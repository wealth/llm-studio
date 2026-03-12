namespace LLMStudio.HuggingFace {

    public class HFClient : Object {
        private Soup.Session  session;
        private GLib.Settings settings;

        private const string API_BASE = "https://huggingface.co/api";
        private const string CDN_BASE = "https://huggingface.co";

        /* Avatar cache: author → texture (successful fetches only) */
        private GLib.HashTable<string, Gdk.Texture> avatar_cache;
        /* Authors whose avatar fetch failed — don't retry */
        private GLib.HashTable<string, bool>        avatar_failed;

        public HFClient (GLib.Settings settings) {
            this.settings     = settings;
            session = new Soup.Session ();
            session.user_agent = "LLMStudio/0.1";
            session.timeout    = 30;
            avatar_cache  = new GLib.HashTable<string, Gdk.Texture> (str_hash, str_equal);
            avatar_failed = new GLib.HashTable<string, bool>         (str_hash, str_equal);
        }

        private string? get_token () {
            var tok = settings.get_string ("hf-token");
            return tok == "" ? null : tok;
        }

        private void add_auth (Soup.Message msg) {
            var tok = get_token ();
            if (tok != null)
                msg.request_headers.replace ("Authorization", "Bearer " + tok);
        }

        private async GLib.Bytes session_fetch (Soup.Message msg, GLib.Cancellable? cancel = null) throws Error {
            return yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancel);
        }

        public async GLib.List<HFModel> search_models (
            string  query,
            string? filter_lib = null,
            int     limit      = 20,
            int     offset     = 0
        ) throws Error {
            var url = new GLib.StringBuilder ();
            url.append (API_BASE);
            url.append ("/models?sort=downloads&direction=-1");
            url.append ("&limit=%d".printf (limit));
            url.append ("&offset=%d".printf (offset));
            if (query != "")        url.append ("&search=" + GLib.Uri.escape_string (query, null, false));
            // Use both library= and filter= for best coverage on HF API
            if (filter_lib != null) {
                url.append ("&library=" + GLib.Uri.escape_string (filter_lib, null, false));
                url.append ("&filter="  + GLib.Uri.escape_string (filter_lib, null, false));
            }
            url.append ("&full=true");

            var msg = new Soup.Message ("GET", url.str);
            add_auth (msg);
            var bytes = yield session_fetch (msg, null);
            check_status (msg);

            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data ());
            var root   = parser.get_root ();
            var result = new GLib.List<HFModel> ();
            if (root.get_node_type () == Json.NodeType.ARRAY) {
                root.get_array ().foreach_element ((arr, i, node) => {
                    if (node.get_node_type () == Json.NodeType.OBJECT)
                        result.append (HFModel.from_json (node.get_object ()));
                });
            }
            return (owned) result;
        }

        public async HFModel get_model_info (string model_id) throws Error {
            var msg = new Soup.Message ("GET", "%s/models/%s".printf (API_BASE, model_id));
            add_auth (msg);
            var bytes = yield session_fetch (msg, null);
            check_status (msg);

            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data ());
            var root = parser.get_root ();
            if (root.get_node_type () != Json.NodeType.OBJECT)
                throw new IOError.FAILED ("Unexpected response format");
            var model = HFModel.from_json (root.get_object ());

            /* Populate file sizes from the tree endpoint. */
            try {
                var sizes = yield fetch_file_sizes (model_id);
                foreach (var sib in model.siblings) {
                    if (sizes.contains (sib.filename))
                        sib.size = sizes.get (sib.filename);
                }
            } catch (Error e) {
                warning ("Could not fetch file sizes for %s: %s", model_id, e.message);
            }

            return model;
        }

        /* Returns filename → size map from /api/models/{id}/tree/main */
        private async GLib.HashTable<string, int64?> fetch_file_sizes (string model_id) throws Error {
            var url = "%s/models/%s/tree/main".printf (API_BASE, model_id);
            var msg = new Soup.Message ("GET", url);
            add_auth (msg);
            var bytes = yield session_fetch (msg, null);
            check_status (msg);

            var sizes = new GLib.HashTable<string, int64?> (str_hash, str_equal);
            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data ());
            var root = parser.get_root ();
            if (root.get_node_type () != Json.NodeType.ARRAY) return sizes;

            root.get_array ().foreach_element ((arr, i, node) => {
                if (node.get_node_type () != Json.NodeType.OBJECT) return;
                var obj = node.get_object ();
                if (!obj.has_member ("path")) return;
                string path = obj.get_string_member ("path");
                int64 size = 0;
                /* LFS files carry their real size in lfs.size */
                if (obj.has_member ("lfs") &&
                    obj.get_member ("lfs").get_node_type () == Json.NodeType.OBJECT) {
                    var lfs = obj.get_object_member ("lfs");
                    if (lfs.has_member ("size"))
                        size = lfs.get_int_member ("size");
                }
                /* Non-LFS files have a direct size field */
                if (size == 0 && obj.has_member ("size"))
                    size = obj.get_int_member ("size");
                if (size > 0)
                    sizes.insert (path, size);
            });

            return sizes;
        }

        public async DownloadTask download_file (
            string model_id,
            string filename,
            string dest_dir
        ) throws Error {
            GLib.DirUtils.create_with_parents (dest_dir, 0755);
            var dest_path = GLib.Path.build_filename (dest_dir, GLib.Path.get_basename (filename));
            var url = "%s/%s/resolve/main/%s".printf (
                CDN_BASE, model_id,
                GLib.Uri.escape_string (filename, "/", false));

            var task = new DownloadTask ();
            task.model_id  = model_id;
            task.filename  = filename;
            task.dest_path = dest_path;
            do_download.begin (url, task);
            return task;
        }

        private async void do_download (string url, DownloadTask task) {
            try {
                var msg = new Soup.Message ("GET", url);
                add_auth (msg);

                // Check for partial download to resume
                int64 resume_from = 0;
                var tmp_path = task.dest_path + ".part";
                if (GLib.FileUtils.test (tmp_path, GLib.FileTest.EXISTS)) {
                    try {
                        var finfo = GLib.File.new_for_path (tmp_path)
                            .query_info ("standard::size", GLib.FileQueryInfoFlags.NONE);
                        resume_from = finfo.get_size ();
                        if (resume_from > 0) {
                            msg.request_headers.replace ("Range", "bytes=%lld-".printf (resume_from));
                            task.downloaded = resume_from;
                        }
                    } catch (Error e) {}
                }

                var istream = yield session.send_async (msg, GLib.Priority.DEFAULT, task.cancellable);
                check_status (msg);

                int64 content_length = msg.response_headers.get_content_length ();
                task.total_size = resume_from + content_length;

                var file = GLib.File.new_for_path (tmp_path);
                GLib.OutputStream ostream;
                if (resume_from > 0) {
                    ostream = yield file.append_to_async (GLib.FileCreateFlags.NONE,
                        GLib.Priority.DEFAULT, task.cancellable);
                } else {
                    ostream = yield file.replace_async (null, false,
                        GLib.FileCreateFlags.REPLACE_DESTINATION,
                        GLib.Priority.DEFAULT, task.cancellable);
                }

                var buf = new uint8[65536];
                while (!task.cancellable.is_cancelled ()) {
                    ssize_t read = yield istream.read_async (buf, GLib.Priority.DEFAULT, task.cancellable);
                    if (read <= 0) break;
                    yield ostream.write_all_async (buf[0:read], GLib.Priority.DEFAULT, task.cancellable, null);
                    task.downloaded += read;
                }
                yield ostream.close_async ();
                yield istream.close_async ();

                if (!task.cancellable.is_cancelled ()) {
                    yield GLib.File.new_for_path (tmp_path).move_async (
                        GLib.File.new_for_path (task.dest_path),
                        GLib.FileCopyFlags.OVERWRITE,
                        GLib.Priority.DEFAULT, null, null);
                    task.completed = true;
                }
            } catch (Error e) {
                if (!task.cancelled) {
                    task.failed    = true;
                    task.error_msg = e.message;
                    warning ("Download failed for %s: %s", task.filename, e.message);
                }
            }
        }

        /* Fetch and cache the avatar for an HF author/org.
           Returns null silently if not available or on error. */
        public async Gdk.Texture? fetch_avatar (string author) {
            if (avatar_cache.contains (author))  return avatar_cache.get (author);
            if (avatar_failed.contains (author)) return null;

            try {
                var url = "%s/%s/picture".printf (CDN_BASE, author);
                var msg = new Soup.Message ("GET", url);
                add_auth (msg);
                var bytes = yield session_fetch (msg, null);
                if (msg.status_code != 200) {
                    avatar_failed.insert (author, true);
                    return null;
                }

                var texture = Gdk.Texture.from_bytes (bytes);
                avatar_cache.insert (author, texture);
                return texture;
            } catch (Error e) {
                avatar_failed.insert (author, true);
                return null;
            }
        }

        private void check_status (Soup.Message msg) throws Error {
            var code = msg.status_code;
            if (code == 401) throw new IOError.PERMISSION_DENIED ("HuggingFace: Authentication required.");
            if (code == 404) throw new IOError.NOT_FOUND ("HuggingFace: Not found.");
            if (code >= 400) throw new IOError.FAILED ("HuggingFace API error: HTTP %u".printf (code));
        }
    }
}

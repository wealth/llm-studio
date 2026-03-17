namespace LLMStudio.HuggingFace {

    public class HFModelFile : Object {
        public string  filename  { get; set; default = ""; }
        public int64   size      { get; set; default = 0;  }
        public string? blob_id  { get; set; default = null; }
        public string  lfs_sha  { get; set; default = ""; }

        public string format_size () {
            if (size <= 0) return "?";
            double gb = size / (1024.0 * 1024.0 * 1024.0);
            if (gb >= 1.0) return "%.1f GB".printf (gb);
            double mb = size / (1024.0 * 1024.0);
            return "%.0f MB".printf (mb);
        }

        public ModelFormat get_model_format () {
            return ModelFormat.from_filename (filename);
        }

        public bool is_model_file () {
            return get_model_format () != ModelFormat.UNKNOWN;
        }
    }

    public class HFModel : Object {
        public string    id             { get; set; default = ""; }
        public string    author         { get; set; default = ""; }
        public string    model_name     { get; set; default = ""; }
        public string?   description    { get; set; default = null; }
        public int64     downloads      { get; set; default = 0;    }
        public int64     likes          { get; set; default = 0;    }
        public string?   pipeline_tag   { get; set; default = null; }
        public string?   library_name   { get; set; default = null; }
        public int64     last_modified  { get; set; default = 0;    }
        public GLib.List<string>      tags;
        public GLib.List<HFModelFile> siblings;

        construct {
            tags      = new GLib.List<string> ();
            siblings  = new GLib.List<HFModelFile> ();
        }

        public bool has_gguf () {
            foreach (var s in siblings) {
                if (s.get_model_format () == ModelFormat.GGUF) return true;
            }
            return false;
        }

        public GLib.List<HFModelFile> get_gguf_files () {
            var result = new GLib.List<HFModelFile> ();
            foreach (var s in siblings) {
                if (s.get_model_format () == ModelFormat.GGUF)
                    result.append (s);
            }
            return result;
        }

        /* Returns true when the repo contains at least one mmproj-*.gguf file. */
        public bool has_mmproj () {
            foreach (var s in siblings) {
                string n = s.filename.down ();
                if (n.has_prefix ("mmproj") && n.has_suffix (".gguf")) return true;
            }
            return false;
        }

        /* Returns the best mmproj file: BF16 > F16 > first found. */
        public HFModelFile? get_best_mmproj () {
            HFModelFile? best_bf16 = null;
            HFModelFile? best_f16  = null;
            HFModelFile? first     = null;
            foreach (var s in siblings) {
                string n = s.filename.down ();
                if (!n.has_prefix ("mmproj") || !n.has_suffix (".gguf")) continue;
                if (first == null) first = s;
                if (n.contains ("bf16")) { best_bf16 = s; break; }
                if (n.contains ("f16"))    best_f16  = s;
            }
            return best_bf16 ?? best_f16 ?? first;
        }

        // Groups GGUF siblings (excluding mmproj) by quant, merging multi-part sets.
        public GLib.List<HFModelFileGroup> get_gguf_file_groups () {
            var groups    = new GLib.HashTable<string, HFModelFileGroup> (str_hash, str_equal);
            var order     = new GLib.List<string> ();

            foreach (var sib in siblings) {
                if (sib.get_model_format () != ModelFormat.GGUF) continue;
                if (sib.filename.down ().contains ("mmproj")) continue;

                string stem = sib.filename.has_suffix (".gguf")
                    ? sib.filename.substring (0, sib.filename.length - 5) : sib.filename;
                string base_stem = ModelInfo.strip_part_suffix (stem);

                if (!groups.contains (base_stem)) {
                    var grp      = new HFModelFileGroup ();
                    grp.base_stem = base_stem;
                    grp.quant    = ModelInfo.extract_quant_from_stem (base_stem);
                    groups.set (base_stem, grp);
                    order.append (base_stem);
                }

                var grp = groups.get (base_stem);
                grp.files.append (sib);
                grp.total_size += sib.size;
            }

            var result = new GLib.List<HFModelFileGroup> ();
            foreach (var key in order)
                result.append (groups.get (key));
            return result;
        }

        public string format_downloads () {
            if (downloads >= 1000000)
                return "%.1fM".printf (downloads / 1000000.0);
            if (downloads >= 1000)
                return "%.0fK".printf (downloads / 1000.0);
            return downloads.to_string ();
        }

        public string short_id () {
            var parts = id.split ("/");
            return parts[parts.length - 1];
        }

        public static HFModel from_json (Json.Object obj) {
            var m = new HFModel ();
            if (obj.has_member ("id"))          m.id           = obj.get_string_member ("id");
            if (obj.has_member ("author"))      m.author       = obj.get_string_member ("author");
            if (obj.has_member ("modelId"))     m.model_name   = obj.get_string_member ("modelId");
            if (obj.has_member ("description")) m.description  = obj.get_string_member ("description");
            if (obj.has_member ("downloads"))   m.downloads    = obj.get_int_member ("downloads");
            if (obj.has_member ("likes"))       m.likes        = obj.get_int_member ("likes");
            if (obj.has_member ("pipeline_tag"))m.pipeline_tag = obj.get_string_member ("pipeline_tag");
            if (obj.has_member ("library_name"))m.library_name = obj.get_string_member ("library_name");

            if (m.model_name == "") {
                var parts = m.id.split ("/");
                m.model_name = parts[parts.length - 1];
            }

            if (obj.has_member ("tags") && obj.get_member ("tags").get_node_type () == Json.NodeType.ARRAY) {
                obj.get_array_member ("tags").foreach_element ((arr, i, node) => {
                    m.tags.append (node.get_string ());
                });
            }

            if (obj.has_member ("siblings") && obj.get_member ("siblings").get_node_type () == Json.NodeType.ARRAY) {
                obj.get_array_member ("siblings").foreach_element ((arr, i, node) => {
                    if (node.get_node_type () != Json.NodeType.OBJECT) return;
                    var sib_obj = node.get_object ();
                    var f = new HFModelFile ();
                    if (sib_obj.has_member ("rfilename")) f.filename = sib_obj.get_string_member ("rfilename");
                    // Top-level size (non-LFS files)
                    if (sib_obj.has_member ("size") && sib_obj.get_int_member ("size") > 0)
                        f.size = sib_obj.get_int_member ("size");
                    // LFS size takes priority for large tracked files
                    if (sib_obj.has_member ("lfs") && sib_obj.get_member ("lfs").get_node_type () == Json.NodeType.OBJECT) {
                        var lfs = sib_obj.get_object_member ("lfs");
                        if (lfs.has_member ("size") && lfs.get_int_member ("size") > 0)
                            f.size = lfs.get_int_member ("size");
                    }
                    m.siblings.append (f);
                });
            }

            return m;
        }
    }

    // A logical quant entry: one or more files that together form a single model weight.
    public class HFModelFileGroup : Object {
        public string base_stem  { get; set; default = ""; }  // stem after stripping part suffix
        public string quant      { get; set; default = ""; }
        public int64  total_size { get; set; default = 0;  }
        public GLib.List<HFModelFile> files;

        construct { files = new GLib.List<HFModelFile> (); }

        public int part_count () { return (int) files.length (); }

        public string format_size () {
            if (total_size <= 0) return "?";
            double gb = total_size / (1024.0 * 1024.0 * 1024.0);
            if (gb >= 1.0) return "%.1f GB".printf (gb);
            double mb = total_size / (1024.0 * 1024.0);
            return "%.0f MB".printf (mb);
        }

        // Display name with quant suffix stripped (quant shown separately as badge).
        public string display_name () {
            string name = base_stem;
            if (quant != "") {
                string up = name.ascii_up ();
                foreach (string sep in new string[] {"-", ".", "_"}) {
                    if (up.has_suffix (sep + quant)) {
                        name = name.substring (0, name.length - quant.length - 1);
                        break;
                    }
                }
            }
            return name;
        }
    }

    // A set of DownloadTasks that together form one logical model download
    // (multi-part shards + optional mmproj).  One UI row tracks this group.
    public class DownloadGroup : Object {
        public string model_id     { get; set; default = ""; }
        public string model_repo   { get; set; default = ""; }
        public string display_name { get; set; default = ""; }
        public string dest_dir     { get; set; default = ""; }

        // All filenames in this group — used to restart downloads on retry.
        public GLib.List<string>       filenames;
        // Active download tasks — may be replaced on retry.
        public GLib.List<DownloadTask> tasks;

        public signal void progress_changed ();
        // Emitted once when every task has reached a terminal state.
        public signal void all_finished ();

        construct {
            filenames = new GLib.List<string> ();
            tasks     = new GLib.List<DownloadTask> ();
        }

        public void add_task (DownloadTask task) {
            tasks.append (task);
            task.notify["downloaded"].connect (() => {
                GLib.Idle.add (() => { progress_changed (); return false; });
            });
            task.notify["completed"].connect (() => {
                GLib.Idle.add (() => { check_done (); return false; });
            });
            task.notify["failed"].connect (() => {
                GLib.Idle.add (() => { check_done (); return false; });
            });
            task.notify["cancelled"].connect (() => {
                GLib.Idle.add (() => { check_done (); return false; });
            });
        }

        // Replace task list (called before retry so stale task signals are ignored).
        public void clear_tasks () {
            tasks = new GLib.List<DownloadTask> ();
        }

        public int64 get_total_size () {
            int64 s = 0;
            foreach (var t in tasks) s += t.total_size;
            return s;
        }

        public int64 get_downloaded () {
            int64 d = 0;
            foreach (var t in tasks) d += t.downloaded;
            return d;
        }

        // True when every task has settled (completed, failed, or cancelled).
        public bool is_all_terminal () {
            if (tasks.length () == 0) return false;
            foreach (var t in tasks) {
                if (!t.completed && !t.failed && !t.cancelled) return false;
            }
            return true;
        }

        public bool is_all_completed () {
            if (tasks.length () == 0) return false;
            foreach (var t in tasks) if (!t.completed) return false;
            return true;
        }

        public bool has_failures () {
            foreach (var t in tasks) if (t.failed) return true;
            return false;
        }

        public bool has_cancelled () {
            foreach (var t in tasks) if (t.cancelled && !t.completed) return true;
            return false;
        }

        public string? first_error () {
            foreach (var t in tasks)
                if (t.failed && t.error_msg != null) return t.error_msg;
            return null;
        }

        public double get_progress () {
            int64 tot = get_total_size ();
            if (tot <= 0) return 0.0;
            return (double) get_downloaded () / (double) tot;
        }

        public string format_progress () {
            double dl  = get_downloaded () / (1024.0 * 1024.0);
            double tot = get_total_size ()  / (1024.0 * 1024.0);
            if (tot >= 1024.0) return "%.1f / %.1f GB".printf (dl / 1024.0, tot / 1024.0);
            return "%.0f / %.0f MB".printf (dl, tot);
        }

        public string format_total_size () {
            double tot = get_total_size () / (1024.0 * 1024.0);
            if (tot >= 1024.0) return "%.1f GB".printf (tot / 1024.0);
            return "%.0f MB".printf (tot);
        }

        public void cancel_all () {
            foreach (var t in tasks) {
                if (!t.completed && !t.failed) t.cancel ();
            }
        }

        private void check_done () {
            if (!is_all_terminal ()) return;
            all_finished ();
        }
    }

    public class DownloadRecord : Object {
        public string  model_id   { get; set; default = ""; }
        public string  filename   { get; set; default = ""; }
        public string  dest_path  { get; set; default = ""; }
        public string  status     { get; set; default = ""; }  // "in_progress"|"complete"|"failed"|"cancelled"
        public int64   total_size { get; set; default = 0;  }
        public string? error_msg  { get; set; default = null; }
    }

    public class DownloadTask : Object {
        public string     model_id   { get; set; default = ""; }
        public string     filename   { get; set; default = ""; }
        public string     dest_path  { get; set; default = ""; }
        public int64      total_size { get; set; default = 0;  }
        public int64      downloaded { get; set; default = 0;  }
        public bool       completed  { get; set; default = false; }
        public bool       cancelled  { get; set; default = false; }
        public bool       failed     { get; set; default = false; }
        public string?    error_msg  { get; set; default = null; }
        public GLib.Cancellable cancellable { get; set; }

        construct {
            cancellable = new GLib.Cancellable ();
        }

        public double get_progress () {
            if (total_size <= 0) return 0.0;
            return (double) downloaded / (double) total_size;
        }

        public string format_progress () {
            double dl_mb = downloaded / (1024.0 * 1024.0);
            double tot_mb = total_size / (1024.0 * 1024.0);
            if (tot_mb >= 1024.0)
                return "%.1f / %.1f GB".printf (dl_mb / 1024.0, tot_mb / 1024.0);
            return "%.0f / %.0f MB".printf (dl_mb, tot_mb);
        }

        public void cancel () {
            cancellable.cancel ();
            cancelled = true;
        }
    }
}

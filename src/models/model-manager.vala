namespace LLMStudio {

    public class ModelManager : Object {
        private GLib.Settings settings;
        private GLib.ListStore _models;
        private string models_dir;
        private GLib.List<ModelInfo> scan_buffer;

        public GLib.ListStore models { get { return _models; } }

        public signal void model_added   (ModelInfo model);
        public signal void model_removed (ModelInfo model);
        public signal void scan_started  ();
        public signal void scan_finished (int count);

        public ModelManager (GLib.Settings settings) {
            this.settings = settings;
            _models = new GLib.ListStore (typeof (ModelInfo));
            scan_buffer = new GLib.List<ModelInfo> ();

            models_dir = settings.get_string ("models-directory");
            if (models_dir == "") {
                models_dir = GLib.Path.build_filename (
                    GLib.Environment.get_home_dir (),
                    ".local", "share", "llm-studio", "models");
            }

            settings.changed["models-directory"].connect (() => {
                models_dir = settings.get_string ("models-directory");
                if (models_dir == "") {
                    models_dir = GLib.Path.build_filename (
                        GLib.Environment.get_home_dir (),
                        ".local", "share", "llm-studio", "models");
                }
            });
        }

        public string get_models_dir () { return models_dir; }

        public void set_models_dir (string dir) {
            models_dir = dir;
            settings.set_string ("models-directory", dir);
        }

        public async void scan_async () {
            scan_started ();
            scan_buffer = new GLib.List<ModelInfo> ();
            try {
                GLib.DirUtils.create_with_parents (models_dir, 0755);
                yield scan_directory_async (models_dir);
            } catch (Error e) {
                warning ("Scan error: %s", e.message);
            }

            // Build existing path set
            var existing = new GLib.HashTable<string, bool> (str_hash, str_equal);
            for (uint i = 0; i < _models.get_n_items (); i++)
                existing.set (((ModelInfo) _models.get_item (i)).path, true);

            // Add newly found
            foreach (var m in scan_buffer) {
                if (!existing.contains (m.path)) {
                    _models.append (m);
                    model_added (m);
                }
            }

            // Remove missing
            var found_paths = new GLib.HashTable<string, bool> (str_hash, str_equal);
            foreach (var m in scan_buffer) found_paths.set (m.path, true);

            uint i = 0;
            while (i < _models.get_n_items ()) {
                var m = (ModelInfo) _models.get_item (i);
                if (!found_paths.contains (m.path)) {
                    model_removed (m);
                    _models.remove (i);
                } else {
                    i++;
                }
            }

            scan_finished ((int) _models.get_n_items ());
        }

        private async void scan_directory_async (string dir) throws Error {
            var directory = GLib.File.new_for_path (dir);
            var enumerator = yield directory.enumerate_children_async (
                "standard::name,standard::type",
                GLib.FileQueryInfoFlags.NONE,
                GLib.Priority.DEFAULT, null);

            GLib.List<GLib.FileInfo> infos;
            while ((infos = yield enumerator.next_files_async (
                    50, GLib.Priority.DEFAULT, null)).length () > 0) {
                foreach (var info in infos) {
                    var name      = info.get_name ();
                    var full_path = GLib.Path.build_filename (dir, name);

                    if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                        yield scan_directory_async (full_path);
                        continue;
                    }

                    var fmt = ModelFormat.from_filename (name);
                    if (fmt == ModelFormat.UNKNOWN) continue;
                    if (name.has_suffix (".llmstudio.json")) continue;
                    if (name.down ().has_prefix ("mmproj")) continue;  // vision projection sidecar

                    scan_buffer.append (ModelInfo.from_file (full_path));
                }
            }
        }

        public void add_model_path (string path) {
            if (GLib.Path.get_basename (path).down ().has_prefix ("mmproj")) return;
            for (uint i = 0; i < _models.get_n_items (); i++) {
                if (((ModelInfo) _models.get_item (i)).path == path) return;
            }
            var model = ModelInfo.from_file (path);
            _models.append (model);
            model_added (model);
        }

        public void remove_model (ModelInfo model) {
            for (uint i = 0; i < _models.get_n_items (); i++) {
                if (((ModelInfo) _models.get_item (i)).path == model.path) {
                    _models.remove (i);
                    model_removed (model);
                    return;
                }
            }
        }

        public ModelInfo? find_by_path (string path) {
            for (uint i = 0; i < _models.get_n_items (); i++) {
                var m = (ModelInfo) _models.get_item (i);
                if (m.path == path) return m;
            }
            return null;
        }

        public ModelInfo? find_by_id (string id) {
            for (uint i = 0; i < _models.get_n_items (); i++) {
                var m = (ModelInfo) _models.get_item (i);
                if (m.id == id) return m;
            }
            return null;
        }
    }
}

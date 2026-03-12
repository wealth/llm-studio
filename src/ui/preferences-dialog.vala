namespace LLMStudio.UI {

    public class PreferencesDialog : Adw.PreferencesWindow {
        private BackendManager backend_manager;
        private EngineManager  engine_manager;
        private GLib.Settings  settings;

        public PreferencesDialog (BackendManager manager, EngineManager engine_mgr,
                                  GLib.Settings settings, Gtk.Window parent) {
            Object (transient_for: parent, modal: true);
            this.backend_manager = manager;
            this.engine_manager  = engine_mgr;
            this.settings        = settings;
            title = "Preferences";
            build_pages ();
        }

        private void build_pages () {
            add (make_general_page ());
            add (make_backend_page ());
            add (make_huggingface_page ());
        }

        private Adw.PreferencesPage make_general_page () {
            var page = new Adw.PreferencesPage ();
            page.title     = "General";
            page.icon_name = "preferences-system-symbolic";

            // Models directory
            var dirs_group = new Adw.PreferencesGroup ();
            dirs_group.title = "Model Storage";
            page.add (dirs_group);

            var models_dir_row = new Adw.ActionRow ();
            models_dir_row.title    = "Models Directory";
            models_dir_row.subtitle = settings.get_string ("models-directory") == "" ?
                GLib.Path.build_filename (GLib.Environment.get_home_dir (), ".local", "share", "llm-studio", "models") :
                settings.get_string ("models-directory");
            models_dir_row.activatable = true;

            var models_dir_icon = new Gtk.Image.from_icon_name ("folder-open-symbolic");
            models_dir_row.add_suffix (models_dir_icon);
            models_dir_row.activated.connect (() => {
                var dlg = new Gtk.FileDialog ();
                dlg.title = "Select Models Directory";
                dlg.select_folder.begin (this, null, (obj, res) => {
                    try {
                        var folder = dlg.select_folder.end (res);
                        settings.set_string ("models-directory", folder.get_path ());
                        models_dir_row.subtitle = folder.get_path ();
                    } catch (Error e) {}
                });
            });
            dirs_group.add (models_dir_row);

            // HF cache dir
            var hf_cache_row = new Adw.ActionRow ();
            hf_cache_row.title    = "Download Directory";
            hf_cache_row.subtitle = settings.get_string ("hf-cache-dir") == "" ?
                "Same as models directory" : settings.get_string ("hf-cache-dir");
            hf_cache_row.activatable = true;
            var hf_cache_icon = new Gtk.Image.from_icon_name ("folder-open-symbolic");
            hf_cache_row.add_suffix (hf_cache_icon);
            hf_cache_row.activated.connect (() => {
                var dlg = new Gtk.FileDialog ();
                dlg.title = "Select Download Directory";
                dlg.select_folder.begin (this, null, (obj, res) => {
                    try {
                        var folder = dlg.select_folder.end (res);
                        settings.set_string ("hf-cache-dir", folder.get_path ());
                        hf_cache_row.subtitle = folder.get_path ();
                    } catch (Error e) {}
                });
            });
            dirs_group.add (hf_cache_row);

            return page;
        }

        private Adw.PreferencesPage make_backend_page () {
            var page = new Adw.PreferencesPage ();
            page.title     = "Backend";
            page.icon_name = "utilities-terminal-symbolic";

            // Backend type
            var backend_group = new Adw.PreferencesGroup ();
            backend_group.title = "Inference Backend";
            page.add (backend_group);

            var backend_types = new Gtk.StringList (null);
            backend_types.append ("llama.cpp");
            backend_types.append ("ik_llama.cpp");
            backend_types.append ("vLLM");

            var backend_row = new Adw.ComboRow ();
            backend_row.title  = "Backend";
            backend_row.subtitle = "Inference engine to use for model loading";
            backend_row.model  = backend_types;

            switch (settings.get_string ("backend-type")) {
                case "ik-llama": backend_row.selected = 1; break;
                case "vllm":     backend_row.selected = 2; break;
                default:         backend_row.selected = 0; break;
            }

            backend_row.notify["selected"].connect (() => {
                BackendType type;
                switch (backend_row.selected) {
                    case 1:  type = BackendType.IK_LLAMA; break;
                    case 2:  type = BackendType.VLLM;     break;
                    default: type = BackendType.LLAMA;    break;
                }
                backend_manager.switch_backend.begin (type);
            });

            backend_group.add (backend_row);

            // llama.cpp group
            var llama_group = new Adw.PreferencesGroup ();
            llama_group.title = "llama.cpp";
            page.add (llama_group);

            var llama_path_row = new Adw.EntryRow ();
            llama_path_row.title = "llama-server path";
            llama_path_row.text  = settings.get_string ("llama-server-path");
            llama_path_row.changed.connect (() =>
                settings.set_string ("llama-server-path", llama_path_row.text));
            llama_group.add (llama_path_row);

            // ik_llama group
            var ik_group = new Adw.PreferencesGroup ();
            ik_group.title = "ik_llama.cpp";
            page.add (ik_group);

            var ik_path_row = new Adw.EntryRow ();
            ik_path_row.title = "ik-llama-server path";
            ik_path_row.text  = settings.get_string ("ik-llama-server-path");
            ik_path_row.changed.connect (() =>
                settings.set_string ("ik-llama-server-path", ik_path_row.text));
            ik_group.add (ik_path_row);

            // vllm group
            var vllm_group = new Adw.PreferencesGroup ();
            vllm_group.title = "vLLM";
            page.add (vllm_group);

            var vllm_host_row = new Adw.EntryRow ();
            vllm_host_row.title = "vLLM Server URL";
            vllm_host_row.text  = settings.get_string ("vllm-host");
            vllm_host_row.changed.connect (() =>
                settings.set_string ("vllm-host", vllm_host_row.text));
            vllm_group.add (vllm_host_row);

            var vllm_managed_row = new Adw.SwitchRow ();
            vllm_managed_row.title    = "Managed Mode";
            vllm_managed_row.subtitle = "Launch and manage the vLLM process automatically";
            vllm_managed_row.active   = settings.get_boolean ("vllm-managed");
            vllm_managed_row.notify["active"].connect (() =>
                settings.set_boolean ("vllm-managed", vllm_managed_row.active));
            vllm_group.add (vllm_managed_row);

            // Engine installer
            var engine_group = new Adw.PreferencesGroup ();
            engine_group.title       = "Inference Engine";
            engine_group.description = "Download or reinstall the llama.cpp server binary with the correct GPU variant.";
            page.add (engine_group);

            var detected     = engine_manager.detect_gpu ();
            var install_row  = new Adw.ActionRow ();
            install_row.title      = "Reinstall Engine";
            install_row.subtitle   = "Auto-detected: %s".printf (detected.label ());
            install_row.activatable = true;
            install_row.add_suffix (new Gtk.Image.from_icon_name ("folder-download-symbolic"));
            install_row.activated.connect (() => {
                do_reinstall_engine.begin ();
            });
            engine_group.add (install_row);

            return page;
        }

        private async void do_reinstall_engine () {
            EngineRelease? release = null;
            try {
                release = yield engine_manager.check_latest (engine_manager.detect_gpu ());
            } catch (Error e) {
                // show error toast if possible
                return;
            }
            if (release == null) return;

            var detected = engine_manager.detect_gpu ();
            var dlg = new EngineInstallDialog (release, engine_manager, detected, this);
            dlg.engine_ready.connect (() => {
                // nothing extra needed
            });
            dlg.present ();
        }

        private Adw.PreferencesPage make_huggingface_page () {
            var page = new Adw.PreferencesPage ();
            page.title     = "HuggingFace";
            page.icon_name = "network-server-symbolic";

            var hf_group = new Adw.PreferencesGroup ();
            hf_group.title       = "Account";
            hf_group.description = "An API token is required to download gated models.";
            page.add (hf_group);

            var token_row = new Adw.PasswordEntryRow ();
            token_row.title = "API Token";
            token_row.text  = settings.get_string ("hf-token");
            token_row.changed.connect (() =>
                settings.set_string ("hf-token", token_row.text));
            hf_group.add (token_row);

            var token_help = new Adw.ActionRow ();
            token_help.title    = "Get your token";
            token_help.subtitle = "huggingface.co/settings/tokens";
            token_help.activatable = true;
            token_help.add_suffix (new Gtk.Image.from_icon_name ("external-link-symbolic"));
            token_help.activated.connect (() => {
                GLib.AppInfo.launch_default_for_uri_async.begin ("https://huggingface.co/settings/tokens", null, null, null);
            });
            hf_group.add (token_help);

            return page;
        }
    }
}

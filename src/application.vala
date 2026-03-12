namespace LLMStudio {

    public class Application : Adw.Application {
        private GLib.Settings  settings;
        private ModelManager   model_manager;
        private BackendManager backend_manager;
        private HuggingFace.HFClient hf_client;
        private OpenAIServer   api_server;
        private EngineManager  engine_manager;
        private ChatHistory    chat_history;
        private Window?        main_window;

        public Application () {
            Object (
                application_id: "dev.llmstudio.LLMStudio",
                flags: GLib.ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void startup () {
            base.startup ();

            // Initialize settings
            settings = new GLib.Settings ("dev.llmstudio.LLMStudio");

            // Initialize subsystems
            model_manager   = new ModelManager (settings);
            backend_manager = new BackendManager (settings);
            hf_client       = new HuggingFace.HFClient (settings);
            api_server      = new OpenAIServer (backend_manager, settings);
            engine_manager  = new EngineManager (settings);
            chat_history    = new ChatHistory ();

            // Setup actions
            setup_actions ();

            // Load custom CSS
            load_css ();

            // Start API server if it was running
            if (settings.get_boolean ("api-server-enabled")) {
                try {
                    api_server.start ();
                } catch (Error e) {
                    warning ("Could not auto-start API server: %s", e.message);
                }
            }

            // Initial model scan
            model_manager.scan_async.begin ();

            // Engine check runs after the window is shown (activate → engine_check)

        }

        protected override void activate () {
            if (main_window != null) {
                main_window.present ();
                return;
            }

            main_window = new Window (this, settings, model_manager, backend_manager,
                hf_client, api_server, chat_history);
            main_window.present ();

            // Check engine after window is visible
            check_engine_async.begin ();
        }

        private async void check_engine_async () {
            // Small delay so the window fully renders before showing a dialog
            var src = new GLib.TimeoutSource (700);
            src.set_callback (() => { check_engine_async.callback (); return false; });
            src.attach (null);
            yield;

            EngineRelease? release = null;
            string? check_error = null;
            try {
                release = yield engine_manager.check_latest ();
            } catch (Error e) {
                check_error = e.message;
                warning ("Engine version check failed: %s", e.message);
            }

            var detected_gpu = engine_manager.detect_gpu ();
            bool installed = engine_manager.engine_installed ();

            if (!installed) {
                if (release == null) {
                    var msg = check_error != null
                        ? "Engine not found. Network error: %s".printf (check_error)
                        : "Engine not found and no release info available.";
                    main_window.show_toast (msg);
                    return;
                }
                var dlg = new UI.EngineInstallDialog (release, engine_manager, detected_gpu, main_window);
                dlg.engine_ready.connect (() => {
                    main_window.show_toast ("llama.cpp engine ready!");
                });
                dlg.present ();
            } else if (release != null && engine_manager.is_newer (release.tag)) {
                var skip_tag = settings.get_string ("engine-skip-version");
                if (skip_tag == release.tag) return;

                var dlg = new UI.EngineUpdateDialog (
                    release, engine_manager, main_window,
                    engine_manager.installed_version);

                dlg.update_accepted.connect (() => {
                    var install_dlg = new UI.EngineInstallDialog (
                        release, engine_manager, detected_gpu, main_window);
                    install_dlg.engine_ready.connect (() => {
                        main_window.show_toast (
                            "Engine updated to %s!".printf (release.tag));
                    });
                    install_dlg.present ();
                });
                dlg.update_skipped.connect ((tag) => {
                    settings.set_string ("engine-skip-version", tag);
                });
                dlg.present ();
            }
        }

        private void setup_actions () {
            // Quit
            var quit_action = new GLib.SimpleAction ("quit", null);
            quit_action.activate.connect (() => {
                quit_gracefully.begin ();
            });
            add_action (quit_action);
            set_accels_for_action ("app.quit", {"<Control>q"});

            // New chat
            var new_chat_action = new GLib.SimpleAction ("new-chat", null);
            new_chat_action.activate.connect (() => {
                backend_manager.clear_conversation ();
                if (main_window != null) main_window.navigate_to (UI.SidebarPage.CHAT);
            });
            add_action (new_chat_action);
            set_accels_for_action ("app.new-chat", {"<Control>n"});

            // Preferences
            var prefs_action = new GLib.SimpleAction ("preferences", null);
            prefs_action.activate.connect (() => {
                if (main_window != null) {
                    var prefs = new UI.PreferencesDialog (backend_manager, engine_manager, settings, main_window);
                    prefs.present ();
                }
            });
            add_action (prefs_action);
            set_accels_for_action ("app.preferences", {"<Control>comma"});

            // About
            var about_action = new GLib.SimpleAction ("about", null);
            about_action.activate.connect (show_about);
            add_action (about_action);

            // Load model (unload current first)
            var unload_action = new GLib.SimpleAction ("unload-model", null);
            unload_action.activate.connect (() => {
                backend_manager.unload_model.begin ();
            });
            add_action (unload_action);
        }

        private void load_css () {
            var provider = new Gtk.CssProvider ();
            provider.load_from_string ("""
                .message-user {
                    background-color: @card_bg_color;
                    border-radius: 18px;
                }
                .badge {
                    border-radius: 99px;
                    padding: 2px 8px;
                    font-size: smaller;
                    font-weight: bold;
                }
                .badge.success {
                    background-color: alpha(@success_color, 0.2);
                    color: @success_color;
                }
                .badge.error {
                    background-color: alpha(@error_color, 0.2);
                    color: @error_color;
                }
                .badge.accent {
                    background-color: alpha(@accent_color, 0.2);
                    color: @accent_color;
                }
                .badge.dim-label {
                    background-color: alpha(@window_fg_color, 0.1);
                }
                .badge.quant {
                    background-color: alpha(@window_fg_color, 0.1);
                    color: @window_fg_color;
                    font-family: monospace;
                }
                .badge.badge-vision {
                    background-color: alpha(@blue_3, 0.2);
                    color: @blue_3;
                }
                .badge.badge-tools {
                    background-color: alpha(@green_4, 0.2);
                    color: @green_4;
                }
                .dl-badge {
                    background: @accent_bg_color;
                    color: @accent_fg_color;
                    border-radius: 99px;
                    font-size: 9px;
                    font-weight: bold;
                    padding: 0 3px;
                    min-width: 14px;
                    min-height: 14px;
                }
                .badge.outlined {
                    background-color: transparent;
                    border: 1px solid alpha(@window_fg_color, 0.3);
                    color: @window_fg_color;
                    font-family: monospace;
                }
                headerbar.flat {
                    min-height: 47px;
                }
                dropdown.model-selector > button {
                    background-color: alpha(@window_fg_color, 0.08);
                    color: @window_fg_color;
                    border-radius: 99px;
                    padding: 2px 16px;
                    box-shadow: none;
                }
                dropdown.model-selector.model-loaded > button {
                    background-color: @accent_bg_color;
                    color: @accent_fg_color;
                }
                @keyframes model-shimmer {
                    0%   { background-color: alpha(@accent_bg_color, 0.15); }
                    50%  { background-color: alpha(@accent_bg_color, 0.55); }
                    100% { background-color: alpha(@accent_bg_color, 0.15); }
                }
                dropdown.model-selector.loading > button {
                    animation: model-shimmer 1.4s ease-in-out infinite;
                    color: @accent_fg_color;
                }
            """);
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private void show_about () {
            var about = new Adw.AboutWindow ();
            about.transient_for    = main_window;
            about.application_name = "LLM Studio";
            about.application_icon = "dev.llmstudio.LLMStudio";
            about.developer_name   = "LLM Studio Contributors";
            about.version          = "0.1.0";
            about.website          = "https://github.com/llmstudio";
            about.comments         = "Run and chat with local language models";
            about.license_type     = Gtk.License.GPL_3_0;
            about.developers       = { "LLM Studio Contributors" };
            about.present ();
        }

        private async void quit_gracefully () {
            // Unload model before exit
            if (backend_manager.loaded_model != null) {
                try {
                    yield backend_manager.unload_model ();
                } catch (Error e) {
                    warning ("Error unloading on quit: %s", e.message);
                }
            }
            api_server.stop ();
            quit ();
        }

        // Accessors for the window
        public ModelManager   get_model_manager   () { return model_manager; }
        public BackendManager get_backend_manager () { return backend_manager; }
        public HuggingFace.HFClient get_hf_client () { return hf_client; }
        public OpenAIServer   get_api_server       () { return api_server; }
        public GLib.Settings  get_settings         () { return settings; }
    }
}

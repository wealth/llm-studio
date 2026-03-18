namespace LLMStudio {

    public class Window : Adw.ApplicationWindow {
        private GLib.Settings  settings;
        private ModelManager   model_manager;
        private BackendManager backend_manager;
        private HuggingFace.HFClient hf_client;
        private OpenAIServer   api_server;
        private ChatHistory    chat_history;
        private ToolManager    tool_manager;

        // UI components
        private Adw.OverlaySplitView split_view;
        private UI.Sidebar           sidebar;
        private Gtk.Stack            content_stack;
        private UI.ChatView          chat_view;
        private UI.ModelBrowser      model_browser;
        private UI.HubSearchView     hub_view;
        private UI.ServerPanel       server_panel;
        private UI.LogsView          logs_view;
        private Adw.ToastOverlay     toast_overlay;
        private GLib.Cancellable?    load_cancel;

        // Header model button
        private Gtk.Button      model_btn;
        private Gtk.Label       model_btn_lbl;
        private Gtk.Button      eject_btn;
        private UI.ChatParamsPanel  params_panel;
        private Gtk.Paned           main_paned;
        private Gtk.ToggleButton    params_toggle_btn;

        public Window (
            Application app,
            GLib.Settings settings,
            ModelManager model_manager,
            BackendManager backend_manager,
            HuggingFace.HFClient hf_client,
            OpenAIServer api_server,
            ChatHistory chat_history
        ) {
            Object (application: app);
            this.settings        = settings;
            this.model_manager   = model_manager;
            this.backend_manager = backend_manager;
            this.hf_client       = hf_client;
            this.api_server      = api_server;
            this.chat_history    = chat_history;
            this.tool_manager    = new ToolManager (settings);

            build_ui ();
            restore_state ();
        }

        private void build_ui () {
            title = "LLM Studio";

            // Create hub_view early so its downloads_widget can be embedded
            // in the header popover below.
            hub_view = new UI.HubSearchView (hf_client, model_manager, settings);

            // Root: toast overlay → single top-level ToolbarView so the header
            // spans the full window width (no separate sidebar header).
            toast_overlay = new Adw.ToastOverlay ();
            set_content (toast_overlay);

            var root_toolbar = new Adw.ToolbarView ();
            toast_overlay.set_child (root_toolbar);

            // ── Single full-width header ─────────────────────────────────────
            var content_header = new Adw.HeaderBar ();
            content_header.add_css_class ("flat");

            // Sidebar toggle
            var sidebar_btn = new Gtk.ToggleButton ();
            sidebar_btn.icon_name    = "sidebar-show-symbolic";
            sidebar_btn.tooltip_text = "Toggle Sidebar";
            sidebar_btn.add_css_class ("flat");
            content_header.pack_start (sidebar_btn);

            // Model selector button (title widget)
            model_btn_lbl = new Gtk.Label ("Load Model");
            model_btn_lbl.ellipsize = Pango.EllipsizeMode.END;

            var arrow_icon = new Gtk.Image.from_icon_name ("pan-down-symbolic");
            arrow_icon.add_css_class ("dim-label");
            arrow_icon.pixel_size = 12;

            var btn_inner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            btn_inner.halign = Gtk.Align.CENTER;
            btn_inner.valign = Gtk.Align.CENTER;
            btn_inner.append (model_btn_lbl);
            btn_inner.append (arrow_icon);

            model_btn = new Gtk.Button ();
            model_btn.set_child (btn_inner);
            model_btn.add_css_class ("model-selector");
            model_btn.width_request = 360;
            model_btn.clicked.connect (on_model_btn_clicked);

            eject_btn = new Gtk.Button.from_icon_name ("media-eject-symbolic");
            eject_btn.tooltip_text = "Unload model";
            eject_btn.add_css_class ("flat");
            eject_btn.sensitive = false;
            eject_btn.clicked.connect (() => backend_manager.unload_model.begin ());

            var title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            title_box.valign = Gtk.Align.CENTER;
            title_box.append (model_btn);
            title_box.append (eject_btn);
            content_header.set_title_widget (title_box);

            // Downloads popover button
            var dl_popover = new Gtk.Popover ();
            dl_popover.set_child (hub_view.downloads_widget);

            var dl_btn = new Gtk.MenuButton ();
            dl_btn.icon_name    = "folder-download-symbolic";
            dl_btn.tooltip_text = "Downloads";
            dl_btn.add_css_class ("flat");
            dl_btn.popover = dl_popover;

            var dl_badge = new Gtk.Label ("");
            dl_badge.add_css_class ("dl-badge");
            dl_badge.halign  = Gtk.Align.END;
            dl_badge.valign  = Gtk.Align.START;
            dl_badge.visible = false;

            var dl_overlay = new Gtk.Overlay ();
            dl_overlay.set_child (dl_btn);
            dl_overlay.add_overlay (dl_badge);
            content_header.pack_end (dl_overlay);

            hub_view.active_count_changed.connect ((count) => {
                dl_badge.label   = count.to_string ();
                dl_badge.visible = count > 0;
            });

            // Parameters panel toggle (right side, before menu)
            params_toggle_btn = new Gtk.ToggleButton ();
            params_toggle_btn.icon_name    = "sidebar-show-symbolic";
            params_toggle_btn.tooltip_text = "Toggle Parameters Panel";
            params_toggle_btn.add_css_class ("flat");
            params_toggle_btn.active = true;
            params_toggle_btn.toggled.connect (() => {
                if (sidebar.current_page == UI.SidebarPage.CHAT)
                    params_panel.visible = params_toggle_btn.active;
            });
            content_header.pack_end (params_toggle_btn);

            root_toolbar.add_top_bar (content_header);
            root_toolbar.add_top_bar (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // ── Split view (below the single header) ────────────────────────
            split_view = new Adw.OverlaySplitView ();
            split_view.sidebar_position       = Gtk.PackType.START;
            split_view.min_sidebar_width      = 240;
            split_view.max_sidebar_width      = 340;
            split_view.sidebar_width_fraction = 0.24;

            // Sidebar goes directly — no own header bar
            sidebar = new UI.Sidebar (backend_manager, chat_history);
            sidebar.page_changed.connect (on_page_changed);
            sidebar.new_chat_requested.connect (() => {
                chat_view.new_chat ();
                navigate_to (UI.SidebarPage.CHAT);
            });
            sidebar.session_selected.connect (s => {
                chat_view.load_session (s);
                navigate_to (UI.SidebarPage.CHAT);
            });
            sidebar.session_delete_requested.connect (s => {
                chat_history.delete_session (s);
                if (chat_history.current != null)
                    chat_view.load_session (chat_history.current);
                else {
                    var new_s = chat_history.new_session ();
                    chat_view.load_session (new_s);
                }
                navigate_to (UI.SidebarPage.CHAT);
            });
            split_view.set_sidebar (sidebar);

            // Content stack (the main pages)
            content_stack = new Gtk.Stack ();
            content_stack.transition_type     = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            content_stack.transition_duration = 200;
            content_stack.hexpand = true;
            content_stack.vexpand = true;

            // Main body: resizable paned split — content stack | params panel
            params_panel = new UI.ChatParamsPanel (backend_manager, tool_manager);

            main_paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            main_paned.start_child        = content_stack;
            main_paned.end_child          = params_panel;
            main_paned.resize_start_child = true;
            main_paned.resize_end_child   = false;
            main_paned.shrink_start_child = false;
            main_paned.shrink_end_child   = false;
            split_view.set_content (main_paned);

            root_toolbar.set_content (split_view);

            // ── Pages ────────────────────────────────────────────────────────
            chat_view = new UI.ChatView (backend_manager, settings, chat_history, tool_manager);
            chat_view.show_toast.connect (show_toast);
            content_stack.add_named (chat_view, "chat");

            model_browser = new UI.ModelBrowser (model_manager, backend_manager, settings);
            model_browser.load_model_requested.connect (on_load_model_requested);
            model_browser.open_hub_requested.connect (() => navigate_to (UI.SidebarPage.HUB));
            content_stack.add_named (model_browser, "models");

            content_stack.add_named (hub_view, "hub");

            server_panel = new UI.ServerPanel (api_server, backend_manager, settings);
            content_stack.add_named (server_panel, "server");

            logs_view = new UI.LogsView (backend_manager);
            content_stack.add_named (logs_view, "logs");

            // ── Bindings & signals ───────────────────────────────────────────
            sidebar_btn.bind_property ("active", split_view, "show-sidebar",
                GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);
            split_view.show_sidebar = true;
            sidebar_btn.active      = true;

            backend_manager.status_changed.connect (s => {
                bool busy = (s == BackendStatus.LOADING || s == BackendStatus.UNLOADING);
                model_btn.sensitive = !busy;
                if (busy) {
                    model_btn.add_css_class ("loading");
                } else {
                    model_btn.remove_css_class ("loading");
                }
                eject_btn.sensitive = (s == BackendStatus.READY);
            });

            backend_manager.model_loaded.connect (m => {
                var pub = m.publisher ();
                model_btn_lbl.label = pub != "" ? pub + "/" + m.clean_name ().down ()
                                                : m.clean_name ().down ();
                model_btn.add_css_class ("model-loaded");
                eject_btn.sensitive = true;
            });

            backend_manager.model_unloaded.connect (() => {
                model_btn_lbl.label = "Load Model";
                model_btn.remove_css_class ("model-loaded");
                eject_btn.sensitive = false;
            });

            close_request.connect (on_close_request);

            // On startup the sidebar already has the first session selected (visual-only),
            // but the session_selected signal fired during construction before our handler
            // was connected. Load the session explicitly here.
            if (chat_history.current != null)
                chat_view.load_session (chat_history.current);
        }

        private void restore_state () {
            int w = settings.get_int ("window-width");
            int h = settings.get_int ("window-height");
            if (w > 100 && h > 100) set_default_size (w, h);
            else set_default_size (1280, 840);

            if (settings.get_boolean ("window-maximized")) maximize ();
        }

        private bool on_close_request () {
            int w, h;
            get_default_size (out w, out h);
            settings.set_int     ("window-width",     w);
            settings.set_int     ("window-height",    h);
            settings.set_boolean ("window-maximized", is_maximized ());

            if (backend_manager.loaded_model != null) {
                do_close_async.begin ();
                return true;   /* block immediate close; async will destroy() */
            }
            return false;
        }

        private async void do_close_async () {
            try {
                yield backend_manager.unload_model ();
            } catch (Error e) {
                warning ("Error unloading model on close: %s", e.message);
            }
            destroy ();
        }

        private void on_page_changed (UI.SidebarPage page) {
            content_stack.visible_child_name = page.to_string ();
            params_panel.visible = (page == UI.SidebarPage.CHAT) && params_toggle_btn.active;
        }

        public void navigate_to (UI.SidebarPage page) {
            sidebar.current_page             = page;
            content_stack.visible_child_name = page.to_string ();
            params_panel.visible = (page == UI.SidebarPage.CHAT) && params_toggle_btn.active;
        }

        private void on_load_model_requested (ModelInfo model) {
            var dialog = new UI.ModelLoadDialog (model, this);
            dialog.load_requested.connect (on_load_confirmed);
            dialog.present ();
        }

        private void on_load_confirmed (ModelInfo model, ModelParams params) {
            load_cancel?.cancel ();
            load_cancel = new GLib.Cancellable ();
            do_load_model.begin (model, params);
        }

        private async void do_load_model (ModelInfo model, ModelParams params) {
            try {
                yield backend_manager.load_model (model, params, load_cancel);
                navigate_to (UI.SidebarPage.CHAT);
            } catch (Error e) {
                if (!(e is IOError.CANCELLED))
                    show_error_dialog ("Failed to load model", e.message);
            }
        }

        private void show_error_dialog (string title, string message) {
            var dialog = new Adw.MessageDialog (this, title, message);
            dialog.add_response ("ok", "OK");
            dialog.default_response = "ok";
            dialog.present ();
        }

        public void show_toast (string message) {
            var toast = new Adw.Toast (message);
            toast.timeout = 3;
            toast_overlay.add_toast (toast);
        }

        private void on_model_btn_clicked () {
            var dialog = new UI.ModelPickerDialog (model_manager, backend_manager, this);
            dialog.load_requested.connect (on_load_confirmed);
            dialog.present ();
        }
    }
}

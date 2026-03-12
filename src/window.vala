namespace LLMStudio {

    // Thin wrapper used as items in the header model-picker ListStore.
    // model == null means the placeholder "— Select model —" entry.
    private class ModelPickerItem : Object {
        public ModelInfo? model { get; construct; }
        public ModelPickerItem (ModelInfo? m) { Object (model: m); }
    }

    public class Window : Adw.ApplicationWindow {
        private GLib.Settings  settings;
        private ModelManager   model_manager;
        private BackendManager backend_manager;
        private HuggingFace.HFClient hf_client;
        private OpenAIServer   api_server;
        private ChatHistory    chat_history;

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

        // Header model selector
        private GLib.ListStore  dropdown_store;
        private Gtk.DropDown    model_dropdown;
        private Gtk.Button      eject_btn;
        private bool            model_list_updating = false;
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

            build_ui ();
            restore_state ();
        }

        private void build_ui () {
            title = "LLM Studio";

            // Create hub_view early so its downloads_widget can be embedded
            // in the header popover below.
            hub_view = new UI.HubSearchView (hf_client, model_manager, settings);

            // Root: toast overlay → split view directly (no spanning top header)
            toast_overlay = new Adw.ToastOverlay ();
            set_content (toast_overlay);

            // Split view fills the entire window, including the title-bar row
            split_view = new Adw.OverlaySplitView ();
            split_view.sidebar_position       = Gtk.PackType.START;
            split_view.min_sidebar_width      = 240;
            split_view.max_sidebar_width      = 340;
            split_view.sidebar_width_fraction = 0.24;
            toast_overlay.set_child (split_view);

            // ── Sidebar panel ────────────────────────────────────────────────
            // Give the sidebar its own ToolbarView + HeaderBar so it occupies
            // the full window height (Builder-style layout).
            var sidebar_toolbar = new Adw.ToolbarView ();

            var sidebar_header = new Adw.HeaderBar ();
            sidebar_header.add_css_class ("flat");
            // No window-decoration buttons here — they live in the content header
            sidebar_header.decoration_layout = "";

            var app_name_lbl = new Gtk.Label ("LLM Studio");
            app_name_lbl.add_css_class ("heading");
            sidebar_header.set_title_widget (app_name_lbl);

            sidebar_toolbar.add_top_bar (sidebar_header);
            sidebar_toolbar.add_top_bar (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

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
            sidebar_toolbar.set_content (sidebar);

            split_view.set_sidebar (sidebar_toolbar);

            // ── Content panel ────────────────────────────────────────────────
            var content_toolbar = new Adw.ToolbarView ();

            var content_header = new Adw.HeaderBar ();
            content_header.add_css_class ("flat");
            // Window decoration buttons only in the content header
            content_header.show_start_title_buttons = false;

            // Sidebar toggle
            var sidebar_btn = new Gtk.ToggleButton ();
            sidebar_btn.icon_name    = "sidebar-show-symbolic";
            sidebar_btn.tooltip_text = "Toggle Sidebar";
            sidebar_btn.add_css_class ("flat");
            content_header.pack_start (sidebar_btn);

            // Model selector (title widget — visible on all tabs)
            dropdown_store = new GLib.ListStore (typeof (ModelPickerItem));
            dropdown_store.append (new ModelPickerItem (null));  // placeholder

            // Factory for the button (compact: name only)
            var btn_factory = new Gtk.SignalListItemFactory ();
            btn_factory.setup.connect (item => {
                var li  = (Gtk.ListItem) item;
                var lbl = new Gtk.Label ("");
                lbl.halign = Gtk.Align.START;
                lbl.ellipsize = Pango.EllipsizeMode.END;
                li.set_child (lbl);
            });
            btn_factory.bind.connect (item => {
                var li    = (Gtk.ListItem) item;
                var lbl   = (Gtk.Label) li.get_child ();
                var entry = (ModelPickerItem) li.get_item ();
                if (entry.model == null) {
                    lbl.label = "— Select model —";
                } else {
                    var pub = entry.model.publisher ();
                    var n   = entry.model.clean_name ().down ();
                    lbl.label = pub != "" ? pub + "/" + n : n;
                }
            });

            // Factory for the popup list (rich: name + quant + params + size)
            var list_factory = new Gtk.SignalListItemFactory ();
            list_factory.setup.connect (item => {
                var li  = (Gtk.ListItem) item;
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                row.margin_start  = 4;
                row.margin_end    = 4;
                row.margin_top    = 4;
                row.margin_bottom = 4;

                var name_lbl  = new Gtk.Label ("");
                name_lbl.halign   = Gtk.Align.START;
                name_lbl.hexpand  = true;
                name_lbl.ellipsize = Pango.EllipsizeMode.END;
                name_lbl.set_data ("role", "name");

                var quant_lbl = new Gtk.Label ("");
                quant_lbl.add_css_class ("badge");
                quant_lbl.add_css_class ("quant");
                quant_lbl.valign = Gtk.Align.CENTER;
                quant_lbl.set_data ("role", "quant");

                var params_lbl = new Gtk.Label ("");
                params_lbl.add_css_class ("caption");
                params_lbl.add_css_class ("dim-label");
                params_lbl.width_chars = 5;
                params_lbl.halign      = Gtk.Align.END;
                params_lbl.set_data ("role", "params");

                var size_lbl = new Gtk.Label ("");
                size_lbl.add_css_class ("caption");
                size_lbl.add_css_class ("dim-label");
                size_lbl.add_css_class ("monospace");
                size_lbl.width_chars = 8;
                size_lbl.halign      = Gtk.Align.END;
                size_lbl.set_data ("role", "size");

                var vision_tag = new Gtk.Label ("Vision");
                vision_tag.add_css_class ("badge");
                vision_tag.add_css_class ("badge-vision");
                vision_tag.valign  = Gtk.Align.CENTER;
                vision_tag.visible = false;
                vision_tag.set_data ("role", "vision");

                var tools_tag = new Gtk.Label ("Tools");
                tools_tag.add_css_class ("badge");
                tools_tag.add_css_class ("badge-tools");
                tools_tag.valign  = Gtk.Align.CENTER;
                tools_tag.visible = false;
                tools_tag.set_data ("role", "tools");

                row.append (name_lbl);
                row.append (vision_tag);
                row.append (tools_tag);
                row.append (quant_lbl);
                row.append (params_lbl);
                row.append (size_lbl);
                li.set_child (row);
            });
            list_factory.bind.connect (item => {
                var li    = (Gtk.ListItem) item;
                var row   = (Gtk.Box) li.get_child ();
                var entry = (ModelPickerItem) li.get_item ();

                Gtk.Label? name_lbl   = null;
                Gtk.Label? quant_lbl  = null;
                Gtk.Label? params_lbl = null;
                Gtk.Label? size_lbl   = null;
                Gtk.Label? vision_tag = null;
                Gtk.Label? tools_tag  = null;

                var child = row.get_first_child ();
                while (child != null) {
                    if (child is Gtk.Label) {
                        var r = ((Gtk.Label) child).get_data<string> ("role");
                        if (r == "name")   name_lbl   = (Gtk.Label) child;
                        if (r == "quant")  quant_lbl  = (Gtk.Label) child;
                        if (r == "params") params_lbl = (Gtk.Label) child;
                        if (r == "size")   size_lbl   = (Gtk.Label) child;
                        if (r == "vision") vision_tag = (Gtk.Label) child;
                        if (r == "tools")  tools_tag  = (Gtk.Label) child;
                    }
                    child = child.get_next_sibling ();
                }

                if (entry.model == null) {
                    if (name_lbl   != null) name_lbl.label     = "— Select model —";
                    if (quant_lbl  != null) quant_lbl.visible  = false;
                    if (params_lbl != null) params_lbl.label   = "";
                    if (size_lbl   != null) size_lbl.label     = "";
                    if (vision_tag != null) vision_tag.visible = false;
                    if (tools_tag  != null) tools_tag.visible  = false;
                } else {
                    var m = entry.model;
                    if (name_lbl   != null) name_lbl.label   = m.clean_name ().down ();
                    if (quant_lbl  != null) {
                        var q = m.quant_tag ();
                        quant_lbl.label   = q;
                        quant_lbl.visible = q != "";
                    }
                    if (params_lbl != null) params_lbl.label   = m.format_params ();
                    if (size_lbl   != null) size_lbl.label     = m.format_size ();
                    if (vision_tag != null) vision_tag.visible = m.has_vision;
                    if (tools_tag  != null) tools_tag.visible  = m.has_tools;
                }
            });

            model_dropdown = new Gtk.DropDown (dropdown_store, null);
            model_dropdown.factory      = btn_factory;
            model_dropdown.list_factory = list_factory;
            model_dropdown.add_css_class ("model-selector");
            model_dropdown.show_arrow    = true;
            model_dropdown.width_request = 460;
            model_dropdown.notify["selected"].connect (on_model_selected);

            eject_btn = new Gtk.Button.from_icon_name ("media-eject-symbolic");
            eject_btn.tooltip_text = "Unload model";
            eject_btn.add_css_class ("flat");
            eject_btn.sensitive = false;
            eject_btn.clicked.connect (() => backend_manager.unload_model.begin ());

            var title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            title_box.valign = Gtk.Align.CENTER;
            title_box.append (model_dropdown);
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

            content_toolbar.add_top_bar (content_header);
            content_toolbar.add_top_bar (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Content stack (the main pages)
            content_stack = new Gtk.Stack ();
            content_stack.transition_type     = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            content_stack.transition_duration = 200;
            content_stack.hexpand = true;
            content_stack.vexpand = true;

            // Main body: resizable paned split — content stack | params panel
            params_panel = new UI.ChatParamsPanel (backend_manager);

            main_paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            main_paned.start_child        = content_stack;
            main_paned.end_child          = params_panel;
            main_paned.resize_start_child = true;
            main_paned.resize_end_child   = false;
            main_paned.shrink_start_child = false;
            main_paned.shrink_end_child   = false;
            content_toolbar.set_content (main_paned);

            split_view.set_content (content_toolbar);

            // ── Pages ────────────────────────────────────────────────────────
            chat_view = new UI.ChatView (backend_manager, settings, chat_history);
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

            model_manager.models.items_changed.connect ((pos, removed, added) => {
                update_header_model_list ();
            });

            backend_manager.status_changed.connect (s => {
                if (s == BackendStatus.LOADING) {
                    model_dropdown.add_css_class ("loading");
                } else {
                    model_dropdown.remove_css_class ("loading");
                }
                eject_btn.sensitive = (s == BackendStatus.READY);
            });

            backend_manager.model_loaded.connect (m => {
                model_list_updating = true;
                for (uint i = 0; i < dropdown_store.get_n_items (); i++) {
                    var entry = (ModelPickerItem) dropdown_store.get_item (i);
                    if (entry.model != null && entry.model.path == m.path) {
                        model_dropdown.selected = i;
                        break;
                    }
                }
                model_list_updating = false;
                model_dropdown.add_css_class ("model-loaded");
            });

            backend_manager.model_unloaded.connect (() => {
                model_list_updating = true;
                model_dropdown.selected = 0;
                model_list_updating = false;
                eject_btn.sensitive = false;
                model_dropdown.remove_css_class ("model-loaded");
            });

            close_request.connect (on_close_request);
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

            var toast = new Adw.Toast ("Loading %s…".printf (model.name));
            toast.timeout = 0;
            toast_overlay.add_toast (toast);

            do_load_model.begin (model, params, toast);
        }

        private async void do_load_model (ModelInfo model, ModelParams params, Adw.Toast loading_toast) {
            try {
                yield backend_manager.load_model (model, params, load_cancel);
                loading_toast.dismiss ();
                var ok_toast = new Adw.Toast ("%s loaded".printf (model.name));
                ok_toast.timeout = 3;
                toast_overlay.add_toast (ok_toast);
                navigate_to (UI.SidebarPage.CHAT);
            } catch (Error e) {
                loading_toast.dismiss ();
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

        private void update_header_model_list () {
            model_list_updating = true;
            dropdown_store.remove_all ();
            dropdown_store.append (new ModelPickerItem (null));  // placeholder
            for (uint i = 0; i < model_manager.models.get_n_items (); i++) {
                var m = (ModelInfo) model_manager.models.get_item (i);
                dropdown_store.append (new ModelPickerItem (m));
            }
            // Restore selection if a model is currently loaded
            uint new_sel = 0;
            if (backend_manager.loaded_model != null) {
                for (uint i = 0; i < model_manager.models.get_n_items (); i++) {
                    var m = (ModelInfo) model_manager.models.get_item (i);
                    if (m.path == backend_manager.loaded_model.path) {
                        new_sel = i + 1;
                        break;
                    }
                }
            }
            model_dropdown.selected = new_sel;
            model_list_updating = false;
        }

        private void on_model_selected () {
            if (model_list_updating) return;
            uint idx = model_dropdown.selected;
            if (idx == 0 || idx == uint.MAX) return;
            var entry = (ModelPickerItem) dropdown_store.get_item (idx);
            if (entry == null || entry.model == null) return;
            var model = entry.model;

            // Reset dropdown to placeholder immediately
            model_list_updating = true;
            model_dropdown.selected = 0;
            model_list_updating = false;

            // Skip if already loaded
            if (backend_manager.loaded_model?.path == model.path) return;

            on_load_model_requested (model);
        }
    }
}

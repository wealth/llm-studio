namespace LLMStudio.UI {

    public enum SidebarPage {
        CHAT,
        MODELS,
        HUB,
        SERVER,
        LOGS;

        public string to_string () {
            switch (this) {
                case CHAT:   return "chat";
                case MODELS: return "models";
                case HUB:    return "hub";
                case SERVER: return "server";
                case LOGS:   return "logs";
                default:     return "chat";
            }
        }
    }

    public class Sidebar : Gtk.Box {
        private BackendManager    backend_manager;
        private ChatHistory       chat_history;

        // Icon rail buttons
        private Gtk.ToggleButton  chat_btn;
        private Gtk.ToggleButton  models_btn;
        private Gtk.ToggleButton  hub_btn;
        private Gtk.ToggleButton  server_btn;
        private Gtk.ToggleButton  logs_btn;

        // Content pane
        private Gtk.Stack         content_stack;
        private ChatSidebarPanel  chat_panel;

        // Status indicator in icon rail
        private Gtk.Spinner       status_spinner;
        private Gtk.Image         status_dot;

        private SidebarPage       _current_page = SidebarPage.CHAT;
        private bool              updating_nav  = false;

        public signal void page_changed (SidebarPage page);
        public signal void new_chat_requested ();
        public signal void session_selected   (ChatSession session);
        public signal void session_delete_requested (ChatSession session);

        public SidebarPage current_page {
            get { return _current_page; }
            set { select_page (value); }
        }

        public Sidebar (BackendManager manager, ChatHistory history) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            this.backend_manager = manager;
            this.chat_history    = history;
            build_ui ();
            connect_signals ();
        }

        private Gtk.ToggleButton make_nav_btn (string icon, string tip) {
            var img = new Gtk.Image.from_icon_name (icon);
            img.pixel_size = 18;
            var btn = new Gtk.ToggleButton ();
            btn.set_child (img);
            btn.add_css_class ("flat");
            btn.tooltip_text = tip;
            btn.width_request  = 48;
            btn.height_request = 42;
            return btn;
        }

        private void build_ui () {
            // ── Icon rail (left, narrow) ──────────────────────────────────
            var icon_rail = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            icon_rail.width_request = 48;

            chat_btn   = make_nav_btn ("chat-symbolic",                      "Chat");
            models_btn = make_nav_btn ("drive-harddisk-symbolic",            "Models");
            hub_btn    = make_nav_btn ("folder-remote-symbolic",             "Hub");
            server_btn = make_nav_btn ("network-server-symbolic",            "API Server");
            logs_btn   = make_nav_btn ("utilities-system-monitor-symbolic",  "Logs");

            // Mutual-exclusion group
            models_btn.set_group (chat_btn);
            hub_btn.set_group    (chat_btn);
            server_btn.set_group (chat_btn);
            logs_btn.set_group   (chat_btn);

            chat_btn.active = true;

            chat_btn.toggled.connect   (() => { if (chat_btn.active)   navigate (SidebarPage.CHAT);   });
            models_btn.toggled.connect (() => { if (models_btn.active) navigate (SidebarPage.MODELS); });
            hub_btn.toggled.connect    (() => { if (hub_btn.active)    navigate (SidebarPage.HUB);    });
            server_btn.toggled.connect (() => { if (server_btn.active) navigate (SidebarPage.SERVER); });
            logs_btn.toggled.connect   (() => { if (logs_btn.active)   navigate (SidebarPage.LOGS);   });

            icon_rail.append (chat_btn);
            icon_rail.append (models_btn);
            icon_rail.append (hub_btn);
            icon_rail.append (server_btn);
            icon_rail.append (logs_btn);

            // Spacer
            var spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            spacer.vexpand = true;
            icon_rail.append (spacer);

            // Status indicator
            var status_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            status_box.halign        = Gtk.Align.CENTER;
            status_box.margin_bottom = 4;

            status_dot = new Gtk.Image.from_icon_name ("media-record-symbolic");
            status_dot.pixel_size = 10;
            status_dot.add_css_class ("dim-label");
            status_box.append (status_dot);

            status_spinner = new Gtk.Spinner ();
            status_spinner.visible = false;
            status_box.append (status_spinner);

            icon_rail.append (status_box);

            // Preferences button
            var prefs_btn = new Gtk.Button.from_icon_name ("preferences-system-symbolic");
            prefs_btn.add_css_class ("flat");
            prefs_btn.tooltip_text = "Preferences";
            prefs_btn.action_name  = "app.preferences";
            prefs_btn.width_request  = 48;
            prefs_btn.height_request = 42;
            prefs_btn.margin_bottom  = 4;
            icon_rail.append (prefs_btn);

            append (icon_rail);
            append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            // ── Content pane (right, expandable) ─────────────────────────
            content_stack = new Gtk.Stack ();
            content_stack.transition_type     = Gtk.StackTransitionType.CROSSFADE;
            content_stack.transition_duration = 120;
            content_stack.hexpand = true;
            content_stack.vexpand = true;

            // Chat page — history list
            chat_panel = new ChatSidebarPanel (chat_history);
            chat_panel.new_chat_requested.connect        (() => new_chat_requested ());
            chat_panel.session_selected.connect          (s => session_selected (s));
            chat_panel.session_delete_requested.connect  (s => session_delete_requested (s));
            content_stack.add_named (chat_panel, "chat");

            // Other pages — simple placeholder labels
            foreach (var page in new SidebarPage[] {
                SidebarPage.MODELS, SidebarPage.HUB,
                SidebarPage.SERVER, SidebarPage.LOGS
            }) {
                var lbl = new Gtk.Label (page_display_name (page));
                lbl.add_css_class ("dim-label");
                lbl.valign = Gtk.Align.START;
                lbl.halign = Gtk.Align.START;
                lbl.margin_top   = 12;
                lbl.margin_start = 12;
                content_stack.add_named (lbl, page.to_string ());
            }

            append (content_stack);
        }

        private string page_display_name (SidebarPage p) {
            switch (p) {
                case SidebarPage.MODELS: return "Models";
                case SidebarPage.HUB:    return "Hub";
                case SidebarPage.SERVER: return "API Server";
                case SidebarPage.LOGS:   return "Logs";
                default:                 return "";
            }
        }

        private void navigate (SidebarPage page) {
            if (updating_nav) return;
            _current_page = page;
            content_stack.visible_child_name = page.to_string ();
            page_changed (page);
        }

        private void select_page (SidebarPage page) {
            updating_nav = true;
            _current_page = page;
            content_stack.visible_child_name = page.to_string ();
            switch (page) {
                case SidebarPage.CHAT:   chat_btn.active   = true; break;
                case SidebarPage.MODELS: models_btn.active = true; break;
                case SidebarPage.HUB:    hub_btn.active    = true; break;
                case SidebarPage.SERVER: server_btn.active = true; break;
                case SidebarPage.LOGS:   logs_btn.active   = true; break;
            }
            updating_nav = false;
        }

        private void connect_signals () {
            backend_manager.status_changed.connect (on_status_changed);
        }

        private void on_status_changed (BackendStatus s) {
            switch (s) {
                case BackendStatus.LOADING:
                    status_spinner.visible  = true;
                    status_spinner.spinning = true;
                    status_dot.visible      = false;
                    break;
                case BackendStatus.READY:
                    status_spinner.visible  = false;
                    status_spinner.spinning = false;
                    status_dot.visible      = true;
                    status_dot.remove_css_class ("dim-label");
                    status_dot.add_css_class    ("success");
                    break;
                case BackendStatus.ERROR:
                    status_spinner.visible  = false;
                    status_spinner.spinning = false;
                    status_dot.visible      = true;
                    status_dot.remove_css_class ("success");
                    status_dot.add_css_class    ("error");
                    break;
                default:
                    status_spinner.visible  = false;
                    status_spinner.spinning = false;
                    status_dot.visible      = true;
                    status_dot.remove_css_class ("success");
                    status_dot.remove_css_class ("error");
                    status_dot.add_css_class    ("dim-label");
                    break;
            }
        }
    }
}

namespace LLMStudio.UI {

    public class ServerPanel : Gtk.Box {
        private OpenAIServer  api_server;
        private BackendManager backend_manager;
        private GLib.Settings  settings;

        private Gtk.Switch     server_switch;
        private Gtk.Label      status_lbl;
        private Gtk.Label      url_lbl;
        private Gtk.Entry      host_entry;
        private Gtk.SpinButton port_spin;
        private Gtk.Switch     cors_switch;
        private Gtk.ListBox    log_list;
        private Gtk.Button     copy_url_btn;
        private Gtk.Button     clear_log_btn;

        public ServerPanel (OpenAIServer server, BackendManager manager, GLib.Settings settings) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.api_server      = server;
            this.backend_manager = manager;
            this.settings        = settings;
            build_ui ();
            connect_signals ();
            update_status ();
        }

        private void build_ui () {
            // Title bar
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            toolbar.margin_start  = 16;
            toolbar.margin_end    = 16;
            toolbar.margin_top    = 10;
            toolbar.margin_bottom = 10;

            var title = new Gtk.Label ("API Server");
            title.add_css_class ("title-4");
            title.hexpand = true;
            title.halign  = Gtk.Align.START;
            toolbar.append (title);
            append (toolbar);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            append (scroll);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 20);
            content.margin_start  = 18;
            content.margin_end    = 18;
            content.margin_top    = 16;
            content.margin_bottom = 24;
            scroll.set_child (content);

            // Status card
            var status_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            status_card.add_css_class ("card");
            status_card.margin_top = 4;

            var status_top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            status_top.margin_start  = 16;
            status_top.margin_end    = 16;
            status_top.margin_top    = 14;
            status_top.margin_bottom = 0;

            var status_icon = new Gtk.Image.from_icon_name ("network-server-symbolic");
            status_icon.pixel_size = 48;

            var status_text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            status_text_box.valign = Gtk.Align.CENTER;
            status_text_box.hexpand = true;

            status_lbl = new Gtk.Label ("Server stopped");
            status_lbl.add_css_class ("title-3");
            status_lbl.halign = Gtk.Align.START;

            url_lbl = new Gtk.Label ("");
            url_lbl.add_css_class ("dim-label");
            url_lbl.halign   = Gtk.Align.START;
            url_lbl.selectable = true;

            status_text_box.append (status_lbl);
            status_text_box.append (url_lbl);
            status_top.append (status_icon);
            status_top.append (status_text_box);

            // Server on/off switch
            var switch_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            switch_row.margin_start  = 16;
            switch_row.margin_end    = 16;
            switch_row.margin_bottom = 14;
            var switch_lbl = new Gtk.Label ("Enable Server");
            switch_lbl.add_css_class ("body");
            switch_lbl.hexpand = true;
            server_switch = new Gtk.Switch ();
            server_switch.valign = Gtk.Align.CENTER;
            server_switch.active = settings.get_boolean ("api-server-enabled");
            switch_row.append (switch_lbl);
            switch_row.append (server_switch);

            copy_url_btn = new Gtk.Button.with_label ("Copy URL");
            copy_url_btn.add_css_class ("pill");
            copy_url_btn.halign = Gtk.Align.START;
            copy_url_btn.margin_start  = 16;
            copy_url_btn.margin_bottom = 14;
            copy_url_btn.sensitive = false;
            copy_url_btn.clicked.connect (on_copy_url);

            status_card.append (status_top);
            status_card.append (switch_row);
            status_card.append (copy_url_btn);
            content.append (status_card);

            // Configuration group
            var config_group = new Adw.PreferencesGroup ();
            config_group.title = "Configuration";
            content.append (config_group);

            // Host
            var host_row = new Adw.ActionRow ();
            host_row.title    = "Bind Address";
            host_row.subtitle = "IP address to listen on. Use 0.0.0.0 for all interfaces.";
            host_entry = new Gtk.Entry ();
            host_entry.text   = settings.get_string ("api-server-host");
            host_entry.valign = Gtk.Align.CENTER;
            host_entry.width_chars = 16;
            host_entry.changed.connect (() => settings.set_string ("api-server-host", host_entry.text));
            host_row.add_suffix (host_entry);
            host_row.activatable_widget = host_entry;
            config_group.add (host_row);

            // Port
            var port_adj = new Gtk.Adjustment (settings.get_int ("api-server-port"), 1024, 65535, 1, 100, 0);
            var port_row = new Adw.SpinRow (port_adj, 1, 0);
            port_row.title    = "Port";
            port_row.subtitle = "TCP port to listen on";
            port_row.notify["value"].connect (() =>
                settings.set_int ("api-server-port", (int) port_row.get_value ()));
            config_group.add (port_row);

            // CORS
            var cors_row = new Adw.SwitchRow ();
            cors_row.title    = "CORS Headers";
            cors_row.subtitle = "Allow cross-origin requests (needed for browser apps)";
            cors_row.active   = settings.get_boolean ("api-server-cors");
            cors_row.notify["active"].connect (() =>
                settings.set_boolean ("api-server-cors", cors_row.active));
            config_group.add (cors_row);

            // Endpoints reference
            var endpoints_group = new Adw.PreferencesGroup ();
            endpoints_group.title       = "Available Endpoints";
            endpoints_group.description = "OpenAI-compatible REST API";
            content.append (endpoints_group);

            string[] endpoints = {
                "GET  /v1/models",         "List loaded models",
                "POST /v1/chat/completions","Chat completion (streaming supported)",
                "GET  /health",            "Server health check"
            };

            for (int i = 0; i < endpoints.length; i += 2) {
                var ep_row = new Adw.ActionRow ();
                ep_row.title    = endpoints[i];
                ep_row.subtitle = endpoints[i+1];
                ep_row.add_css_class ("monospace");
                endpoints_group.add (ep_row);
            }

            // Request log
            var log_group = new Adw.PreferencesGroup ();
            log_group.title = "Request Log";
            content.append (log_group);

            var log_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var log_title   = new Gtk.Label ("Recent Requests");
            log_title.add_css_class ("heading");
            log_title.hexpand = true;
            log_title.halign  = Gtk.Align.START;
            clear_log_btn = new Gtk.Button.with_label ("Clear");
            clear_log_btn.add_css_class ("flat");
            clear_log_btn.clicked.connect (() => {
                var c = log_list.get_first_child ();
                while (c != null) { var n = c.get_next_sibling (); log_list.remove ((Gtk.Widget)c); c = n; }
            });
            log_toolbar.append (log_title);
            log_toolbar.append (clear_log_btn);

            var log_frame = new Gtk.Frame (null);
            log_frame.add_css_class ("card");
            log_list = new Gtk.ListBox ();
            log_list.selection_mode = Gtk.SelectionMode.NONE;
            var log_empty = new Adw.StatusPage ();
            log_empty.icon_name   = "utilities-system-monitor-symbolic";
            log_empty.title       = "No requests yet";
            log_list.set_placeholder (log_empty);
            log_frame.set_child (log_list);

            var log_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            log_box.append (log_toolbar);
            log_box.append (log_frame);
            content.append (log_box);
        }

        private void connect_signals () {
            server_switch.state_set.connect ((active) => {
                if (active) {
                    try {
                        api_server.start ();
                        settings.set_boolean ("api-server-enabled", true);
                    } catch (Error e) {
                        show_error ("Failed to start server: " + e.message);
                        server_switch.active = false;
                        return true; // prevent state change
                    }
                } else {
                    api_server.stop ();
                    settings.set_boolean ("api-server-enabled", false);
                }
                return false;
            });

            api_server.started.connect ((host, port) => {
                update_status ();
            });
            api_server.stopped.connect (() => {
                update_status ();
            });
            api_server.request_log.connect ((method, path, status) => {
                add_log_entry (method, path, status);
            });
        }

        private void update_status () {
            if (api_server.is_running) {
                status_lbl.label    = "Server running";
                status_lbl.remove_css_class ("dim-label");
                var host = settings.get_string ("api-server-host");
                if (host == "0.0.0.0") host = "localhost";
                var url  = "http://%s:%d".printf (host, api_server.port);
                url_lbl.label       = url;
                copy_url_btn.sensitive = true;
                server_switch.active   = true;
            } else {
                status_lbl.label    = "Server stopped";
                url_lbl.label       = "";
                copy_url_btn.sensitive = false;
                server_switch.active   = false;
            }
        }

        private void on_copy_url () {
            var host = settings.get_string ("api-server-host");
            if (host == "0.0.0.0") host = "localhost";
            var url = "http://%s:%d".printf (host, api_server.port);
            get_display ().get_clipboard ().set_text (url);
            show_toast ("URL copied to clipboard");
        }

        private void add_log_entry (string method, string path, int status) {
            var row = new Gtk.ListBoxRow ();
            row.activatable = false;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.margin_top    = 6;
            box.margin_bottom = 6;
            box.margin_start  = 12;
            box.margin_end    = 12;

            var method_lbl = new Gtk.Label (method);
            method_lbl.add_css_class ("monospace");
            method_lbl.add_css_class ("caption");
            method_lbl.width_chars = 4;
            method_lbl.halign = Gtk.Align.START;

            var path_lbl = new Gtk.Label (path);
            path_lbl.add_css_class ("monospace");
            path_lbl.add_css_class ("caption");
            path_lbl.hexpand = true;
            path_lbl.halign  = Gtk.Align.START;

            var status_lbl2 = new Gtk.Label (status.to_string ());
            status_lbl2.add_css_class ("badge");
            status_lbl2.add_css_class (status < 400 ? "success" : "error");

            var time_lbl = new Gtk.Label (
                new DateTime.now_local ().format ("%H:%M:%S"));
            time_lbl.add_css_class ("caption");
            time_lbl.add_css_class ("dim-label");

            box.append (method_lbl);
            box.append (path_lbl);
            box.append (status_lbl2);
            box.append (time_lbl);
            row.child = box;

            // Prepend to show newest first
            log_list.prepend (row);

            // Keep max 50 entries
            uint count = 0;
            var c = log_list.get_first_child ();
            while (c != null) { count++; c = c.get_next_sibling (); }
            if (count > 50) {
                c = log_list.get_last_child ();
                if (c != null) log_list.remove (c);
            }
        }

        private void show_error (string msg) {
            var dialog = new Adw.MessageDialog (get_root () as Gtk.Window, "Error", msg);
            dialog.add_response ("ok", "OK");
            dialog.present ();
        }

        private void show_toast (string msg) {
            Gtk.Widget? w = this;
            while (w != null) {
                if (w is Adw.ToastOverlay) {
                    ((Adw.ToastOverlay) w).add_toast (new Adw.Toast (msg));
                    return;
                }
                w = w.get_parent ();
            }
        }
    }
}

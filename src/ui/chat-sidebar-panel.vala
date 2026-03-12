namespace LLMStudio.UI {

    public class ChatSidebarPanel : Gtk.Box {
        private ChatHistory   history;
        private Gtk.ListBox   session_list;
        private string        filter_text = "";

        public signal void new_chat_requested ();
        public signal void session_selected   (ChatSession session);
        public signal void session_delete_requested (ChatSession session);

        public ChatSidebarPanel (ChatHistory history) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.history = history;
            build_ui ();
            history.sessions.items_changed.connect ((pos, removed, added) => refresh_list ());
            history.session_changed.connect (on_current_changed);
            refresh_list ();
        }

        private void build_ui () {
            // Toolbar: title + new-chat button
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            toolbar.margin_start  = 10;
            toolbar.margin_end    = 4;
            toolbar.margin_top    = 6;
            toolbar.margin_bottom = 4;

            var title_lbl = new Gtk.Label ("Chats");
            title_lbl.add_css_class ("heading");
            title_lbl.halign  = Gtk.Align.START;
            title_lbl.hexpand = true;
            toolbar.append (title_lbl);

            var new_btn = new Gtk.Button.from_icon_name ("tab-new-symbolic");
            new_btn.add_css_class ("flat");
            new_btn.tooltip_text = "New Chat";
            new_btn.clicked.connect (() => new_chat_requested ());
            toolbar.append (new_btn);
            append (toolbar);

            // Search
            var search = new Gtk.SearchEntry ();
            search.placeholder_text = "Search chats…";
            search.margin_start  = 8;
            search.margin_end    = 8;
            search.margin_bottom = 6;
            search.changed.connect (() => {
                filter_text = search.text.down ();
                refresh_list ();
            });
            append (search);

            // Session list
            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand           = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            append (scroll);

            session_list = new Gtk.ListBox ();
            session_list.selection_mode = Gtk.SelectionMode.SINGLE;
            session_list.add_css_class  ("navigation-sidebar");
            session_list.row_selected.connect (on_row_selected);
            scroll.set_child (session_list);

            var empty_lbl = new Gtk.Label ("No chats yet");
            empty_lbl.add_css_class ("dim-label");
            session_list.set_placeholder (empty_lbl);
        }

        private void refresh_list () {
            var child = session_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                session_list.remove ((Gtk.Widget) child);
                child = next;
            }

            for (uint i = 0; i < history.sessions.get_n_items (); i++) {
                var s = (ChatSession) history.sessions.get_item (i);
                if (filter_text != "" && !s.title.down ().contains (filter_text))
                    continue;
                session_list.append (make_session_row (s));
            }

            on_current_changed (history.current);
        }

        private Gtk.ListBoxRow make_session_row (ChatSession session) {
            var row = new Gtk.ListBoxRow ();
            row.set_data ("session-id", session.id);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            box.margin_start  = 10;
            box.margin_end    = 2;
            box.margin_top    = 6;
            box.margin_bottom = 6;

            var lbl = new Gtk.Label (session.title);
            lbl.halign   = Gtk.Align.START;
            lbl.hexpand  = true;
            lbl.ellipsize = Pango.EllipsizeMode.END;
            box.append (lbl);

            var del_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            del_btn.add_css_class ("flat");
            del_btn.add_css_class ("circular");
            del_btn.opacity      = 0.0;
            del_btn.tooltip_text = "Delete";
            del_btn.clicked.connect (() => session_delete_requested (session));
            box.append (del_btn);

            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect (() => del_btn.opacity = 1.0);
            motion.leave.connect (() => del_btn.opacity = 0.0);
            box.add_controller (motion);

            row.child = box;
            return row;
        }

        private void on_row_selected (Gtk.ListBoxRow? row) {
            if (row == null) return;
            var id = row.get_data<string> ("session-id");
            for (uint i = 0; i < history.sessions.get_n_items (); i++) {
                var s = (ChatSession) history.sessions.get_item (i);
                if (s.id == id) {
                    session_selected (s);
                    return;
                }
            }
        }

        private void on_current_changed (ChatSession? session) {
            if (session == null) {
                session_list.select_row (null);
                return;
            }
            var row = session_list.get_first_child ();
            while (row != null) {
                if (row is Gtk.ListBoxRow) {
                    var r = (Gtk.ListBoxRow) row;
                    if (r.get_data<string> ("session-id") == session.id) {
                        session_list.select_row (r);
                        return;
                    }
                }
                row = row.get_next_sibling ();
            }
        }
    }
}

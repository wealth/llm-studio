namespace LLMStudio {

    public class ChatSession : Object {
        public string id         { get; set; default = ""; }
        public string title      { get; set; default = "New Chat"; }
        public int64  updated_at { get; set; default = 0; }

        private GLib.List<ChatMessage> _messages;

        public ChatSession () {
            _messages = new GLib.List<ChatMessage> ();
        }

        public unowned GLib.List<ChatMessage> get_messages () {
            return _messages;
        }

        public void add_message (ChatMessage msg) {
            _messages.append (msg);
        }

        public void clear_messages () {
            _messages = new GLib.List<ChatMessage> ();
        }

        /* Remove the user+assistant pair at exchange index @idx (0-based).
           Messages are stored as alternating user/assistant pairs.        */
        public void delete_exchange_at (int idx) {
            var asst = _messages.nth_data ((uint)(idx * 2 + 1));
            if (asst != null) _messages.remove (asst);
            var user = _messages.nth_data ((uint)(idx * 2));
            if (user != null) _messages.remove (user);
        }

        public uint message_count () {
            return _messages.length ();
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            obj.set_string_member ("id",         id);
            obj.set_string_member ("title",      title);
            obj.set_int_member    ("updated_at", updated_at);

            var msgs_arr = new Json.Array ();
            foreach (var m in _messages) {
                var mo = new Json.Object ();
                mo.set_string_member ("role",    m.role);
                mo.set_string_member ("content", m.content);
                if (m.model_name != "") mo.set_string_member ("model_name", m.model_name);
                if (m.stats_text != "") mo.set_string_member ("stats_text", m.stats_text);
                if (m.role == "assistant" && m.rounds.length () > 0) {
                    var rounds_arr = new Json.Array ();
                    foreach (unowned var r in m.rounds) {
                        var ro = new Json.Object ();
                        if (r.think    != "") ro.set_string_member ("think",    r.think);
                        if (r.response != "") ro.set_string_member ("response", r.response);
                        if (r.tool_calls.length () > 0) {
                            var tca = new Json.Array ();
                            foreach (unowned var tc in r.tool_calls) {
                                var tco = new Json.Object ();
                                tco.set_string_member ("display", tc.display);
                                tco.set_string_member ("result",  tc.result);
                                var tcn = new Json.Node (Json.NodeType.OBJECT);
                                tcn.set_object (tco);
                                tca.add_element (tcn);
                            }
                            var tcan = new Json.Node (Json.NodeType.ARRAY);
                            tcan.set_array (tca);
                            ro.set_member ("tool_calls", tcan);
                        }
                        var rn = new Json.Node (Json.NodeType.OBJECT);
                        rn.set_object (ro);
                        rounds_arr.add_element (rn);
                    }
                    var rounds_n = new Json.Node (Json.NodeType.ARRAY);
                    rounds_n.set_array (rounds_arr);
                    mo.set_member ("rounds", rounds_n);
                }
                if (m.has_attachments ()) {
                    var atts = new Json.Array ();
                    foreach (var a in m.attachments) {
                        var an = new Json.Node (Json.NodeType.OBJECT);
                        an.set_object (a.to_json ());
                        atts.add_element (an);
                    }
                    var atts_node = new Json.Node (Json.NodeType.ARRAY);
                    atts_node.set_array (atts);
                    mo.set_member ("attachments", atts_node);
                }
                var mn = new Json.Node (Json.NodeType.OBJECT);
                mn.set_object (mo);
                msgs_arr.add_element (mn);
            }
            var msgs_node = new Json.Node (Json.NodeType.ARRAY);
            msgs_node.set_array (msgs_arr);
            obj.set_member ("messages", msgs_node);
            return obj;
        }

        public static ChatSession from_json (Json.Object obj) {
            var s = new ChatSession ();
            s.id         = obj.has_member ("id")         ? obj.get_string_member ("id")      : GLib.Uuid.string_random ();
            s.title      = obj.has_member ("title")      ? obj.get_string_member ("title")   : "Chat";
            s.updated_at = obj.has_member ("updated_at") ? obj.get_int_member    ("updated_at") : 0;

            if (obj.has_member ("messages")) {
                var arr = obj.get_array_member ("messages");
                for (uint i = 0; i < arr.get_length (); i++) {
                    var mo = arr.get_object_element (i);
                    var role    = mo.has_member ("role")    ? mo.get_string_member ("role")    : "user";
                    var content = mo.has_member ("content") ? mo.get_string_member ("content") : "";
                    ChatMessage msg;
                    switch (role) {
                        case "system":    msg = new ChatMessage.system    (content); break;
                        case "assistant": msg = new ChatMessage.assistant (content); break;
                        default:          msg = new ChatMessage.user      (content); break;
                    }
                    if (mo.has_member ("model_name")) msg.model_name = mo.get_string_member ("model_name");
                    if (mo.has_member ("stats_text")) msg.stats_text = mo.get_string_member ("stats_text");
                    if (mo.has_member ("rounds")) {
                        var rarr = mo.get_array_member ("rounds");
                        for (uint j = 0; j < rarr.get_length (); j++) {
                            var ro = rarr.get_object_element (j);
                            var round = new ChatRound ();
                            if (ro.has_member ("think"))    round.think    = ro.get_string_member ("think");
                            if (ro.has_member ("response")) round.response = ro.get_string_member ("response");
                            if (ro.has_member ("tool_calls")) {
                                var tca = ro.get_array_member ("tool_calls");
                                for (uint k = 0; k < tca.get_length (); k++) {
                                    var tco = tca.get_object_element (k);
                                    var tc = new ChatToolCall ();
                                    if (tco.has_member ("display")) tc.display = tco.get_string_member ("display");
                                    if (tco.has_member ("result"))  tc.result  = tco.get_string_member ("result");
                                    round.tool_calls.append (tc);
                                }
                            }
                            msg.rounds.append (round);
                        }
                    }
                    if (mo.has_member ("attachments")) {
                        var aa = mo.get_array_member ("attachments");
                        for (uint j = 0; j < aa.get_length (); j++) {
                            var ao = aa.get_object_element (j);
                            msg.attachments.append (ChatAttachment.from_json (ao));
                        }
                    }
                    s._messages.append (msg);
                }
            }
            return s;
        }
    }

    public class ChatHistory : Object {
        public GLib.ListStore sessions { get; private set; }

        private ChatSession? _current = null;
        public ChatSession?  current  { get { return _current; } }

        private string history_file;

        public signal void session_changed (ChatSession? session);

        public ChatHistory () {
            sessions = new GLib.ListStore (typeof (ChatSession));
            var data_dir = GLib.Path.build_filename (
                GLib.Environment.get_user_data_dir (), "llm-studio2");
            GLib.DirUtils.create_with_parents (data_dir, 0755);
            history_file = GLib.Path.build_filename (data_dir, "chat-history.json");
            load ();
        }

        public ChatSession new_session () {
            var s = new ChatSession ();
            s.id         = GLib.Uuid.string_random ();
            s.updated_at = GLib.get_real_time () / 1000000;
            sessions.insert (0, s);
            _current = s;
            session_changed (_current);
            save ();
            return s;
        }

        public void switch_to (ChatSession s) {
            _current = s;
            session_changed (_current);
        }

        // Set title from the first user message (truncated to 48 chars)
        public void auto_title (string first_user_text) {
            if (_current == null) return;
            var t = first_user_text.strip ();
            if (t.length > 48) t = t.substring (0, 48) + "…";
            _current.title = t;
            notify_session_changed_in_list (_current);
            save ();
        }

        public void mark_updated () {
            if (_current == null) return;
            _current.updated_at = GLib.get_real_time () / 1000000;
            save ();
        }

        public void delete_session (ChatSession s) {
            uint pos;
            if (sessions.find (s, out pos))
                sessions.remove (pos);
            if (_current == s) {
                _current = sessions.get_n_items () > 0
                    ? (ChatSession) sessions.get_item (0)
                    : null;
                session_changed (_current);
            }
            save ();
        }

        private void notify_session_changed_in_list (ChatSession s) {
            uint pos;
            if (sessions.find (s, out pos))
                sessions.items_changed (pos, 1, 1);
        }

        private void load () {
            if (!GLib.FileUtils.test (history_file, GLib.FileTest.EXISTS)) return;
            try {
                string data;
                GLib.FileUtils.get_contents (history_file, out data);
                var parser = new Json.Parser ();
                parser.load_from_data (data);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
                var arr = root.get_array ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    var obj = arr.get_object_element (i);
                    sessions.append (ChatSession.from_json (obj));
                }
                if (sessions.get_n_items () > 0)
                    _current = (ChatSession) sessions.get_item (0);
            } catch (Error e) {
                warning ("ChatHistory.load: %s", e.message);
            }
        }

        public void save () {
            try {
                var arr = new Json.Array ();
                for (uint i = 0; i < sessions.get_n_items (); i++) {
                    var s = (ChatSession) sessions.get_item (i);
                    var n = new Json.Node (Json.NodeType.OBJECT);
                    n.set_object (s.to_json ());
                    arr.add_element (n);
                }
                var root = new Json.Node (Json.NodeType.ARRAY);
                root.set_array (arr);
                var gen = new Json.Generator ();
                gen.set_root (root);
                gen.pretty = true;
                GLib.FileUtils.set_contents (history_file, gen.to_data (null));
            } catch (Error e) {
                warning ("ChatHistory.save: %s", e.message);
            }
        }
    }
}

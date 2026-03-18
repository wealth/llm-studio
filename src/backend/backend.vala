namespace LLMStudio {

    public enum BackendStatus {
        IDLE,
        LOADING,
        READY,
        UNLOADING,
        ERROR;

        public string to_string () {
            switch (this) {
                case IDLE:      return "Idle";
                case LOADING:   return "Loading...";
                case READY:     return "Ready";
                case UNLOADING: return "Unloading...";
                case ERROR:     return "Error";
                default:        return "Unknown";
            }
        }

        public string to_css_class () {
            switch (this) {
                case READY:     return "success";
                case LOADING:
                case UNLOADING: return "warning";
                case ERROR:     return "error";
                default:        return "";
            }
        }
    }

    public enum BackendType {
        LLAMA,
        IK_LLAMA,
        VLLM;

        public string to_string () {
            switch (this) {
                case LLAMA:    return "llama";
                case IK_LLAMA: return "ik-llama";
                case VLLM:     return "vllm";
                default:       return "llama";
            }
        }

        public string display_name () {
            switch (this) {
                case LLAMA:    return "llama.cpp";
                case IK_LLAMA: return "ik_llama.cpp";
                case VLLM:     return "vLLM";
                default:       return "llama.cpp";
            }
        }

        public static BackendType from_string (string s) {
            switch (s) {
                case "ik-llama": return IK_LLAMA;
                case "vllm":     return VLLM;
                default:         return LLAMA;
            }
        }
    }

    public delegate void CompletionChunkCallback (string chunk, bool done, string? finish_reason);

    public abstract class Backend : Object {

        public abstract BackendStatus status       { get; protected set; }
        public abstract ModelInfo?    loaded_model { get; protected set; }
        public abstract BackendType   backend_type { get; }

        /* Tracks whether we are currently inside a reasoning_content block. */
        private bool _in_reasoning = false;
        /* Tracks whether reasoning_content was used at all during this stream. */
        private bool _had_reasoning = false;
        /* JSON string of accumulated tool_calls when finish_reason=="tool_calls". */
        protected string? _pending_tool_call_json = null;
        public string? pending_tool_call_json { get { return _pending_tool_call_json; } }

        public signal void status_changed (BackendStatus status);
        public signal void log_message    (string line, bool is_error);
        public signal void model_loaded   (ModelInfo model);
        public signal void model_unloaded ();

        public abstract async bool load_model (
            ModelInfo    model,
            ModelParams  params,
            GLib.Cancellable? cancel = null
        ) throws Error;

        public abstract async bool unload_model () throws Error;

        public abstract async string chat_completion (
            Json.Array   messages,
            ModelParams  params,
            GLib.Cancellable? cancel = null
        ) throws Error;

        public abstract async void chat_completion_stream (
            Json.Array   messages,
            ModelParams  params,
            owned CompletionChunkCallback callback,
            GLib.Cancellable? cancel = null,
            Json.Array? tools = null
        ) throws Error;

        // For the API server to know which port the backend server is on
        public abstract int get_server_port ();

        /* Build a JSON content node for a ChatMessage.
           Returns a plain string node when no attachments are present,
           or an array of content parts for multimodal messages.       */
        public static Json.Node build_content_node (ChatMessage m) {
            if (!m.has_attachments ()) {
                var n = new Json.Node (Json.NodeType.VALUE);
                n.set_string (m.content);
                return n;
            }

            /* Multimodal: array of content parts */
            var parts = new Json.Array ();

            /* Text part first (may be empty for image-only messages) */
            if (m.content != "") {
                var tp = new Json.Object ();
                tp.set_string_member ("type", "text");
                tp.set_string_member ("text", m.content);
                var tn = new Json.Node (Json.NodeType.OBJECT);
                tn.set_object (tp);
                parts.add_element (tn);
            }

            foreach (var att in m.attachments) {
                if (att.is_image ()) {
                    var img_url = new Json.Object ();
                    img_url.set_string_member ("url", att.to_data_uri ());
                    var img_url_n = new Json.Node (Json.NodeType.OBJECT);
                    img_url_n.set_object (img_url);

                    var ip = new Json.Object ();
                    ip.set_string_member ("type", "image_url");
                    ip.set_member ("image_url", img_url_n);
                    var in_ = new Json.Node (Json.NodeType.OBJECT);
                    in_.set_object (ip);
                    parts.add_element (in_);
                } else {
                    /* Text file: include content as a text part with filename header */
                    var tp = new Json.Object ();
                    tp.set_string_member ("type", "text");
                    tp.set_string_member ("text", "[%s]\n%s".printf (att.filename, att.data));
                    var tn = new Json.Node (Json.NodeType.OBJECT);
                    tn.set_object (tp);
                    parts.add_element (tn);
                }
            }

            var arr_n = new Json.Node (Json.NodeType.ARRAY);
            arr_n.set_array (parts);
            return arr_n;
        }

        // Build a JSON messages array from ChatMessage list
        public Json.Array build_messages_array (GLib.List<ChatMessage> msgs, string system_prompt) {
            var arr = new Json.Array ();

            if (system_prompt != "") {
                var sys = new Json.Object ();
                sys.set_string_member ("role", "system");
                sys.set_string_member ("content", system_prompt);
                var node = new Json.Node (Json.NodeType.OBJECT);
                node.set_object (sys);
                arr.add_element (node);
            }

            foreach (var m in msgs) {
                var obj = new Json.Object ();
                obj.set_string_member ("role", m.role);
                obj.set_member ("content", build_content_node (m));
                var node = new Json.Node (Json.NodeType.OBJECT);
                node.set_object (obj);
                arr.add_element (node);
            }
            return arr;
        }

        // Parse SSE stream into chunks, handling tool_calls finish_reason.
        protected async void parse_sse_stream (
            GLib.InputStream     istream,
            owned CompletionChunkCallback callback,
            GLib.Cancellable?    cancel = null
        ) throws Error {
            _in_reasoning          = false;
            _had_reasoning         = false;
            _pending_tool_call_json = null;

            // Tool-call accumulators (up to 8 parallel tool calls)
            string[] tc_ids   = new string[8];
            string[] tc_names = new string[8];
            StringBuilder[] tc_args = new StringBuilder[8];
            int tc_max_idx = -1;
            for (int i = 0; i < 8; i++) {
                tc_ids[i]   = "";
                tc_names[i] = "";
                tc_args[i]  = new StringBuilder ();
            }

            var ds = new GLib.DataInputStream (istream);
            string? line;
            while ((line = yield ds.read_line_async (GLib.Priority.DEFAULT, cancel)) != null) {
                if (!line.has_prefix ("data: ")) continue;
                var data = line[6:line.length];
                if (data == "[DONE]") {
                    if (_in_reasoning) {
                        callback ("</think>", false, null);
                        _in_reasoning = false;
                    }
                    callback ("", true, "stop");
                    break;
                }
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data (data);
                    var root = parser.get_root ();
                    if (root.get_node_type () != Json.NodeType.OBJECT) continue;
                    var obj = root.get_object ();
                    if (!obj.has_member ("choices")) continue;
                    var choices = obj.get_array_member ("choices");
                    if (choices.get_length () == 0) continue;
                    var choice = choices.get_object_element (0);

                    string? finish_reason = null;
                    if (choice.has_member ("finish_reason") &&
                        choice.get_member ("finish_reason").get_node_type () != Json.NodeType.NULL) {
                        finish_reason = choice.get_string_member ("finish_reason");
                    }

                    if (choice.has_member ("delta")) {
                        var delta = choice.get_object_member ("delta");

                        /* reasoning_content: used by Qwen3/DeepSeek-R1 and some servers. */
                        if (delta.has_member ("reasoning_content") &&
                            delta.get_member ("reasoning_content").get_node_type () == Json.NodeType.VALUE) {
                            var rc = delta.get_string_member ("reasoning_content");
                            if (rc != null && rc.length > 0) {
                                if (!_in_reasoning) {
                                    callback ("<think>", false, null);
                                    _in_reasoning = true;
                                    _had_reasoning = true;
                                }
                                callback (rc, false, null);
                            }
                        }

                        if (delta.has_member ("content") &&
                            delta.get_member ("content").get_node_type () == Json.NodeType.VALUE) {
                            var content = delta.get_string_member ("content");
                            if (_in_reasoning) {
                                callback ("</think>", false, null);
                                _in_reasoning = false;
                            }
                            if (content != null && content.length > 0) {
                                if (_had_reasoning)
                                    content = content.replace ("<think>", "").replace ("</think>", "");
                                if (content.length > 0) {
                                    // Don't mark done for tool_calls — handled below
                                    bool is_final = finish_reason != null && finish_reason != "tool_calls";
                                    callback (content, is_final, is_final ? finish_reason : null);
                                }
                            } else if (finish_reason != null && finish_reason != "tool_calls") {
                                callback ("", true, finish_reason);
                            }
                        }

                        /* Accumulate tool_calls delta fragments. */
                        if (delta.has_member ("tool_calls")) {
                            var tca = delta.get_array_member ("tool_calls");
                            for (int ti = 0; ti < (int) tca.get_length (); ti++) {
                                var tc = tca.get_object_element (ti);
                                int idx = tc.has_member ("index")
                                    ? (int) tc.get_int_member ("index") : ti;
                                if (idx < 0 || idx >= 8) continue;
                                if (idx > tc_max_idx) tc_max_idx = idx;
                                if (tc.has_member ("id"))
                                    tc_ids[idx] = tc.get_string_member ("id");
                                if (tc.has_member ("function")) {
                                    var fn = tc.get_object_member ("function");
                                    if (fn.has_member ("name"))
                                        tc_names[idx] = fn.get_string_member ("name");
                                    if (fn.has_member ("arguments"))
                                        tc_args[idx].append (fn.get_string_member ("arguments"));
                                }
                            }
                        }
                    }

                    /* Finalize tool calls when the model signals it's done calling tools. */
                    if (finish_reason == "tool_calls" && tc_max_idx >= 0) {
                        var b = new Json.Builder ();
                        b.begin_array ();
                        for (int i = 0; i <= tc_max_idx; i++) {
                            if (tc_names[i] == "") continue;
                            b.begin_object ();
                            b.set_member_name ("id");
                            b.add_string_value (tc_ids[i] != "" ? tc_ids[i]
                                                                 : "call_%d".printf (i));
                            b.set_member_name ("name");      b.add_string_value (tc_names[i]);
                            b.set_member_name ("arguments"); b.add_string_value (tc_args[i].str);
                            b.end_object ();
                        }
                        b.end_array ();
                        var gen = new Json.Generator ();
                        gen.set_root (b.get_root ());
                        _pending_tool_call_json = gen.to_data (null);
                        callback ("", true, "tool_calls");
                        break;
                    }
                } catch (Error e) {
                    // Malformed chunk - skip
                }
            }
        }

        // Helper: make a JSON request body node for chat completions
        protected Json.Node make_chat_request_body (Json.Array messages, ModelParams params, bool stream,
                                                     Json.Array? tools = null) {
            var builder = new Json.Builder ();
            builder.begin_object ();
            var arr_node = new Json.Node (Json.NodeType.ARRAY);
            arr_node.set_array (messages);
            builder.set_member_name ("messages");
            builder.add_value (arr_node);
            builder.set_member_name ("stream");        builder.add_boolean_value (stream);
            builder.set_member_name ("temperature");   builder.add_double_value (params.temperature);
            builder.set_member_name ("top_p");         builder.add_double_value (params.top_p);
            builder.set_member_name ("top_k");         builder.add_int_value (params.top_k);
            builder.set_member_name ("repeat_penalty");builder.add_double_value (params.repeat_penalty);
            builder.set_member_name ("presence_penalty"); builder.add_double_value (params.presence_penalty);
            builder.set_member_name ("frequency_penalty"); builder.add_double_value (params.frequency_penalty);
            if (params.seed >= 0) {
                builder.set_member_name ("seed");
                builder.add_int_value (params.seed);
            }
            if (params.max_tokens > 0) {
                builder.set_member_name ("max_tokens");
                builder.add_int_value (params.max_tokens);
            }
            builder.set_member_name ("enable_thinking");
            builder.add_boolean_value (params.enable_thinking);
            /* For llama.cpp: pass enable_thinking as a Jinja2 template variable.
               This is the mechanism used by Qwen3/similar chat templates to insert
               or suppress the <|im_start|>think token before the assistant turn. */
            builder.set_member_name ("chat_template_kwargs");
            builder.begin_object ();
            builder.set_member_name ("enable_thinking");
            builder.add_boolean_value (params.enable_thinking);
            builder.end_object ();
            if (tools != null && tools.get_length () > 0) {
                var tools_node = new Json.Node (Json.NodeType.ARRAY);
                tools_node.set_array (tools);
                builder.set_member_name ("tools");
                builder.add_value (tools_node);
                builder.set_member_name ("tool_choice");
                builder.add_string_value ("auto");
            }
            builder.end_object ();
            return builder.get_root ();
        }
    }
}

namespace LLMStudio {

    // OpenAI-compatible HTTP API server using libsoup-3.0
    public class OpenAIServer : Object {
        private Soup.Server?   server;
        private BackendManager backend_manager;
        private GLib.Settings  settings;
        private bool           _running;
        private int            _port;

        public signal void started     (string host, int port);
        public signal void stopped     ();
        public signal void request_log (string method, string path, int status);

        public bool is_running { get { return _running; } }
        public int  port       { get { return _port;    } }

        public OpenAIServer (BackendManager manager, GLib.Settings settings) {
            this.backend_manager = manager;
            this.settings        = settings;
        }

        public void start () throws Error {
            if (_running) return;

            server = new Soup.Server (null);

            server.add_handler ("/v1/models",           handle_models);
            server.add_handler ("/v1/chat/completions", handle_chat_completions);
            server.add_handler ("/health",              handle_health);
            server.add_handler (null,                   handle_not_found);

            var host_str = settings.get_string ("api-server-host");
            if (host_str == "") host_str = "127.0.0.1";
            _port = settings.get_int ("api-server-port");
            if (_port <= 0) _port = 1234;

            var addr = new GLib.InetSocketAddress (
                new GLib.InetAddress.from_string (host_str),
                (uint16) _port
            );
            server.listen (addr, 0);

            _running = true;
            started (host_str, _port);
        }

        public void stop () {
            if (!_running || server == null) return;
            server.disconnect ();
            server = null;
            _running = false;
            stopped ();
        }

        private void add_cors (Soup.ServerMessage msg) {
            if (!settings.get_boolean ("api-server-cors")) return;
            msg.get_response_headers ().replace ("Access-Control-Allow-Origin",  "*");
            msg.get_response_headers ().replace ("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            msg.get_response_headers ().replace ("Access-Control-Allow-Headers", "Content-Type, Authorization");
        }

        private void send_json (Soup.ServerMessage msg, uint code, string json) {
            add_cors (msg);
            msg.set_response ("application/json", Soup.MemoryUse.COPY, json.data);
            msg.set_status (code, null);
        }

        private void send_error (Soup.ServerMessage msg, uint code, string message) {
            var json = """{"error":{"message":"%s","code":%u}}""".printf (
                message.replace ("\"", "\\\""), code);
            send_json (msg, code, json);
        }

        private void handle_health (
            Soup.Server server, Soup.ServerMessage msg, string path,
            GLib.HashTable<string,string>? query
        ) {
            if (msg.get_method () == "OPTIONS") { send_json (msg, 200, "{}"); return; }
            var status_str = backend_manager.status == BackendStatus.READY ? "ok" : "loading";
            var model_name = backend_manager.loaded_model?.name ?? "";
            send_json (msg, 200, """{"status":"%s","model":"%s"}""".printf (status_str, model_name));
            request_log ("GET", "/health", 200);
        }

        private void handle_models (
            Soup.Server server, Soup.ServerMessage msg, string path,
            GLib.HashTable<string,string>? query
        ) {
            if (msg.get_method () == "OPTIONS") { send_json (msg, 200, "{}"); return; }

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("object"); builder.add_string_value ("list");
            builder.set_member_name ("data");   builder.begin_array ();

            if (backend_manager.loaded_model != null) {
                var m = backend_manager.loaded_model;
                builder.begin_object ();
                builder.set_member_name ("id");       builder.add_string_value (m.name);
                builder.set_member_name ("object");   builder.add_string_value ("model");
                builder.set_member_name ("created");  builder.add_int_value ((int64) GLib.get_real_time () / 1000000);
                builder.set_member_name ("owned_by"); builder.add_string_value ("local");
                builder.end_object ();
            }

            builder.end_array ();
            builder.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            send_json (msg, 200, gen.to_data (null));
            request_log ("GET", "/v1/models", 200);
        }

        private void handle_chat_completions (
            Soup.Server server, Soup.ServerMessage msg, string path,
            GLib.HashTable<string,string>? query
        ) {
            if (msg.get_method () == "OPTIONS") { send_json (msg, 200, "{}"); return; }
            if (msg.get_method () != "POST")    { send_error (msg, 405, "Method not allowed"); return; }

            if (backend_manager.status != BackendStatus.READY) {
                send_error (msg, 503, "No model loaded");
                request_log ("POST", "/v1/chat/completions", 503);
                return;
            }

            // Parse request body
            var flat = msg.get_request_body ().flatten ();
            var flat_data = flat.get_data ();
            if (flat_data == null || flat_data.length == 0) {
                send_error (msg, 400, "Empty body");
                return;
            }

            Json.Object? req_obj = null;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data ((string) flat_data);
                req_obj = parser.get_root ().get_object ();
            } catch (Error e) {
                send_error (msg, 400, "Invalid JSON: " + e.message);
                return;
            }

            if (req_obj == null || !req_obj.has_member ("messages")) {
                send_error (msg, 400, "Missing 'messages'");
                return;
            }

            var messages = req_obj.get_array_member ("messages");

            // Extract params
            var params = new ModelParams ();
            if (backend_manager.loaded_model != null)
                params = backend_manager.loaded_model.params.copy ();
            if (req_obj.has_member ("temperature"))
                params.temperature = req_obj.get_double_member ("temperature");
            if (req_obj.has_member ("top_p"))
                params.top_p = req_obj.get_double_member ("top_p");
            if (req_obj.has_member ("max_tokens"))
                params.max_tokens = (int) req_obj.get_int_member ("max_tokens");
            if (req_obj.has_member ("seed"))
                params.seed = (int) req_obj.get_int_member ("seed");
            if (req_obj.has_member ("presence_penalty"))
                params.presence_penalty = req_obj.get_double_member ("presence_penalty");
            if (req_obj.has_member ("frequency_penalty"))
                params.frequency_penalty = req_obj.get_double_member ("frequency_penalty");

            // Pause and handle async (we collect full response for simplicity)
            msg.pause ();
            handle_completion_async.begin (msg, messages, params);
            request_log ("POST", "/v1/chat/completions", 200);
        }

        private async void handle_completion_async (
            Soup.ServerMessage msg,
            Json.Array         messages,
            ModelParams        params
        ) {
            try {
                var content    = yield backend_manager.active_backend.chat_completion (messages, params);
                var model_name = backend_manager.loaded_model?.name ?? "unknown";
                var chat_id    = "chatcmpl-%s".printf (
                    GLib.Checksum.compute_for_string (GLib.ChecksumType.MD5,
                        GLib.get_real_time ().to_string ()));
                var created    = (int64) GLib.get_real_time () / 1000000;

                var builder = new Json.Builder ();
                builder.begin_object ();
                builder.set_member_name ("id");      builder.add_string_value (chat_id);
                builder.set_member_name ("object");  builder.add_string_value ("chat.completion");
                builder.set_member_name ("created"); builder.add_int_value (created);
                builder.set_member_name ("model");   builder.add_string_value (model_name);
                builder.set_member_name ("choices");
                builder.begin_array ();
                builder.begin_object ();
                builder.set_member_name ("index"); builder.add_int_value (0);
                builder.set_member_name ("message");
                builder.begin_object ();
                builder.set_member_name ("role");    builder.add_string_value ("assistant");
                builder.set_member_name ("content"); builder.add_string_value (content);
                builder.end_object ();
                builder.set_member_name ("finish_reason"); builder.add_string_value ("stop");
                builder.end_object ();
                builder.end_array ();
                builder.set_member_name ("usage");
                builder.begin_object ();
                builder.set_member_name ("prompt_tokens");     builder.add_int_value (0);
                builder.set_member_name ("completion_tokens"); builder.add_int_value (0);
                builder.set_member_name ("total_tokens");      builder.add_int_value (0);
                builder.end_object ();
                builder.end_object ();

                var gen = new Json.Generator ();
                gen.set_root (builder.get_root ());
                send_json (msg, 200, gen.to_data (null));
            } catch (Error e) {
                send_error (msg, 500, e.message);
            }
            msg.unpause ();
        }

        private void handle_not_found (
            Soup.Server server, Soup.ServerMessage msg, string path,
            GLib.HashTable<string,string>? query
        ) {
            send_error (msg, 404, "Not found: " + path);
        }
    }
}

namespace LLMStudio {

    public class VllmBackend : Backend {
        private GLib.Settings    settings;
        private GLib.Subprocess? process;
        private Soup.Session     session;
        private string           base_url;
        private GLib.Cancellable? load_cancel;

        public override BackendStatus status       { get; protected set; default = BackendStatus.IDLE; }
        public override ModelInfo?    loaded_model { get; protected set; default = null; }
        public override BackendType   backend_type { get { return BackendType.VLLM; } }

        public VllmBackend (GLib.Settings settings) {
            this.settings = settings;
            this.session  = new Soup.Session ();
            this.session.timeout = 0;
            this.base_url = settings.get_string ("vllm-host");
            if (base_url == "") base_url = "http://localhost:8000";
            settings.changed["vllm-host"].connect (() => {
                base_url = settings.get_string ("vllm-host");
            });
        }

        public override int get_server_port () {
            try {
                var uri = GLib.Uri.parse (base_url, GLib.UriFlags.NONE);
                int p = uri.get_port ();
                return p > 0 ? p : 8000;
            } catch (Error e) {
                return 8000;
            }
        }

        private async GLib.Bytes session_fetch (Soup.Message msg, GLib.Cancellable? cancel = null) throws Error {
            return yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancel);
        }

        public override async bool load_model (
            ModelInfo model,
            ModelParams params,
            GLib.Cancellable? cancel = null
        ) throws Error {
            load_cancel = cancel ?? new GLib.Cancellable ();
            status = BackendStatus.LOADING;
            status_changed (status);

            if (settings.get_boolean ("vllm-managed"))
                yield start_vllm_process (model, params);

            bool ready = yield wait_for_ready (load_cancel);
            if (!ready) {
                if (settings.get_boolean ("vllm-managed")) yield kill_process ();
                status = BackendStatus.ERROR;
                status_changed (status);
                throw new IOError.FAILED ("vLLM not reachable at %s".printf (base_url));
            }

            loaded_model = model;
            status = BackendStatus.READY;
            status_changed (status);
            model_loaded (model);
            return true;
        }

        private async void start_vllm_process (ModelInfo model, ModelParams params) throws Error {
            var argv = new string[] {
                "python3", "-m", "vllm.entrypoints.openai.api_server",
                "--model", model.path,
                "--host", "0.0.0.0",
                "--port", get_server_port ().to_string (),
                "--max-model-len", params.context_length.to_string ()
            };
            log_message ("Starting vLLM: " + string.joinv (" ", argv), false);
            process = new GLib.Subprocess.newv (argv,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
            monitor_output.begin ();
        }

        private async void monitor_output () {
            if (process == null) return;
            var istream = process.get_stdout_pipe ();
            if (istream == null) return;
            var ds = new GLib.DataInputStream (istream);
            string? line;
            try {
                while ((line = yield ds.read_line_async (GLib.Priority.DEFAULT, null)) != null)
                    log_message (line, false);
            } catch (Error e) {}
            if (status == BackendStatus.READY) {
                status = BackendStatus.ERROR;
                status_changed (status);
                log_message ("vLLM process exited", true);
            }
        }

        private async bool wait_for_ready (GLib.Cancellable cancel) {
            for (int i = 0; i < 180 && !cancel.is_cancelled (); i++) {
                yield vllm_sleep (1000);
                try {
                    var msg = new Soup.Message ("GET", base_url + "/health");
                    var bytes = yield session_fetch (msg, cancel);
                    if (msg.status_code < 500) return true;
                } catch (Error e) {}
            }
            return false;
        }

        private static async void vllm_sleep (uint ms) {
            GLib.Timeout.add (ms, () => { vllm_sleep.callback (); return false; });
            yield;
        }

        public override async bool unload_model () throws Error {
            if (status == BackendStatus.IDLE) return true;
            status = BackendStatus.UNLOADING;
            status_changed (status);
            if (load_cancel != null) load_cancel.cancel ();
            if (settings.get_boolean ("vllm-managed")) yield kill_process ();
            loaded_model = null;
            status = BackendStatus.IDLE;
            status_changed (status);
            model_unloaded ();
            return true;
        }

        private async void kill_process () {
            if (process == null) return;
            try { process.send_signal (15); } catch (Error e) {}
            bool exited = false;
            process.wait_async.begin (null, (obj, res) => {
                try { process.wait_async.end (res); } catch (Error e) {}
                exited = true;
            });
            for (int i = 0; i < 30 && !exited; i++)
                yield vllm_sleep (100);
            if (!exited) { try { process.force_exit (); } catch (Error e) {} }
            process = null;
        }

        public override async string chat_completion (
            Json.Array messages,
            ModelParams params,
            GLib.Cancellable? cancel = null
        ) throws Error {
            if (status != BackendStatus.READY)
                throw new IOError.NOT_CONNECTED ("vLLM not connected");

            var gen = new Json.Generator ();
            gen.set_root (make_chat_request_body (messages, params, false));
            var msg = new Soup.Message ("POST", base_url + "/v1/chat/completions");
            msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (gen.to_data (null).data));

            var bytes = yield session_fetch (msg, cancel);
            if (msg.status_code >= 400)
                throw new IOError.FAILED ("vLLM HTTP %u".printf (msg.status_code));

            var parser = new Json.Parser ();
            parser.load_from_data ((string) bytes.get_data ());
            return parser.get_root ().get_object ()
                .get_array_member ("choices").get_object_element (0)
                .get_object_member ("message").get_string_member ("content");
        }

        public override async void chat_completion_stream (
            Json.Array messages,
            ModelParams params,
            owned CompletionChunkCallback callback,
            GLib.Cancellable? cancel = null
        ) throws Error {
            if (status != BackendStatus.READY)
                throw new IOError.NOT_CONNECTED ("vLLM not connected");

            var gen = new Json.Generator ();
            gen.set_root (make_chat_request_body (messages, params, true));
            var msg = new Soup.Message ("POST", base_url + "/v1/chat/completions");
            msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (gen.to_data (null).data));

            var istream = yield session.send_async (msg, GLib.Priority.DEFAULT, cancel);
            if (msg.status_code >= 400)
                throw new IOError.FAILED ("vLLM HTTP %u".printf (msg.status_code));

            yield parse_sse_stream (istream, (owned) callback, cancel);
        }
    }
}

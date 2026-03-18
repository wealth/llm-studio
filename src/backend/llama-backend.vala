namespace LLMStudio {

    public class LlamaBackend : Backend {
        private GLib.Settings    settings;
        private GLib.Subprocess? process;
        private Soup.Session     session;
        private int              port;
        private BackendType      _type;
        private GLib.Cancellable? load_cancel;
        private string?          _load_error_hint  = null;
        private bool             _process_exited   = false;

        public override BackendStatus status       { get; protected set; default = BackendStatus.IDLE; }
        public override ModelInfo?    loaded_model { get; protected set; default = null; }
        public override BackendType   backend_type { get { return _type; } }

        public LlamaBackend (GLib.Settings settings, BackendType type = BackendType.LLAMA) {
            this.settings = settings;
            this._type    = type;
            this.session  = new Soup.Session ();
            this.session.timeout = 0;
            this.port     = find_free_port ();
        }

        private int find_free_port () {
            for (int p = 8080; p <= 8180; p++) {
                try {
                    var socket = new GLib.Socket (GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
                    var addr = new GLib.InetSocketAddress (
                        new GLib.InetAddress.loopback (GLib.SocketFamily.IPV4), (uint16) p);
                    socket.bind (addr, false);
                    socket.close ();
                    return p;
                } catch (Error e) { continue; }
            }
            return 8080;
        }

        public override int get_server_port () { return port; }

        private async GLib.Bytes session_fetch (Soup.Message msg, GLib.Cancellable? cancel = null) throws Error {
            return yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancel);
        }

        public override async bool load_model (
            ModelInfo model,
            ModelParams params,
            GLib.Cancellable? cancel = null
        ) throws Error {
            if (status == BackendStatus.LOADING || status == BackendStatus.READY)
                yield unload_model ();

            load_cancel      = cancel ?? new GLib.Cancellable ();
            _load_error_hint = null;
            _process_exited  = false;
            status = BackendStatus.LOADING;
            status_changed (status);

            string server_bin = _type == BackendType.IK_LLAMA ?
                settings.get_string ("ik-llama-server-path") :
                settings.get_string ("llama-server-path");
            if (server_bin == "") server_bin = "llama-server";

            var argv = new GLib.Array<string> ();
            argv.append_val (server_bin);
            argv.append_val ("--model");      argv.append_val (model.path);
            argv.append_val ("--host");       argv.append_val ("127.0.0.1");
            argv.append_val ("--port");       argv.append_val (port.to_string ());
            argv.append_val ("--ctx-size");   argv.append_val (params.context_length.to_string ());
            argv.append_val ("--batch-size"); argv.append_val (params.batch_size.to_string ());
            argv.append_val ("--ubatch-size");argv.append_val (params.ubatch_size.to_string ());

            int n_gpu = params.gpu_layers >= 0 ? params.gpu_layers : 999;
            argv.append_val ("--n-gpu-layers"); argv.append_val (n_gpu.to_string ());

            if (params.cpu_threads > 0) {
                argv.append_val ("--threads"); argv.append_val (params.cpu_threads.to_string ());
            }
            argv.append_val ("--flash-attn"); argv.append_val (params.flash_attention ? "on" : "off");
            if (params.mmap)   argv.append_val ("--mmap");
            else               argv.append_val ("--no-mmap");
            if (params.mlock)  argv.append_val ("--mlock");
            if (params.kv_cache_type != "f16") {
                argv.append_val ("--cache-type-k"); argv.append_val (params.kv_cache_type);
                argv.append_val ("--cache-type-v"); argv.append_val (params.kv_cache_type);
            }
            if (params.rope_freq_scale != 1.0) {
                argv.append_val ("--rope-scale"); argv.append_val (params.rope_freq_scale.to_string ());
            }
            if (params.rope_freq_base > 0) {
                argv.append_val ("--rope-freq-base"); argv.append_val (params.rope_freq_base.to_string ());
            }
            if (params.seed >= 0) {
                argv.append_val ("--seed"); argv.append_val (params.seed.to_string ());
            }

            if (model.has_vision && params.enable_vision) {
                var mmproj = find_mmproj (model.path);
                if (mmproj != "") {
                    argv.append_val ("--mmproj"); argv.append_val (mmproj);
                }
            }

            string[] argv_array = argv.data;
            log_message ("Starting %s: %s".printf (_type.display_name (), string.joinv (" ", argv_array)), false);

            try {
                process = new GLib.Subprocess.newv (argv_array,
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
            } catch (Error e) {
                status = BackendStatus.ERROR;
                status_changed (status);
                throw new IOError.FAILED ("Failed to start %s: %s".printf (_type.display_name (), e.message));
            }

            monitor_output.begin ();

            bool ready = yield wait_for_ready (load_cancel);
            if (!ready) {
                yield kill_process ();
                status = BackendStatus.ERROR;
                status_changed (status);
                if (load_cancel.is_cancelled ())
                    throw new IOError.CANCELLED ("Cancelled");
                string hint = _load_error_hint ?? "Server failed to start — check the Logs tab for details.";
                _load_error_hint = null;
                throw new IOError.FAILED (hint);
            }

            /* Warmup: send a minimal inference request so that CUDA kernel compilation
               and VRAM transfer complete before the user sends their first message.
               Without this the first real request can stall for minutes on first run. */
            log_message ("Warming up inference engine…", false);
            yield warmup_inference (load_cancel);
            if (load_cancel.is_cancelled ()) {
                yield kill_process ();
                status = BackendStatus.ERROR;
                status_changed (status);
                throw new IOError.CANCELLED ("Cancelled");
            }

            loaded_model = model;
            status = BackendStatus.READY;
            status_changed (status);
            model_loaded (model);
            return true;
        }

        private async void warmup_inference (GLib.Cancellable cancel) {
            try {
                var body = "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1,\"stream\":false}";
                var msg = new Soup.Message ("POST",
                    "http://127.0.0.1:%d/v1/chat/completions".printf (port));
                msg.set_request_body_from_bytes ("application/json",
                    new GLib.Bytes (body.data));
                yield session_fetch (msg, cancel);
                log_message ("Warmup complete", false);
            } catch (Error e) {
                log_message ("Warmup skipped: %s".printf (e.message), false);
            }
        }

        private async bool wait_for_ready (GLib.Cancellable cancel) {
            for (int i = 0; i < 120 && !cancel.is_cancelled (); i++) {
                yield llama_sleep (500);
                if (process == null || _process_exited) return false;
                try {
                    var msg = new Soup.Message ("GET", "http://127.0.0.1:%d/health".printf (port));
                    var bytes = yield session_fetch (msg, cancel);
                    if (msg.status_code < 500) return true;
                } catch (Error e) {}
            }
            return false;
        }

        private static async void llama_sleep (uint ms) {
            GLib.Timeout.add (ms, () => { llama_sleep.callback (); return false; });
            yield;
        }

        private async void monitor_output () {
            if (process == null) return;
            var istream = process.get_stdout_pipe ();
            if (istream == null) return;
            var ds = new GLib.DataInputStream (istream);
            string? line;
            try {
                while ((line = yield ds.read_line_async (GLib.Priority.DEFAULT, null)) != null) {
                    log_message (line, false);
                    // Capture the first actionable error hint for the load-failure dialog.
                    if (_load_error_hint == null) {
                        string lo = line.ascii_down ();
                        if (lo.contains ("outofdevicememory") || lo.contains ("outofhostmemory") ||
                                lo.contains ("failed to allocate") || lo.contains ("unable to allocate")) {
                            _load_error_hint = "Not enough VRAM/RAM to load the model.\n"
                                + "Open Load settings and reduce GPU Layers (set to 0 for CPU-only).";
                        } else if (lo.contains ("error loading model") || lo.contains ("failed to load model")) {
                            _load_error_hint = "Model loading failed — check the Logs tab for details.";
                        } else if (lo.contains ("tensor size mismatch") || lo.contains ("bad magic")) {
                            _load_error_hint = "Model file appears corrupt or incompatible.";
                        }
                    }
                }
            } catch (Error e) {}
            _process_exited = true;
            if (status == BackendStatus.READY) {
                status = BackendStatus.ERROR;
                status_changed (status);
                log_message ("Backend process exited unexpectedly", true);
            }
        }

        public override async bool unload_model () throws Error {
            if (status == BackendStatus.IDLE) return true;
            status = BackendStatus.UNLOADING;
            status_changed (status);
            if (load_cancel != null) load_cancel.cancel ();
            yield kill_process ();
            loaded_model = null;
            status = BackendStatus.IDLE;
            status_changed (status);
            model_unloaded ();
            return true;
        }

        /* Locate the best mmproj-*.gguf sidecar in the same directory as the model.
           Preference: BF16 > F16 > first found.  Returns "" if none present.    */
        private static string find_mmproj (string model_path) {
            string dir = GLib.Path.get_dirname (model_path);
            string best_bf16 = "", best_f16 = "", first = "";
            try {
                var enumerator = GLib.File.new_for_path (dir).enumerate_children (
                    GLib.FileAttribute.STANDARD_NAME, GLib.FileQueryInfoFlags.NONE);
                GLib.FileInfo? fi;
                while ((fi = enumerator.next_file ()) != null) {
                    string n = fi.get_name ().down ();
                    if (!n.has_prefix ("mmproj") || !n.has_suffix (".gguf")) continue;
                    string full = GLib.Path.build_filename (dir, fi.get_name ());
                    if (first == "") first = full;
                    if (n.contains ("bf16")) { best_bf16 = full; break; }
                    if (n.contains ("f16"))    best_f16  = full;
                }
            } catch (Error e) {}
            return best_bf16 != "" ? best_bf16
                 : best_f16  != "" ? best_f16
                 : first;
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
                yield llama_sleep (100);
            if (!exited) { try { process.force_exit (); } catch (Error e) {} }
            process = null;
        }

        public override async string chat_completion (
            Json.Array messages,
            ModelParams params,
            GLib.Cancellable? cancel = null
        ) throws Error {
            if (status != BackendStatus.READY)
                throw new IOError.NOT_CONNECTED ("No model loaded");

            var gen = new Json.Generator ();
            gen.set_root (make_chat_request_body (messages, params, false));
            var msg = new Soup.Message ("POST",
                "http://127.0.0.1:%d/v1/chat/completions".printf (port));
            msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (gen.to_data (null).data));

            var bytes = yield session_fetch (msg, cancel);
            if (msg.status_code >= 400)
                throw new IOError.FAILED ("Backend HTTP %u".printf (msg.status_code));

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
            GLib.Cancellable? cancel = null,
            Json.Array? tools = null
        ) throws Error {
            if (status != BackendStatus.READY)
                throw new IOError.NOT_CONNECTED ("No model loaded");

            var gen = new Json.Generator ();
            gen.set_root (make_chat_request_body (messages, params, true, tools));
            var msg = new Soup.Message ("POST",
                "http://127.0.0.1:%d/v1/chat/completions".printf (port));
            msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (gen.to_data (null).data));

            var istream = yield session.send_async (msg, GLib.Priority.DEFAULT, cancel);
            if (msg.status_code >= 400)
                throw new IOError.FAILED ("Backend HTTP %u".printf (msg.status_code));

            yield parse_sse_stream (istream, (owned) callback, cancel);
        }
    }
}

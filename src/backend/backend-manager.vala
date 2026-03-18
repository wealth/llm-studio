namespace LLMStudio {

    public class BackendManager : Object {
        private GLib.Settings  settings;
        private Backend?       _active;
        private GLib.List<ChatMessage> _conversation;

        public Backend?    active_backend  { get { return _active; } }
        public ModelInfo?  loaded_model    { get { if (_active == null) return null; return _active.loaded_model; } }
        public BackendStatus status        { get { if (_active == null) return BackendStatus.IDLE; return _active.status; } }

        public signal void status_changed  (BackendStatus s);
        public signal void model_loaded    (ModelInfo m);
        public signal void model_unloaded  ();
        public signal void log_message     (string line, bool is_error);
        public signal void chunk_received  (string chunk, bool done, string? finish_reason);
        public signal void backend_changed (BackendType t);

        public BackendManager (GLib.Settings settings) {
            this.settings      = settings;
            this._conversation = new GLib.List<ChatMessage> ();
            create_backend (BackendType.from_string (settings.get_string ("backend-type")));
        }

        private void create_backend (BackendType type) {
            if (_active != null) {
                _active.status_changed.disconnect (on_status_changed);
                _active.log_message.disconnect    (on_log_message);
                _active.model_loaded.disconnect   (on_model_loaded);
                _active.model_unloaded.disconnect (on_model_unloaded);
            }
            switch (type) {
                case BackendType.VLLM:     _active = new VllmBackend  (settings);                    break;
                case BackendType.IK_LLAMA: _active = new LlamaBackend (settings, BackendType.IK_LLAMA); break;
                default:                   _active = new LlamaBackend (settings, BackendType.LLAMA);  break;
            }
            _active.status_changed.connect (on_status_changed);
            _active.log_message.connect    (on_log_message);
            _active.model_loaded.connect   (on_model_loaded);
            _active.model_unloaded.connect (on_model_unloaded);
            settings.set_string ("backend-type", type.to_string ());
            backend_changed (type);
        }

        public async void switch_backend (BackendType type) {
            if (_active != null && _active.status == BackendStatus.READY)
                yield _active.unload_model ();
            create_backend (type);
        }

        private void on_status_changed (BackendStatus s) { status_changed (s); }
        private void on_log_message    (string l, bool e) { log_message (l, e); }
        private void on_model_loaded   (ModelInfo m)      { model_loaded (m); }
        private void on_model_unloaded ()                 { model_unloaded (); }

        public async bool load_model (ModelInfo model, ModelParams params,
                GLib.Cancellable? cancel = null) throws Error {
            if (_active == null) throw new IOError.FAILED ("No backend");
            return yield _active.load_model (model, params, cancel);
        }

        public async bool unload_model () throws Error {
            if (_active == null) return true;
            return yield _active.unload_model ();
        }

        public void clear_conversation () {
            _conversation = new GLib.List<ChatMessage> ();
        }

        public unowned GLib.List<ChatMessage> get_conversation () {
            return _conversation;
        }

        public void add_to_conversation (ChatMessage msg) {
            _conversation.append (msg);
        }

        public void delete_conversation_exchange_at (int idx) {
            var asst = _conversation.nth_data ((uint)(idx * 2 + 1));
            if (asst != null) _conversation.remove (asst);
            var user = _conversation.nth_data ((uint)(idx * 2));
            if (user != null) _conversation.remove (user);
        }

        public int get_server_port () {
            return _active?.get_server_port () ?? 0;
        }
    }
}

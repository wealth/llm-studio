namespace LLMStudio.UI {

    /* Vala bindings for the isolated C webkit glue (no soup-2.4 conflict). */
    [CCode (cname = "llm_webkit_new_webview",  cheader_filename = "ui/webkit-glue.h")]
    extern Gtk.Widget llm_webkit_new_webview ();

    [CCode (cname = "llm_webkit_load_html", cheader_filename = "ui/webkit-glue.h")]
    extern void llm_webkit_load_html (Gtk.Widget wv, string html, string? base_uri);

    [CCode (cname = "llm_webkit_run_js", cheader_filename = "ui/webkit-glue.h")]
    extern void llm_webkit_run_js (Gtk.Widget wv, string js);

    [CCode (cname = "LlmJsCallback", has_target = false)]
    private delegate void LlmJsCallback (string json, void* user_data);

    [CCode (cname = "llm_webkit_add_message_handler", cheader_filename = "ui/webkit-glue.h")]
    extern void llm_webkit_add_message_handler (Gtk.Widget wv, string name,
                                                LlmJsCallback cb, void* user_data);


    public class ChatView : Gtk.Box {

        private BackendManager    backend_manager;
        private GLib.Settings     settings;
        private ChatHistory       chat_history;
        private ToolManager       tool_manager;

        private Gtk.Widget        web_view;
        private Gtk.TextView      input_view;
        private Gtk.Button        send_btn;
        private Gtk.Button        stop_btn;
        private Gtk.Button        attach_btn;
        private Gtk.Box           pending_atts_bar;
        private GLib.Cancellable? current_request;

        /* Input toolbar indicators */
        private Gtk.ToggleButton  thinking_btn;
        private Gtk.Label         vision_tag;
        private Gtk.Label         ctx_lbl;
        private bool              thinking_guard = false;

        /* Pending attachments to send with the next message */
        private GLib.List<ChatAttachment> pending_attachments;

        /* Streaming state */
        private string?  streaming_id    = null;
        private int      msg_id_counter  = 0;
        private bool     think_complete  = false;

        public ChatView (BackendManager manager, GLib.Settings settings,
                         ChatHistory history, ToolManager tm)
        {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.backend_manager  = manager;
            this.settings         = settings;
            this.chat_history     = history;
            this.tool_manager     = tm;
            this.pending_attachments = new GLib.List<ChatAttachment> ();
            build_ui ();
            connect_signals ();
        }

        private void build_ui () {
            /* Resizable split: web view (top) | input (bottom) */
            var paned = new Gtk.Paned (Gtk.Orientation.VERTICAL);
            paned.vexpand            = true;
            paned.resize_start_child = true;
            paned.resize_end_child   = false;
            paned.shrink_start_child = false;
            paned.shrink_end_child   = false;
            append (paned);

            /* ── WebKit chat view ─────────────────────────────────── */
            web_view = llm_webkit_new_webview ();
            web_view.vexpand = true;
            web_view.hexpand = true;
            llm_webkit_add_message_handler (web_view, "llm", on_js_message_cb, this);
            load_blank_page ();
            paned.set_start_child (web_view);

            /* ── Input section ────────────────────────────────────── */
            var input_section = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            input_section.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var input_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            input_toolbar.margin_start  = 16;
            input_toolbar.margin_end    = 16;
            input_toolbar.margin_top    = 6;
            input_toolbar.margin_bottom = 0;

            var hint_lbl = new Gtk.Label ("Shift+Enter for new line");
            hint_lbl.add_css_class ("caption");
            hint_lbl.add_css_class ("dim-label");
            hint_lbl.halign  = Gtk.Align.START;
            hint_lbl.hexpand = true;
            input_toolbar.append (hint_lbl);

            /* ── Thinking toggle ───────────────────────────────────── */
            thinking_btn = new Gtk.ToggleButton ();
            thinking_btn.label         = "Thinking";
            thinking_btn.tooltip_text  = "Enable extended thinking (sends /think prefix)";
            thinking_btn.add_css_class ("thinking-toggle");
            thinking_btn.visible = false;
            thinking_btn.toggled.connect (() => {
                if (thinking_guard) return;
                if (backend_manager.loaded_model != null) {
                    backend_manager.loaded_model.params.enable_thinking = thinking_btn.active;
                    backend_manager.loaded_model.save_params ();
                }
            });
            input_toolbar.append (thinking_btn);

            /* ── Vision tag (unclickable) ──────────────────────────── */
            vision_tag = new Gtk.Label ("Vision");
            vision_tag.add_css_class ("input-tag");
            vision_tag.add_css_class ("input-tag-vision");
            vision_tag.tooltip_text = "Vision is enabled for this model";
            vision_tag.visible = false;
            input_toolbar.append (vision_tag);

            /* ── Context counter ───────────────────────────────────── */
            ctx_lbl = new Gtk.Label ("");
            ctx_lbl.add_css_class ("caption");
            ctx_lbl.add_css_class ("dim-label");
            ctx_lbl.add_css_class ("monospace");
            ctx_lbl.tooltip_text = "Estimated context usage";
            ctx_lbl.visible = false;
            input_toolbar.append (ctx_lbl);

            /* ── Copy HTML ─────────────────────────────────────────── */
            var copy_html_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            copy_html_btn.add_css_class ("flat");
            copy_html_btn.tooltip_text = "Copy chat as HTML";
            copy_html_btn.clicked.connect (() => {
                run_js ("llmCopyChat();");
                show_toast ("Chat copied to clipboard");
            });
            input_toolbar.append (copy_html_btn);

            attach_btn = new Gtk.Button.from_icon_name ("mail-attachment-symbolic");
            attach_btn.add_css_class ("flat");
            attach_btn.tooltip_text = "Attach image";
            attach_btn.visible      = false;   /* shown only for vision-capable models */
            attach_btn.clicked.connect (on_attach_clicked);
            input_toolbar.append (attach_btn);

            input_section.append (input_toolbar);

            /* Pending attachments bar — hidden when empty */
            pending_atts_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            pending_atts_bar.margin_start  = 16;
            pending_atts_bar.margin_end    = 16;
            pending_atts_bar.margin_top    = 4;
            pending_atts_bar.margin_bottom = 0;
            pending_atts_bar.visible       = false;
            input_section.append (pending_atts_bar);

            var input_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            input_box.margin_start  = 16;
            input_box.margin_end    = 16;
            input_box.margin_top    = 8;
            input_box.margin_bottom = 12;
            input_box.vexpand       = true;
            input_section.append (input_box);

            var input_scroll = new Gtk.ScrolledWindow ();
            input_scroll.hexpand            = true;
            input_scroll.vexpand            = true;
            input_scroll.min_content_height = 44;
            input_scroll.hscrollbar_policy  = Gtk.PolicyType.NEVER;
            input_scroll.vscrollbar_policy  = Gtk.PolicyType.AUTOMATIC;
            input_scroll.add_css_class ("card");

            input_view = new Gtk.TextView ();
            input_view.wrap_mode     = Gtk.WrapMode.WORD;
            input_view.top_margin    = 10;
            input_view.bottom_margin = 10;
            input_view.left_margin   = 12;
            input_view.right_margin  = 12;
            input_view.buffer.changed.connect (() => {
                update_send_btn_sensitivity ();
            });

            input_scroll.set_child (input_view);
            input_box.append (input_scroll);

            var btn_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            btn_box.valign = Gtk.Align.FILL;

            send_btn = new Gtk.Button.from_icon_name ("go-up-symbolic");
            send_btn.sensitive     = false;
            send_btn.tooltip_text  = "Send (Enter)";
            send_btn.vexpand       = true;
            send_btn.width_request = 44;
            send_btn.clicked.connect (on_send_clicked);

            stop_btn = new Gtk.Button.from_icon_name ("media-playback-stop-symbolic");
            stop_btn.visible       = false;
            stop_btn.vexpand       = true;
            stop_btn.width_request = 44;
            stop_btn.tooltip_text  = "Stop generation";
            stop_btn.clicked.connect (on_stop_clicked);

            btn_box.append (send_btn);
            btn_box.append (stop_btn);
            input_box.append (btn_box);

            var key_ctrl = new Gtk.EventControllerKey ();
            input_view.add_controller (key_ctrl);
            key_ctrl.key_pressed.connect (on_key_pressed);

            paned.set_end_child (input_section);
        }

        public signal void show_toast (string message);

        private void connect_signals () {
            backend_manager.status_changed.connect (on_backend_status_changed);
            backend_manager.model_loaded.connect (_ => {
                update_attach_btn_visibility ();
                update_input_indicators ();
            });
            backend_manager.model_unloaded.connect (() => {
                update_attach_btn_visibility ();
                thinking_btn.visible = false;
                vision_tag.visible   = false;
                ctx_lbl.visible      = false;
            });
        }

        /* ── Public API ──────────────────────────────────────────────── */

        public void new_chat () {
            msg_id_counter = 0;
            backend_manager.clear_conversation ();
            chat_history.new_session ();
            load_blank_page ();
            update_context_counter ();
        }

        public void load_session (ChatSession session) {
            msg_id_counter = 0;
            backend_manager.clear_conversation ();
            chat_history.switch_to (session);

            var model_name = humanized_model_name (backend_manager.loaded_model);
            unowned var msgs = session.get_messages ();

            /* Render the full session as a single HTML page. */
            string html = HtmlRenderer.get_session_html (msgs, model_name);
            llm_webkit_load_html (web_view, html, HtmlRenderer.BASE_URI);

            /* Keep backend conversation in sync. */
            foreach (var m in msgs) {
                backend_manager.add_to_conversation (m);
                if (m.role == "assistant") msg_id_counter++;
            }
            update_context_counter ();
        }

        /* ── Input indicator helpers ─────────────────────────────────── */

        private void update_input_indicators () {
            var model = backend_manager.loaded_model;
            if (model == null) {
                thinking_btn.visible = false;
                vision_tag.visible   = false;
                ctx_lbl.visible      = false;
                return;
            }
            /* Thinking toggle */
            thinking_btn.visible = model.has_thinking;
            if (model.has_thinking) {
                thinking_guard = true;
                thinking_btn.active = model.params.enable_thinking;
                thinking_guard = false;
            }
            /* Vision tag */
            vision_tag.visible = model.has_vision && model.params.enable_vision;
            /* Context counter */
            update_context_counter ();
        }

        private void update_context_counter () {
            var model = backend_manager.loaded_model;
            if (model == null || model.params.context_length <= 0) {
                ctx_lbl.visible = false;
                return;
            }
            /* Estimate token count as total conversation chars / 4 */
            int total_chars = 0;
            foreach (var msg in backend_manager.get_conversation ())
                total_chars += msg.content.length;
            int est  = total_chars / 4;
            int ctx  = model.params.context_length;
            int pct  = (int) (est * 100.0 / ctx);
            if (pct > 100) pct = 100;

            ctx_lbl.label   = "%d%%".printf (pct);
            ctx_lbl.visible = true;

            if (pct >= 80) {
                ctx_lbl.remove_css_class ("dim-label");
                ctx_lbl.add_css_class    ("error");
            } else if (pct >= 60) {
                ctx_lbl.remove_css_class ("dim-label");
                ctx_lbl.remove_css_class ("error");
                ctx_lbl.add_css_class    ("warning");
            } else {
                ctx_lbl.remove_css_class ("error");
                ctx_lbl.remove_css_class ("warning");
                ctx_lbl.add_css_class    ("dim-label");
            }
        }

        /* ── Internal helpers ─────────────────────────────────────────── */

        private void load_blank_page () {
            llm_webkit_load_html (web_view, HtmlRenderer.get_page_html (),
                                  HtmlRenderer.BASE_URI);
        }

        private void run_js (string js) {
            llm_webkit_run_js (web_view, js);
        }

        /* Return a human-readable model label: "publisher/clean-name" or just "clean-name". */
        private static string humanized_model_name (ModelInfo? model) {
            if (model == null) return "Assistant";
            var pub = model.publisher ();
            return pub != "" ? pub + "/" + model.clean_name ().down ()
                             : model.clean_name ().down ();
        }

        /* Escape a value for embedding in a JS double-quoted string. */
        private static string j (string s) {
            return HtmlRenderer.js_str (s);
        }

        /* Allocate a new unique message ID string, e.g. "m3". */
        private string next_msg_id () {
            return "m%d".printf (msg_id_counter++);
        }

        /* Parse full_content into think and response parts, merging any
           consecutive <think> blocks (some servers send duplicates).    */
        private static void parse_think_resp (string full_content,
                                              out string think, out string resp)
        {
            think = "";
            resp  = full_content;
            if (!full_content.has_prefix ("<think>")) return;

            string remaining = full_content.substring (7);
            while (true) {
                int end = remaining.index_of ("</think>");
                if (end < 0) {
                    /* Think block not yet closed (streaming). */
                    think += remaining;
                    resp   = "";
                    break;
                }
                think    += remaining.substring (0, end);
                remaining = remaining.substring (end + 8).strip ();
                if (remaining.has_prefix ("<think>")) {
                    /* Consecutive think block — merge with separator. */
                    think    += "\n\n";
                    remaining = remaining.substring (7);
                } else {
                    resp = remaining;
                    break;
                }
            }
            think = think.strip ();
            resp  = resp.strip ();
        }

        /* Update streaming display from the current accumulated content. */
        private void update_streaming (string full_content) {
            if (streaming_id == null) return;

            if (full_content.has_prefix ("<think>")) {
                string think_raw, resp_raw;
                parse_think_resp (full_content, out think_raw, out resp_raw);

                if (resp_raw == "" && !full_content.contains ("</think>")) {
                    /* Still inside think block(s) — show raw text live. */
                    run_js (@"llmSetThink(\"$(streaming_id)\",\"$(j(think_raw))\");");
                    return;
                }

                /* Think block(s) finished — update think once, then stream response. */
                if (!think_complete) {
                    think_complete = true;
                    run_js (@"llmSetThink(\"$(streaming_id)\",\"$(j(think_raw))\");");
                }
                if (resp_raw != "") {
                    string resp_html = HtmlRenderer.render_markdown (resp_raw);
                    run_js (@"llmSetContent(\"$(streaming_id)\",\"$(j(resp_html))\");");
                }

            } else {
                /* No think block — render accumulated response as markdown. */
                if (full_content != "") {
                    string resp_html = HtmlRenderer.render_markdown (full_content);
                    run_js (@"llmSetContent(\"$(streaming_id)\",\"$(j(resp_html))\");");
                }
            }
        }

        /* Finalize the streaming message with fully rendered markdown+KaTeX. */
        private void finalize_streaming (string full_content, string stats) {
            if (streaming_id == null) return;

            string think, resp;
            parse_think_resp (full_content, out think, out resp);

            string resp_html = resp != "" ? HtmlRenderer.render_markdown (resp) : "";

            run_js (@"llmFinalize(\"$(streaming_id)\",\"$(j(think))\",\"$(j(resp_html))\",\"$(j(resp))\");");

            if (stats != "")
                run_js (@"llmSetStats(\"$(streaming_id)\",\"$(j(stats))\");");

            streaming_id   = null;
            think_complete = false;
        }

        /* ── Event handlers ──────────────────────────────────────────── */

        private void update_attach_btn_visibility () {
            attach_btn.visible = backend_manager.loaded_model != null &&
                                 backend_manager.loaded_model.has_vision &&
                                 backend_manager.loaded_model.params.enable_vision;
            /* Clear any pending image attachments if model no longer supports vision */
            if (!attach_btn.visible) {
                pending_attachments = new GLib.List<ChatAttachment> ();
                refresh_pending_atts_ui ();
            }
        }

        private void update_send_btn_sensitivity () {
            bool has_content = input_view.buffer.text.strip () != "" ||
                               pending_attachments.length () > 0;
            send_btn.sensitive = has_content &&
                backend_manager.status == BackendStatus.READY;
        }

        private void on_backend_status_changed (BackendStatus s) {
            update_send_btn_sensitivity ();
        }

        private bool on_key_pressed (Gtk.EventControllerKey ctrl,
                uint keyval, uint keycode, Gdk.ModifierType state)
        {
            bool shift_held = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) && !shift_held) {
                if (send_btn.sensitive) on_send_clicked ();
                return true;
            }
            return false;
        }

        /* ── Attachment handling ─────────────────────────────────────── */

        private void on_attach_clicked () {
            do_attach.begin ();
        }

        private async void do_attach () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Attach File";

            var all_filter = new Gtk.FileFilter ();
            all_filter.name = "Images & Text";
            all_filter.add_mime_type ("image/png");
            all_filter.add_mime_type ("image/jpeg");
            all_filter.add_mime_type ("image/gif");
            all_filter.add_mime_type ("image/webp");
            all_filter.add_mime_type ("text/plain");
            all_filter.add_mime_type ("text/markdown");
            all_filter.add_mime_type ("text/x-python");
            all_filter.add_mime_type ("text/x-csrc");
            all_filter.add_mime_type ("text/x-chdr");
            all_filter.add_mime_type ("application/json");

            var img_filter = new Gtk.FileFilter ();
            img_filter.name = "Images";
            img_filter.add_mime_type ("image/png");
            img_filter.add_mime_type ("image/jpeg");
            img_filter.add_mime_type ("image/gif");
            img_filter.add_mime_type ("image/webp");

            var txt_filter = new Gtk.FileFilter ();
            txt_filter.name = "Text files";
            txt_filter.add_mime_type ("text/plain");
            txt_filter.add_mime_type ("text/markdown");
            txt_filter.add_mime_type ("text/x-python");
            txt_filter.add_mime_type ("application/json");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (all_filter);
            filters.append (img_filter);
            filters.append (txt_filter);
            dialog.filters = filters;
            dialog.default_filter = all_filter;

            try {
                var file = yield dialog.open ((Gtk.Window) get_root (), null);
                if (file != null) add_attachment_from_file (file);
            } catch (Error e) {
                /* user cancelled — ignore */
            }
        }

        private void add_attachment_from_file (GLib.File file) {
            try {
                var info = file.query_info (
                    GLib.FileAttribute.STANDARD_CONTENT_TYPE + "," +
                    GLib.FileAttribute.STANDARD_DISPLAY_NAME,
                    GLib.FileQueryInfoFlags.NONE);
                string mime_type    = info.get_content_type () ?? "application/octet-stream";
                string display_name = info.get_display_name ();

                string etag_out;
                var bytes = file.load_bytes (null, out etag_out);

                var att = new ChatAttachment ();
                att.filename  = display_name;
                att.mime_type = mime_type;

                if (att.is_image ()) {
                    /* Reject if the loaded model has no vision capability */
                    bool model_has_vision =
                        backend_manager.loaded_model != null &&
                        backend_manager.loaded_model.has_vision &&
                        backend_manager.loaded_model.params.enable_vision;
                    if (!model_has_vision) {
                        show_toast ("The loaded model does not support image input");
                        return;
                    }
                    /* Scale down and re-encode as JPEG to reduce tile count. */
                    att.data      = encode_image_scaled (bytes);
                    att.mime_type = "image/jpeg";
                } else {
                    /* Treat as UTF-8 text */
                    att.data = (string) bytes.get_data ();
                }

                pending_attachments.append (att);
                refresh_pending_atts_ui ();
            } catch (Error e) {
                warning ("Attachment read failed: %s", e.message);
            }
        }

        private static string encode_image_scaled (GLib.Bytes raw) {
            const int MAX_DIM = 1120;
            try {
                var stream = new GLib.MemoryInputStream.from_bytes (raw);
                var pb = new Gdk.Pixbuf.from_stream (stream, null);
                int w = pb.width;
                int h = pb.height;
                if (w > MAX_DIM || h > MAX_DIM) {
                    double scale = double.min ((double) MAX_DIM / w, (double) MAX_DIM / h);
                    pb = pb.scale_simple ((int)(w * scale), (int)(h * scale), Gdk.InterpType.BILINEAR);
                }
                uint8[] out_buf;
                string[] opt_keys = { "quality", null };
                string[] opt_vals = { "90", null };
                pb.save_to_bufferv (out out_buf, "jpeg", opt_keys, opt_vals);
                return GLib.Base64.encode (out_buf);
            } catch (Error e) {
                warning ("Image scale failed: %s — sending original", e.message);
                return GLib.Base64.encode (raw.get_data ());
            }
        }

        private void refresh_pending_atts_ui () {
            /* Remove old chips */
            Gtk.Widget? child;
            while ((child = pending_atts_bar.get_first_child ()) != null)
                pending_atts_bar.remove (child);

            foreach (var att in pending_attachments)
                pending_atts_bar.append (make_attachment_chip (att));

            pending_atts_bar.visible = pending_attachments.length () > 0;
            update_send_btn_sensitivity ();
        }

        private Gtk.Widget make_attachment_chip (ChatAttachment att) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box.add_css_class ("linked");

            string icon_name = att.is_image ()
                ? "image-x-generic-symbolic"
                : "text-x-generic-symbolic";

            var lbl_btn = new Gtk.Button ();
            lbl_btn.add_css_class ("flat");
            var lbl_inner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var icon = new Gtk.Image.from_icon_name (icon_name);
            icon.pixel_size = 16;
            var lbl = new Gtk.Label (att.filename);
            lbl.max_width_chars = 18;
            lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            lbl_inner.append (icon);
            lbl_inner.append (lbl);
            lbl_btn.set_child (lbl_inner);

            var rm_btn = new Gtk.Button.from_icon_name ("window-close-symbolic");
            rm_btn.add_css_class ("flat");
            rm_btn.clicked.connect (() => {
                pending_attachments.remove (att);
                refresh_pending_atts_ui ();
            });

            box.append (lbl_btn);
            box.append (rm_btn);
            return box;
        }

        /* Serialise an attachment list to a JSON string for JS llmAddUser(). */
        private string build_atts_display_json_from (GLib.List<ChatAttachment> atts) {
            var sb = new StringBuilder ("[");
            bool first = true;
            foreach (var att in atts) {
                if (!first) sb.append (",");
                first = false;
                if (att.is_image ()) {
                    sb.append ("{\"type\":\"image\",\"filename\":\"");
                    sb.append (HtmlRenderer.js_str (att.filename));
                    sb.append ("\",\"src\":\"");
                    sb.append (HtmlRenderer.js_str (att.to_data_uri ()));
                    sb.append ("\"}");
                } else {
                    sb.append ("{\"type\":\"file\",\"filename\":\"");
                    sb.append (HtmlRenderer.js_str (att.filename));
                    sb.append ("\"}");
                }
            }
            sb.append ("]");
            return sb.str;
        }

        private void on_send_clicked () {
            var text = input_view.buffer.text.strip ();
            bool has_atts = pending_attachments.length () > 0;
            if (text == "" && !has_atts) return;
            if (backend_manager.status != BackendStatus.READY) return;

            if (chat_history.current == null)
                chat_history.new_session ();

            bool is_first_message = chat_history.current.message_count () == 0;

            /* Snapshot attachments, then clear pending state */
            var atts = (owned) pending_attachments;
            pending_attachments = new GLib.List<ChatAttachment> ();
            refresh_pending_atts_ui ();

            input_view.buffer.text = "";
            send_btn.sensitive     = false;
            send_btn.visible       = false;
            stop_btn.visible       = true;
            current_request        = new GLib.Cancellable ();

            /* Show user bubble with attachments — render markdown+LaTeX */
            string user_html_content = text != "" ? HtmlRenderer.render_markdown (text) : "";
            string atts_json = build_atts_display_json_from (atts);
            int exchange_idx = msg_id_counter;
            streaming_id   = next_msg_id ();
            run_js (@"llmAddUser($(exchange_idx),\"$(j(user_html_content))\",\"$(j(atts_json))\");");

            /* Create assistant message slot */
            think_complete = false;

            string model_name = humanized_model_name (backend_manager.loaded_model);
            run_js (@"llmStartAssistant(\"$(streaming_id)\",\"$(j(model_name))\");");

            do_send.begin (text, (owned) atts, is_first_message);
        }

        private async void do_send (string text, owned GLib.List<ChatAttachment> atts,
                                    bool is_first_message)
        {
            int64  request_start        = GLib.get_monotonic_time ();
            int64  first_token_us       = -1;
            int64  response_start_us    = -1;   // when first non-think token arrives
            int    token_count          = 0;
            int    response_token_count = 0;
            string? last_reason         = null;
            string full_content         = "";
            bool   stream_complete      = false;
            string model_name           = humanized_model_name (backend_manager.loaded_model);

            /* Build user message outside the try so it's accessible when persisting. */
            var user_msg = new ChatMessage.user (text);
            foreach (var att in atts)
                user_msg.attachments.append (att);

            try {
                var params = backend_manager.loaded_model?.params ?? new ModelParams ();
                var model  = backend_manager.loaded_model;
                var messages = new Json.Array ();

                /* Build system message, injecting /no_think when thinking is disabled
                   for models that support it. llama.cpp respects this prefix token;
                   the enable_thinking field in the request body is for ik_llama.cpp. */
                var system_text = params.system_prompt;
                if (model != null && model.has_thinking && !params.enable_thinking)
                    system_text = "/no_think" + (system_text != "" ? "\n\n" + system_text : "");

                if (system_text != "") {
                    var sys = new Json.Object ();
                    sys.set_string_member ("role",    "system");
                    sys.set_string_member ("content", system_text);
                    var n = new Json.Node (Json.NodeType.OBJECT);
                    n.set_object (sys);
                    messages.add_element (n);
                }

                unowned GLib.List<ChatMessage> conv = backend_manager.get_conversation ();
                foreach (var m in conv) {
                    var o = new Json.Object ();
                    o.set_string_member ("role", m.role);
                    o.set_member ("content", Backend.build_content_node (m));
                    var n = new Json.Node (Json.NodeType.OBJECT);
                    n.set_object (o);
                    messages.add_element (n);
                }

                var user_o = new Json.Object ();
                user_o.set_string_member ("role", "user");
                user_o.set_member ("content", Backend.build_content_node (user_msg));
                var user_n = new Json.Node (Json.NodeType.OBJECT);
                user_n.set_object (user_o);
                messages.add_element (user_n);

                Json.Array? tools = tool_manager.get_tools_array ();
                int tool_iterations = 0;

                while (true) {
                    /* Reset per-iteration streaming state */
                    full_content    = "";
                    last_reason     = null;
                    stream_complete = false;
                    think_complete  = false;

                    yield backend_manager.active_backend.chat_completion_stream (
                        messages, params,
                        (chunk, done, reason) => {
                            if (chunk.length > 0) {
                                if (first_token_us < 0)
                                    first_token_us = GLib.get_monotonic_time ();
                                token_count++;
                                full_content += chunk;
                                bool in_think = full_content.has_prefix ("<think>") &&
                                                full_content.index_of ("</think>") < 0;
                                if (!in_think) {
                                    if (response_start_us < 0)
                                        response_start_us = GLib.get_monotonic_time ();
                                    response_token_count++;
                                }
                                update_streaming (full_content);
                            }
                            if (reason != null && reason.length > 0)
                                last_reason = reason;
                            if (done)
                                stream_complete = true;
                        },
                        current_request,
                        tools
                    );

                    /* Tool-call agentic loop: execute tools and continue */
                    if (last_reason == "tool_calls" && tool_iterations < 5) {
                        if (yield execute_tool_calls (messages)) {
                            tool_iterations++;
                            continue;
                        }
                    }
                    break;
                }

            } catch (Error e) {
                if (!(e is IOError.CANCELLED)) {
                    full_content = "\u26a0 Error: " + e.message;
                    update_streaming (full_content);
                }
            }

            /* Build stats string */
            string stats = "";
            if (first_token_us >= 0) {
                int64  now     = GLib.get_monotonic_time ();
                double ttft_s  = (first_token_us - request_start) / 1000000.0;
                double total_s = (now - request_start) / 1000000.0;
                /* Use response-only rate when thinking was present, total rate otherwise */
                double tps;
                int    display_tokens;
                if (response_start_us >= 0 && response_token_count > 0) {
                    double resp_s = (now - response_start_us) / 1000000.0;
                    tps           = resp_s > 0.001 ? response_token_count / resp_s : 0.0;
                    display_tokens = response_token_count;
                } else {
                    double gen_s = (now - first_token_us) / 1000000.0;
                    tps          = gen_s > 0.001 ? token_count / gen_s : 0.0;
                    display_tokens = token_count;
                }
                stats = "%.1f tok/s \u00b7 %d tokens \u00b7 ttft %.1fs \u00b7 %.1fs total".printf (
                            tps, display_tokens, ttft_s, total_s);
                if (last_reason != null) stats += " \u00b7 %s".printf (last_reason);
            }

            /* Persist the completed exchange with model name and stats. */
            if (stream_complete) {
                var asst_msg = new ChatMessage.assistant (full_content);
                asst_msg.model_name = model_name;
                asst_msg.stats_text = stats;
                backend_manager.get_conversation ().append (user_msg);
                backend_manager.get_conversation ().append (asst_msg);
                if (chat_history.current != null) {
                    chat_history.current.add_message (user_msg);
                    chat_history.current.add_message (asst_msg);
                    if (is_first_message)
                        chat_history.auto_title (text);
                    chat_history.mark_updated ();
                }
            }

            finalize_streaming (full_content, stats);
            update_context_counter ();

            current_request  = null;
            stop_btn.visible = false;
            send_btn.visible = true;
            update_send_btn_sensitivity ();
        }

        private void on_stop_clicked () {
            current_request?.cancel ();
        }

        /* Execute any pending tool calls from the backend, add messages, update UI.
           Returns true if at least one tool was executed successfully.              */
        private async bool execute_tool_calls (Json.Array messages) {
            string? tc_json = backend_manager.active_backend.pending_tool_call_json;
            if (tc_json == null) return false;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (tc_json);
                var tc_arr = parser.get_root ().get_array ();
                if (tc_arr.get_length () == 0) return false;

                /* Add assistant message with tool_calls field */
                var asst_o = new Json.Object ();
                asst_o.set_string_member ("role",    "assistant");
                asst_o.set_string_member ("content", "");
                var tc_msg_arr = new Json.Array ();
                for (int i = 0; i < (int) tc_arr.get_length (); i++) {
                    var tc = tc_arr.get_object_element (i);
                    var tc_msg = new Json.Object ();
                    tc_msg.set_string_member ("id",   tc.get_string_member ("id"));
                    tc_msg.set_string_member ("type", "function");
                    var fn_o = new Json.Object ();
                    fn_o.set_string_member ("name",      tc.get_string_member ("name"));
                    fn_o.set_string_member ("arguments", tc.get_string_member ("arguments"));
                    var fn_n = new Json.Node (Json.NodeType.OBJECT);
                    fn_n.set_object (fn_o);
                    tc_msg.set_member ("function", fn_n);
                    var tc_msg_n = new Json.Node (Json.NodeType.OBJECT);
                    tc_msg_n.set_object (tc_msg);
                    tc_msg_arr.add_element (tc_msg_n);
                }
                var tc_arr_n = new Json.Node (Json.NodeType.ARRAY);
                tc_arr_n.set_array (tc_msg_arr);
                asst_o.set_member ("tool_calls", tc_arr_n);
                var asst_n = new Json.Node (Json.NodeType.OBJECT);
                asst_n.set_object (asst_o);
                messages.add_element (asst_n);

                /* Execute each tool and add result messages */
                for (int i = 0; i < (int) tc_arr.get_length (); i++) {
                    var tc = tc_arr.get_object_element (i);
                    string tc_id   = tc.get_string_member ("id");
                    string tc_name = tc.get_string_member ("name");
                    string tc_args = tc.get_string_member ("arguments");

                    /* Show "working" status in the streaming slot */
                    string display = tool_call_display (tc_name, tc_args);
                    string disp_html = HtmlRenderer.html_esc (display);
                    run_js (@"llmSetContent(\"$(streaming_id)\",\"$(j(disp_html))\");");

                    string result = yield tool_manager.execute_async (
                        tc_name, tc_args, current_request);

                    /* Collapse the tool call into a details element */
                    run_js (@"llmAddToolCall(\"$(streaming_id)\",\"$(j(display))\",\"$(j(result))\");");

                    /* Reset resp to loading dots for the next model response */
                    run_js (@"llmSetContent(\"$(streaming_id)\",\"<span class=\\\"dot\\\"></span>\");");

                    /* Add tool result message */
                    var tool_o = new Json.Object ();
                    tool_o.set_string_member ("role",         "tool");
                    tool_o.set_string_member ("tool_call_id", tc_id);
                    tool_o.set_string_member ("content",      result);
                    var tool_n = new Json.Node (Json.NodeType.OBJECT);
                    tool_n.set_object (tool_o);
                    messages.add_element (tool_n);
                }
                return true;
            } catch (Error e) {
                warning ("Tool call execution error: %s", e.message);
                return false;
            }
        }

        /* ── JS → Vala message bridge ────────────────────────────────── */

        private static void on_js_message_cb (string json, void* user_data) {
            unowned ChatView self = (ChatView) user_data;
            self.handle_js_message (json);
        }

        private void handle_js_message (string json) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
                var obj = parser.get_root ().get_object ();
                string action = obj.get_string_member ("action");
                if (action == "delete") {
                    int idx = (int) obj.get_int_member ("index");
                    delete_exchange (idx);
                }
            } catch (Error e) {
                warning ("JS message parse error: %s", e.message);
            }
        }

        private void delete_exchange (int idx) {
            backend_manager.delete_conversation_exchange_at (idx);
            if (chat_history.current != null) {
                chat_history.current.delete_exchange_at (idx);
                chat_history.save ();
            }
            update_context_counter ();
        }

        private string tool_call_display (string name, string args_json) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (args_json);
                var args = parser.get_root ().get_object ();
                switch (name) {
                    case "duckduckgo_search":
                        return "\xf0\x9f\x94\x8d " + (args.has_member ("query")
                            ? args.get_string_member ("query") : name);
                    case "visit_website":
                        return "\xf0\x9f\x8c\x90 " + (args.has_member ("url")
                            ? args.get_string_member ("url") : name);
                    default:
                        return name;
                }
            } catch (Error e) {
                return name;
            }
        }
    }
}

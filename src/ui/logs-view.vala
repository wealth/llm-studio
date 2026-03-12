namespace LLMStudio.UI {

    public class LogsView : Gtk.Box {
        private BackendManager backend_manager;
        private Gtk.TextView   log_view;
        private Gtk.TextBuffer log_buffer;
        private Gtk.TextTag    tag_error;
        private Gtk.TextTag    tag_info;
        private Gtk.TextTag    tag_system;
        private Gtk.Switch     auto_scroll_switch;
        private bool           auto_scroll = true;
        private int            max_lines   = 5000;

        public LogsView (BackendManager manager) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.backend_manager = manager;
            build_ui ();
            connect_signals ();
        }

        private void build_ui () {
            // Toolbar
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            toolbar.margin_start  = 12;
            toolbar.margin_end    = 12;
            toolbar.margin_top    = 8;
            toolbar.margin_bottom = 8;

            var title = new Gtk.Label ("Backend Logs");
            title.add_css_class ("title-4");
            title.hexpand = true;
            title.halign  = Gtk.Align.START;
            toolbar.append (title);

            var auto_scroll_lbl = new Gtk.Label ("Auto-scroll");
            auto_scroll_lbl.add_css_class ("caption");
            auto_scroll_switch = new Gtk.Switch ();
            auto_scroll_switch.active = true;
            auto_scroll_switch.valign = Gtk.Align.CENTER;
            auto_scroll_switch.notify["active"].connect (() => {
                auto_scroll = auto_scroll_switch.active;
            });
            toolbar.append (auto_scroll_lbl);
            toolbar.append (auto_scroll_switch);

            var clear_btn = new Gtk.Button.from_icon_name ("edit-clear-symbolic");
            clear_btn.tooltip_text = "Clear logs";
            clear_btn.add_css_class ("flat");
            clear_btn.clicked.connect (() => log_buffer.set_text ("", 0));
            toolbar.append (clear_btn);

            var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            copy_btn.tooltip_text = "Copy all logs";
            copy_btn.add_css_class ("flat");
            copy_btn.clicked.connect (() => {
                Gtk.TextIter start, end;
                log_buffer.get_bounds (out start, out end);
                get_display ().get_clipboard ().set_text (log_buffer.get_text (start, end, false));
            });
            toolbar.append (copy_btn);

            append (toolbar);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Text view
            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.kinetic_scrolling = true;
            append (scroll);

            log_buffer = new Gtk.TextBuffer (null);
            tag_error  = log_buffer.create_tag ("error",  "foreground", "#e01b24", null);
            tag_info   = log_buffer.create_tag ("info",   "foreground", "#1c71d8", null);
            tag_system = log_buffer.create_tag ("system", "foreground", "#26a269",
                "style", Pango.Style.ITALIC, null);

            log_view = new Gtk.TextView.with_buffer (log_buffer);
            log_view.editable       = false;
            log_view.monospace      = true;
            log_view.cursor_visible = false;
            log_view.wrap_mode      = Gtk.WrapMode.CHAR;
            log_view.top_margin     = 8;
            log_view.bottom_margin  = 8;
            log_view.left_margin    = 12;
            log_view.right_margin   = 12;
            scroll.set_child (log_view);

            // Initial message
            append_system ("LLM Studio backend log. Start a model to see output here.\n");
        }

        private void connect_signals () {
            backend_manager.log_message.connect ((line, is_error) => {
                Idle.add (() => {
                    append_line (line + "\n", is_error);
                    return false;
                });
            });

            backend_manager.status_changed.connect (s => {
                Idle.add (() => {
                    switch (s) {
                        case BackendStatus.LOADING:
                            append_system ("▶ Loading model…\n");
                            break;
                        case BackendStatus.READY:
                            append_system ("✓ Model ready\n");
                            break;
                        case BackendStatus.UNLOADING:
                            append_system ("◼ Unloading model…\n");
                            break;
                        case BackendStatus.IDLE:
                            append_system ("— Idle\n");
                            break;
                        case BackendStatus.ERROR:
                            append_line ("✗ Backend error\n", true);
                            break;
                    }
                    return false;
                });
            });
        }

        private void append_line (string text, bool is_error) {
            trim_if_needed ();
            Gtk.TextIter iter;
            log_buffer.get_end_iter (out iter);
            log_buffer.insert_with_tags (ref iter, text, text.length,
                is_error ? tag_error : null);
            if (auto_scroll) scroll_to_end ();
        }

        private void append_system (string text) {
            trim_if_needed ();
            Gtk.TextIter iter;
            log_buffer.get_end_iter (out iter);
            log_buffer.insert_with_tags (ref iter, text, text.length, tag_system);
            if (auto_scroll) scroll_to_end ();
        }

        private void trim_if_needed () {
            int line_count = log_buffer.get_line_count ();
            if (line_count < max_lines) return;

            Gtk.TextIter start, end;
            log_buffer.get_start_iter (out start);
            log_buffer.get_iter_at_line (out end, line_count - max_lines + 100);
            log_buffer.delete (ref start, ref end);
        }

        private void scroll_to_end () {
            Gtk.TextIter end;
            log_buffer.get_end_iter (out end);
            var mark = log_buffer.create_mark (null, end, false);
            log_view.scroll_mark_onscreen (mark);
            log_buffer.delete_mark (mark);
        }
    }
}

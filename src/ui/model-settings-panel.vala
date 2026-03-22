namespace LLMStudio.UI {

    public class ModelSettingsPanel : Gtk.Box {
        private ModelInfo? current_model = null;

        private Gtk.Label   title_lbl;
        private Gtk.TextView template_editor;
        private Gtk.Button  reset_btn;
        private uint        save_timeout = 0;

        public signal void close_requested ();

        public ModelSettingsPanel () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            width_request = 340;
            build_ui ();
        }

        private void build_ui () {
            // ── Header ──────────────────────────────────────────────────
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            header.margin_start  = 14;
            header.margin_end    = 6;
            header.margin_top    = 10;
            header.margin_bottom = 10;

            title_lbl = new Gtk.Label ("");
            title_lbl.add_css_class ("title-4");
            title_lbl.halign    = Gtk.Align.START;
            title_lbl.hexpand   = true;
            title_lbl.ellipsize = Pango.EllipsizeMode.END;
            header.append (title_lbl);

            var close_btn = new Gtk.Button.from_icon_name ("window-close-symbolic");
            close_btn.add_css_class ("flat");
            close_btn.valign = Gtk.Align.CENTER;
            close_btn.tooltip_text = "Close";
            close_btn.clicked.connect (() => close_requested ());
            header.append (close_btn);

            append (header);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // ── Scrollable content ──────────────────────────────────────
            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand           = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            append (scroll);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_start  = 14;
            content.margin_end    = 14;
            content.margin_top    = 14;
            content.margin_bottom = 14;
            scroll.set_child (content);

            // ── Chat Template section ───────────────────────────────────
            var tmpl_header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var tmpl_lbl = new Gtk.Label ("Chat Template");
            tmpl_lbl.add_css_class ("heading");
            tmpl_lbl.halign  = Gtk.Align.START;
            tmpl_lbl.hexpand = true;
            tmpl_header.append (tmpl_lbl);

            reset_btn = new Gtk.Button.with_label ("Reset");
            reset_btn.add_css_class ("flat");
            reset_btn.tooltip_text = "Reset to model default";
            reset_btn.valign = Gtk.Align.CENTER;
            reset_btn.clicked.connect (on_reset_template);
            tmpl_header.append (reset_btn);
            content.append (tmpl_header);

            var tmpl_desc = new Gtk.Label ("Jinja template used for formatting chat messages. Leave empty to use the model's built-in template.");
            tmpl_desc.add_css_class ("dim-label");
            tmpl_desc.add_css_class ("caption");
            tmpl_desc.halign   = Gtk.Align.START;
            tmpl_desc.wrap     = true;
            tmpl_desc.xalign   = 0;
            content.append (tmpl_desc);

            var frame = new Gtk.Frame (null);
            frame.add_css_class ("card");
            var editor_scroll = new Gtk.ScrolledWindow ();
            editor_scroll.min_content_height = 200;
            editor_scroll.max_content_height = 600;
            template_editor = new Gtk.TextView ();
            template_editor.wrap_mode       = Gtk.WrapMode.WORD_CHAR;
            template_editor.top_margin      = 8;
            template_editor.bottom_margin   = 8;
            template_editor.left_margin     = 10;
            template_editor.right_margin    = 10;
            template_editor.add_css_class ("monospace");
            template_editor.buffer.changed.connect (on_template_changed);
            editor_scroll.set_child (template_editor);
            frame.set_child (editor_scroll);
            content.append (frame);
        }

        public void show_model (ModelInfo model) {
            flush_save ();
            current_model = model;
            title_lbl.label = model.clean_name ().down ();

            // Show custom template if set, otherwise show default from GGUF
            string display = model.params.chat_template;
            if (display == "" && model.default_chat_template != null)
                display = model.default_chat_template;
            template_editor.buffer.text = display;

            reset_btn.sensitive = model.default_chat_template != null
                && model.default_chat_template != "";
        }

        public void clear () {
            flush_save ();
            current_model = null;
            title_lbl.label = "";
            template_editor.buffer.text = "";
        }

        private void on_template_changed () {
            if (current_model == null) return;
            if (save_timeout != 0) GLib.Source.remove (save_timeout);
            save_timeout = GLib.Timeout.add (800, () => {
                do_save ();
                save_timeout = 0;
                return false;
            });
        }

        private void flush_save () {
            if (save_timeout != 0) {
                GLib.Source.remove (save_timeout);
                save_timeout = 0;
                do_save ();
            }
        }

        private void do_save () {
            if (current_model == null) return;
            string text = template_editor.buffer.text.strip ();
            // If user text matches the model default, store empty (= use default)
            if (current_model.default_chat_template != null
                    && text == current_model.default_chat_template.strip ())
                text = "";
            current_model.params.chat_template = text;
            current_model.save_params ();
        }

        private void on_reset_template () {
            if (current_model == null) return;
            template_editor.buffer.text = current_model.default_chat_template ?? "";
        }
    }
}

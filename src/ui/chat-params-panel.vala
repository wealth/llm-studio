namespace LLMStudio.UI {

    public class ChatParamsPanel : Gtk.Box {
        private BackendManager backend_manager;
        private ToolManager    tool_manager;
        private ModelInfo?     current_model = null;

        private Gtk.Stack      content_stack;
        private Gtk.TextView   system_prompt_view;

        // Sliders + value labels
        private Gtk.Scale  temp_scale;
        private Gtk.Label  temp_val;
        private Gtk.Scale  top_p_scale;
        private Gtk.Label  top_p_val;
        private Gtk.Scale  top_k_scale;
        private Gtk.Label  top_k_val;
        private Gtk.Scale  rep_pen_scale;
        private Gtk.Label  rep_pen_val;
        private Gtk.Scale  max_tokens_scale;
        private Gtk.Label  max_tokens_val;

        private bool       updating_ui = false;

        public ChatParamsPanel (BackendManager bm, ToolManager tm) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.backend_manager = bm;
            this.tool_manager    = tm;
            build_ui ();
            backend_manager.model_loaded.connect (on_model_loaded);
            backend_manager.model_unloaded.connect (on_model_unloaded);
        }

        // Returns a vertical two-line row: name+value on top, scale below
        private Gtk.Box make_slider_row (
            string label_text,
            double min, double max, double step,
            int    digits,
            out Gtk.Scale out_scale,
            out Gtk.Label out_val
        ) {
            var row = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

            var name_lbl = new Gtk.Label (label_text);
            name_lbl.halign  = Gtk.Align.START;
            name_lbl.hexpand = true;
            name_lbl.add_css_class ("caption");
            top.append (name_lbl);

            var val_lbl = new Gtk.Label ("");
            val_lbl.halign      = Gtk.Align.END;
            val_lbl.width_chars = 6;
            val_lbl.xalign      = 1;
            val_lbl.add_css_class ("caption");
            val_lbl.add_css_class ("dim-label");
            top.append (val_lbl);

            row.append (top);

            var scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, min, max, step);
            scale.draw_value = false;
            scale.hexpand    = true;
            scale.digits     = digits;
            row.append (scale);

            out_scale = scale;
            out_val   = val_lbl;
            return row;
        }

        // Returns a collapsible section: clickable header + Revealer wrapping content
        private Gtk.Box make_collapsible_section (string title, Gtk.Widget content, bool expanded = true) {
            var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            outer.margin_bottom = 4;

            var header_btn = new Gtk.ToggleButton ();
            header_btn.active  = expanded;
            header_btn.hexpand = true;
            header_btn.add_css_class ("flat");

            var header_inner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            header_inner.margin_top    = 4;
            header_inner.margin_bottom = 4;

            var lbl = new Gtk.Label (title);
            lbl.add_css_class ("heading");
            lbl.halign  = Gtk.Align.START;
            lbl.hexpand = true;
            header_inner.append (lbl);

            var chevron = new Gtk.Image.from_icon_name (
                expanded ? "pan-down-symbolic" : "pan-end-symbolic");
            header_inner.append (chevron);
            header_btn.set_child (header_inner);

            var content_wrap = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content_wrap.margin_top = 6;
            content_wrap.append (content);

            var revealer = new Gtk.Revealer ();
            revealer.reveal_child        = expanded;
            revealer.transition_type     = Gtk.RevealerTransitionType.SLIDE_DOWN;
            revealer.transition_duration = 150;
            revealer.set_child (content_wrap);

            header_btn.toggled.connect (() => {
                revealer.reveal_child = header_btn.active;
                chevron.icon_name = header_btn.active ? "pan-down-symbolic" : "pan-end-symbolic";
            });

            outer.append (header_btn);
            outer.append (revealer);
            return outer;
        }

        private void build_ui () {
            width_request = 260;

            // Header bar
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            header.margin_start  = 16;
            header.margin_end    = 16;
            header.margin_top    = 12;
            header.margin_bottom = 12;
            var title_lbl = new Gtk.Label ("Model Parameters");
            title_lbl.add_css_class ("heading");
            title_lbl.halign  = Gtk.Align.START;
            title_lbl.hexpand = true;
            header.append (title_lbl);
            append (header);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Stack: empty / params
            content_stack = new Gtk.Stack ();
            content_stack.vexpand = true;
            append (content_stack);

            // Empty state
            var empty = new Adw.StatusPage ();
            empty.icon_name   = "preferences-system-symbolic";
            empty.title       = "No Model Loaded";
            empty.description = "Load a model to edit its parameters";
            content_stack.add_named (empty, "empty");

            // Params page
            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.vexpand = true;

            var outer_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            outer_box.margin_start  = 8;
            outer_box.margin_end    = 8;
            outer_box.margin_top    = 4;
            outer_box.margin_bottom = 12;

            // ── System Prompt section ──────────────────────────────────────
            var sys_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            sys_content.margin_start  = 6;
            sys_content.margin_end    = 6;
            sys_content.margin_bottom = 8;

            var sys_frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            sys_frame.add_css_class ("card");

            var sys_scroll = new Gtk.ScrolledWindow ();
            sys_scroll.min_content_height = 80;
            sys_scroll.max_content_height = 140;
            sys_scroll.hscrollbar_policy  = Gtk.PolicyType.NEVER;

            system_prompt_view = new Gtk.TextView ();
            system_prompt_view.wrap_mode     = Gtk.WrapMode.WORD;
            system_prompt_view.top_margin    = 8;
            system_prompt_view.bottom_margin = 8;
            system_prompt_view.left_margin   = 10;
            system_prompt_view.right_margin  = 10;
            system_prompt_view.buffer.changed.connect (() => {
                if (!updating_ui && current_model != null)
                    current_model.params.system_prompt = system_prompt_view.buffer.text;
            });
            sys_scroll.set_child (system_prompt_view);
            sys_frame.append (sys_scroll);
            sys_content.append (sys_frame);

            // ── Sampling section ───────────────────────────────────────────
            var samp_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            samp_content.margin_start  = 6;
            samp_content.margin_end    = 6;
            samp_content.margin_bottom = 8;

            var temp_row = make_slider_row ("Temperature", 0.0, 2.0, 0.01, 2,
                out temp_scale, out temp_val);
            temp_scale.value_changed.connect (() => {
                temp_val.label = "%.2f".printf (temp_scale.get_value ());
                if (!updating_ui && current_model != null)
                    current_model.params.temperature = temp_scale.get_value ();
            });
            samp_content.append (temp_row);

            var top_p_row = make_slider_row ("Top P", 0.0, 1.0, 0.01, 2,
                out top_p_scale, out top_p_val);
            top_p_scale.value_changed.connect (() => {
                top_p_val.label = "%.2f".printf (top_p_scale.get_value ());
                if (!updating_ui && current_model != null)
                    current_model.params.top_p = top_p_scale.get_value ();
            });
            samp_content.append (top_p_row);

            var top_k_row = make_slider_row ("Top K", 0, 200, 1, 0,
                out top_k_scale, out top_k_val);
            top_k_scale.value_changed.connect (() => {
                top_k_val.label = "%.0f".printf (top_k_scale.get_value ());
                if (!updating_ui && current_model != null)
                    current_model.params.top_k = (int) top_k_scale.get_value ();
            });
            samp_content.append (top_k_row);

            var rep_pen_row = make_slider_row ("Repeat Penalty", 1.0, 2.0, 0.01, 2,
                out rep_pen_scale, out rep_pen_val);
            rep_pen_scale.value_changed.connect (() => {
                rep_pen_val.label = "%.2f".printf (rep_pen_scale.get_value ());
                if (!updating_ui && current_model != null)
                    current_model.params.repeat_penalty = rep_pen_scale.get_value ();
            });
            samp_content.append (rep_pen_row);

            // ── Response section ───────────────────────────────────────────
            var resp_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            resp_content.margin_start  = 6;
            resp_content.margin_end    = 6;
            resp_content.margin_bottom = 8;

            var max_tokens_row = make_slider_row ("Max Tokens", 128, 32768, 128, 0,
                out max_tokens_scale, out max_tokens_val);
            max_tokens_scale.value_changed.connect (() => {
                max_tokens_val.label = "%.0f".printf (max_tokens_scale.get_value ());
                if (!updating_ui && current_model != null)
                    current_model.params.max_tokens = (int) max_tokens_scale.get_value ();
            });
            resp_content.append (max_tokens_row);

            // ── Tools section ──────────────────────────────────────────────────
            var tools_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            tools_content.margin_start  = 6;
            tools_content.margin_end    = 6;
            tools_content.margin_bottom = 8;

            var ddg_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            ddg_row.margin_top    = 6;
            ddg_row.margin_bottom = 2;
            var ddg_lbl = new Gtk.Label ("DuckDuckGo Search");
            ddg_lbl.halign  = Gtk.Align.START;
            ddg_lbl.hexpand = true;
            ddg_lbl.add_css_class ("body");
            var ddg_sw = new Gtk.Switch ();
            ddg_sw.valign = Gtk.Align.CENTER;
            ddg_row.append (ddg_lbl);
            ddg_row.append (ddg_sw);
            tools_content.append (ddg_row);

            var visit_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            visit_row.margin_top    = 4;
            visit_row.margin_bottom = 2;
            var visit_lbl = new Gtk.Label ("Visit Website");
            visit_lbl.halign  = Gtk.Align.START;
            visit_lbl.hexpand = true;
            visit_lbl.add_css_class ("body");
            var visit_sw = new Gtk.Switch ();
            visit_sw.valign = Gtk.Align.CENTER;
            visit_row.append (visit_lbl);
            visit_row.append (visit_sw);
            tools_content.append (visit_row);

            tool_manager.bind_property ("duckduckgo-enabled",    ddg_sw,   "active",
                GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);
            tool_manager.bind_property ("visit-website-enabled", visit_sw, "active",
                GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);

            outer_box.append (make_collapsible_section ("Tools", tools_content, true));
            outer_box.append (make_collapsible_section ("System Prompt", sys_content, false));
            outer_box.append (make_collapsible_section ("Sampling", samp_content, false));
            outer_box.append (make_collapsible_section ("Response", resp_content, false));

            scroll.set_child (outer_box);
            content_stack.add_named (scroll, "params");

            content_stack.visible_child_name = "empty";
        }

        private void on_model_loaded (ModelInfo model) {
            updating_ui   = true;
            current_model = null;

            system_prompt_view.buffer.text = model.params.system_prompt;

            temp_scale.set_value (model.params.temperature);
            temp_val.label = "%.2f".printf (model.params.temperature);

            top_p_scale.set_value (model.params.top_p);
            top_p_val.label = "%.2f".printf (model.params.top_p);

            top_k_scale.set_value ((double) model.params.top_k);
            top_k_val.label = "%d".printf (model.params.top_k);

            rep_pen_scale.set_value (model.params.repeat_penalty);
            rep_pen_val.label = "%.2f".printf (model.params.repeat_penalty);

            int mt = model.params.max_tokens > 0 ? model.params.max_tokens : 2048;
            max_tokens_scale.set_value ((double) mt);
            max_tokens_val.label = "%d".printf (mt);

            current_model = model;
            updating_ui   = false;

            content_stack.visible_child_name = "params";
        }

        private void on_model_unloaded () {
            current_model = null;
            content_stack.visible_child_name = "empty";
        }
    }
}

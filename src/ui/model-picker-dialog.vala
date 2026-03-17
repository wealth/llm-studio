namespace LLMStudio.UI {

    private class ModelPickerRow : Gtk.ListBoxRow {
        public ModelInfo model { get; construct; }
        public ModelPickerRow (ModelInfo m) { Object (model: m); }
    }

    public class ModelPickerDialog : Adw.Window {

        private ModelManager   model_manager;
        private BackendManager backend_manager;

        private ModelInfo?   pending_model  = null;
        private ModelParams? pending_params = null;

        private Gtk.Stack       stack;
        private Gtk.ListBox     model_listbox;
        private Gtk.SearchEntry search_entry;

        // Load page - header title
        private Gtk.Label load_title_lbl;

        // Load page - model info banner
        private Gtk.Label load_name_lbl;
        private Gtk.Label load_meta_lbl;

        // Load form rows
        private Adw.SpinRow   ctx_row;
        private Adw.SpinRow   batch_row;
        private Adw.SpinRow   ubatch_row;
        private Gtk.Scale     gpu_layers_scale;
        private Gtk.Label     gpu_layers_val_lbl;
        private int           gpu_layers_max = 200;
        private Adw.SpinRow   threads_row;
        private Adw.SwitchRow flash_attn_row;
        private Adw.SwitchRow mmap_row;
        private Adw.SwitchRow mlock_row;
        private Adw.ComboRow  kv_type_row;
        private Adw.SpinRow   rope_scale_row;
        private Adw.SpinRow   rope_base_row;
        private Adw.SpinRow   temp_row;
        private Adw.SpinRow   top_p_row;
        private Adw.SpinRow   top_k_row;
        private Adw.SpinRow   min_p_row;
        private Adw.SpinRow   rep_penalty_row;
        private Adw.SpinRow   rep_last_n_row;
        private Adw.SpinRow   presence_row;
        private Adw.SpinRow   frequency_row;
        private Adw.SpinRow   max_tokens_row;
        private Adw.SpinRow   seed_row;
        private Gtk.TextView  system_prompt_view;
        private Adw.ExpanderRow sys_expander;

        public signal void load_requested (ModelInfo model, ModelParams params);

        public ModelPickerDialog (ModelManager   model_manager,
                                  BackendManager backend_manager,
                                  Gtk.Window     parent)
        {
            Object (
                transient_for:  parent,
                modal:          true,
                default_width:  640,
                default_height: 720
            );
            this.model_manager   = model_manager;
            this.backend_manager = backend_manager;
            build_ui ();
        }

        private void build_ui () {
            stack = new Gtk.Stack ();
            stack.transition_type     = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack.transition_duration = 180;
            set_content (stack);
            stack.add_named (build_picker_page (), "picker");
            stack.add_named (build_load_page (),   "load");
        }

        // ── Picker page ──────────────────────────────────────────────

        private Gtk.Widget build_picker_page () {
            var tv = new Adw.ToolbarView ();

            var header = new Adw.HeaderBar ();
            var title_lbl = new Gtk.Label ("Select Model");
            title_lbl.add_css_class ("heading");
            header.set_title_widget (title_lbl);

            var cancel_btn = new Gtk.Button.with_label ("Cancel");
            cancel_btn.clicked.connect (close);
            header.pack_start (cancel_btn);
            tv.add_top_bar (header);

            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = "Search models…";
            search_entry.margin_start  = 12;
            search_entry.margin_end    = 12;
            search_entry.margin_top    = 6;
            search_entry.margin_bottom = 6;
            search_entry.search_changed.connect (() => model_listbox.invalidate_filter ());
            tv.add_top_bar (search_entry);

            model_listbox = new Gtk.ListBox ();
            model_listbox.selection_mode = Gtk.SelectionMode.NONE;
            model_listbox.add_css_class ("boxed-list");
            model_listbox.set_filter_func (filter_model_row);
            model_listbox.row_activated.connect (on_model_row_activated);

            populate_model_list ();

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.margin_start  = 12;
            scroll.margin_end    = 12;
            scroll.margin_top    = 4;
            scroll.margin_bottom = 12;
            scroll.set_child (model_listbox);
            tv.set_content (scroll);

            return tv;
        }

        private void populate_model_list () {
            Gtk.Widget? child;
            while ((child = model_listbox.get_row_at_index (0)) != null)
                model_listbox.remove (child);

            var n = model_manager.models.get_n_items ();
            if (n == 0) {
                var lbl = new Gtk.Label ("No models found. Use the Models page to add models.");
                lbl.add_css_class ("dim-label");
                lbl.wrap          = true;
                lbl.margin_top    = 24;
                lbl.margin_bottom = 24;
                lbl.margin_start  = 24;
                lbl.margin_end    = 24;
                var empty_row = new Gtk.ListBoxRow ();
                empty_row.activatable = false;
                empty_row.set_child (lbl);
                model_listbox.append (empty_row);
                return;
            }

            for (uint i = 0; i < n; i++) {
                var m = (ModelInfo) model_manager.models.get_item (i);
                model_listbox.append (make_model_picker_row (m));
            }
        }

        private Gtk.ListBoxRow make_model_picker_row (ModelInfo model) {
            var row = new ModelPickerRow (model);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            box.margin_start  = 12;
            box.margin_end    = 12;
            box.margin_top    = 10;
            box.margin_bottom = 10;

            var name_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            name_box.hexpand = true;

            var pub     = model.publisher ();
            var display = pub != "" ? pub + "/" + model.clean_name ().down ()
                                    : model.clean_name ().down ();
            var name_lbl = new Gtk.Label (display);
            name_lbl.halign    = Gtk.Align.START;
            name_lbl.hexpand   = true;
            name_lbl.ellipsize = Pango.EllipsizeMode.END;
            name_box.append (name_lbl);

            if (model.has_vision) {
                var tag = new Gtk.Label ("Vision");
                tag.add_css_class ("badge"); tag.add_css_class ("badge-vision");
                tag.valign = Gtk.Align.CENTER;
                name_box.append (tag);
            }
            if (model.has_tools) {
                var tag = new Gtk.Label ("Tools");
                tag.add_css_class ("badge"); tag.add_css_class ("badge-tools");
                tag.valign = Gtk.Align.CENTER;
                name_box.append (tag);
            }
            if (model.has_thinking) {
                var tag = new Gtk.Label ("Thinking");
                tag.add_css_class ("badge"); tag.add_css_class ("badge-thinking");
                tag.valign = Gtk.Align.CENTER;
                name_box.append (tag);
            }
            box.append (name_box);

            var q = model.quant_tag ();
            if (q != "") {
                var quant_lbl = new Gtk.Label (q);
                quant_lbl.add_css_class ("badge"); quant_lbl.add_css_class ("quant");
                quant_lbl.valign = Gtk.Align.CENTER;
                box.append (quant_lbl);
            }

            var params_str = model.format_params ();
            if (params_str != "") {
                var params_lbl = new Gtk.Label (params_str);
                params_lbl.add_css_class ("caption");
                params_lbl.add_css_class ("dim-label");
                params_lbl.width_chars = 5;
                params_lbl.halign      = Gtk.Align.END;
                box.append (params_lbl);
            }

            var size_lbl = new Gtk.Label (model.format_size ());
            size_lbl.add_css_class ("caption");
            size_lbl.add_css_class ("dim-label");
            size_lbl.add_css_class ("monospace");
            size_lbl.width_chars = 8;
            size_lbl.halign      = Gtk.Align.END;
            box.append (size_lbl);

            if (backend_manager.loaded_model?.path == model.path) {
                var tag = new Gtk.Label ("Loaded");
                tag.add_css_class ("badge"); tag.add_css_class ("success");
                tag.valign = Gtk.Align.CENTER;
                box.append (tag);
            }

            row.set_child (box);
            return row;
        }

        private bool filter_model_row (Gtk.ListBoxRow row) {
            var query = search_entry.text.strip ().down ();
            if (query == "") return true;
            if (!(row is ModelPickerRow)) return false;
            var m = ((ModelPickerRow) row).model;
            return (m.publisher () + " " + m.name).down ().contains (query);
        }

        private void on_model_row_activated (Gtk.ListBoxRow row) {
            if (!(row is ModelPickerRow)) return;
            show_load_page (((ModelPickerRow) row).model);
        }

        // ── Load page ────────────────────────────────────────────────

        private Gtk.Widget build_load_page () {
            var tv = new Adw.ToolbarView ();

            var header = new Adw.HeaderBar ();
            var back_btn = new Gtk.Button ();
            back_btn.icon_name    = "go-previous-symbolic";
            back_btn.tooltip_text = "Back to model list";
            back_btn.clicked.connect (() => stack.visible_child_name = "picker");
            header.pack_start (back_btn);

            load_title_lbl = new Gtk.Label ("");
            load_title_lbl.add_css_class ("heading");
            header.set_title_widget (load_title_lbl);

            var load_btn = new Gtk.Button.with_label ("Load");
            load_btn.add_css_class ("suggested-action");
            load_btn.clicked.connect (on_load_clicked);
            header.pack_end (load_btn);
            tv.add_top_bar (header);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            tv.set_content (scroll);

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
            content_box.margin_top    = 12;
            content_box.margin_bottom = 24;
            content_box.margin_start  = 18;
            content_box.margin_end    = 18;
            scroll.set_child (content_box);

            // Model info banner
            var model_card = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            model_card.add_css_class ("card");

            var model_icon = new Gtk.Image.from_icon_name ("application-x-executable-symbolic");
            model_icon.pixel_size = 48;
            model_icon.add_css_class ("dim-label");
            model_card.append (model_icon);

            var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            info_box.valign  = Gtk.Align.CENTER;
            info_box.hexpand = true;
            load_name_lbl = new Gtk.Label ("");
            load_name_lbl.add_css_class ("title-3");
            load_name_lbl.halign    = Gtk.Align.START;
            load_name_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            load_meta_lbl = new Gtk.Label ("");
            load_meta_lbl.add_css_class ("dim-label");
            load_meta_lbl.halign = Gtk.Align.START;
            info_box.append (load_name_lbl);
            info_box.append (load_meta_lbl);
            model_card.append (info_box);
            content_box.append (model_card);

            // ---- Context ----
            var ctx_group = new Adw.PreferencesGroup ();
            ctx_group.title = "Context & Batching";
            content_box.append (ctx_group);
            ctx_row    = make_spin_row ("Context Length",       "Maximum context window in tokens",      512, 131072, 4096, 512);
            batch_row  = make_spin_row ("Batch Size",           "Logical batch size for prompt processing", 32, 8192, 512, 64);
            ubatch_row = make_spin_row ("Physical Batch Size",  "Physical batch size (affects VRAM usage)", 32, 4096, 512, 64);
            ctx_group.add (ctx_row);
            ctx_group.add (batch_row);
            ctx_group.add (ubatch_row);

            // ---- Hardware ----
            var hw_group = new Adw.PreferencesGroup ();
            hw_group.title = "Hardware Acceleration";
            content_box.append (hw_group);

            // GPU Layers slider (range updated in show_load_page)
            var gpu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            gpu_box.margin_top    = 10;
            gpu_box.margin_bottom = 8;
            gpu_box.margin_start  = 12;
            gpu_box.margin_end    = 12;

            var gpu_header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var gpu_title_lbl = new Gtk.Label ("GPU Layers");
            gpu_title_lbl.halign  = Gtk.Align.START;
            gpu_title_lbl.hexpand = true;
            gpu_layers_val_lbl = new Gtk.Label ("");
            gpu_layers_val_lbl.add_css_class ("dim-label");
            gpu_header.append (gpu_title_lbl);
            gpu_header.append (gpu_layers_val_lbl);

            var gpu_sub_lbl = new Gtk.Label ("Transformer layers to offload to GPU");
            gpu_sub_lbl.halign = Gtk.Align.START;
            gpu_sub_lbl.add_css_class ("dim-label");
            gpu_sub_lbl.add_css_class ("caption");

            gpu_layers_scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, gpu_layers_max, 1);
            gpu_layers_scale.hexpand    = true;
            gpu_layers_scale.draw_value = false;
            gpu_layers_scale.add_mark (0,              Gtk.PositionType.BOTTOM, "CPU only");
            gpu_layers_scale.add_mark (gpu_layers_max, Gtk.PositionType.BOTTOM, "All");
            gpu_layers_scale.set_value (gpu_layers_max);
            update_gpu_layers_label (gpu_layers_max);
            gpu_layers_scale.value_changed.connect (() =>
                update_gpu_layers_label ((int) gpu_layers_scale.get_value ()));

            gpu_box.append (gpu_header);
            gpu_box.append (gpu_sub_lbl);
            gpu_box.append (gpu_layers_scale);
            var gpu_row = new Adw.PreferencesRow ();
            gpu_row.activatable = false;
            gpu_row.focusable   = false;
            gpu_row.set_child (gpu_box);
            hw_group.add (gpu_row);

            threads_row    = make_spin_row ("CPU Threads",  "Number of CPU threads to use (-1 = auto)",            -1, 256, -1, 1);
            flash_attn_row = make_switch_row ("Flash Attention", "Use flash attention for faster inference",        true);
            mmap_row       = make_switch_row ("Memory Map",      "Use memory-mapped file I/O for model weights",   true);
            mlock_row      = make_switch_row ("Memory Lock",     "Lock model weights in RAM (prevents swapping)",  false);
            hw_group.add (threads_row);
            hw_group.add (flash_attn_row);
            hw_group.add (mmap_row);
            hw_group.add (mlock_row);

            // ---- KV / RoPE ----
            var kv_group = new Adw.PreferencesGroup ();
            kv_group.title = "KV Cache & RoPE";
            content_box.append (kv_group);
            var kv_types = new Gtk.StringList (null);
            kv_types.append ("f16");
            kv_types.append ("q8_0");
            kv_types.append ("q4_0");
            kv_type_row = new Adw.ComboRow ();
            kv_type_row.title    = "KV Cache Type";
            kv_type_row.subtitle = "Data type for key/value cache (q8_0 saves ~50% VRAM)";
            kv_type_row.model    = kv_types;
            kv_group.add (kv_type_row);
            rope_scale_row = make_double_spin_row ("RoPE Frequency Scale",
                "Scale factor for RoPE frequencies (for context extension)", 0.01, 8.0, 1.0, 0.01);
            rope_base_row  = make_spin_row ("RoPE Base Frequency",
                "Base frequency for RoPE (0 = model default)", 0, 1000000, 0, 1000);
            kv_group.add (rope_scale_row);
            kv_group.add (rope_base_row);

            // ---- Sampling ----
            var samp_group = new Adw.PreferencesGroup ();
            samp_group.title = "Sampling Defaults";
            samp_group.description = "Default values for chat. Can be overridden per-request.";
            content_box.append (samp_group);
            temp_row        = make_double_spin_row ("Temperature",        "Controls randomness. Lower = more focused, higher = more creative", 0.0, 2.0, 0.8, 0.01);
            top_p_row       = make_double_spin_row ("Top-P",              "Nucleus sampling probability threshold",                            0.0, 1.0, 0.95, 0.01);
            top_k_row       = make_spin_row        ("Top-K",              "Only sample from the top K tokens (0 = disabled)",                  0, 200, 40, 1);
            min_p_row       = make_double_spin_row ("Min-P",              "Minimum probability relative to the most likely token",             0.0, 1.0, 0.05, 0.01);
            rep_penalty_row = make_double_spin_row ("Repeat Penalty",     "Penalise recently repeated tokens",                                 1.0, 2.0, 1.1, 0.01);
            rep_last_n_row  = make_spin_row        ("Repeat Last N",      "How many recent tokens to check for repeat penalty",                0, 2048, 64, 8);
            presence_row    = make_double_spin_row ("Presence Penalty",   "Penalise tokens that already appear in the output",                 -2.0, 2.0, 0.0, 0.05);
            frequency_row   = make_double_spin_row ("Frequency Penalty",  "Penalise tokens proportionally to how often they appear",           -2.0, 2.0, 0.0, 0.05);
            max_tokens_row  = make_spin_row        ("Max Tokens",         "Maximum tokens to generate (-1 = unlimited)",                       -1, 32768, -1, 128);
            seed_row        = make_spin_row        ("Seed",               "Random seed for reproducible outputs (-1 = random)",                -1, int.MAX, -1, 1);
            samp_group.add (temp_row);
            samp_group.add (top_p_row);
            samp_group.add (top_k_row);
            samp_group.add (min_p_row);
            samp_group.add (rep_penalty_row);
            samp_group.add (rep_last_n_row);
            samp_group.add (presence_row);
            samp_group.add (frequency_row);
            samp_group.add (max_tokens_row);
            samp_group.add (seed_row);

            // ---- System prompt ----
            var sys_group = new Adw.PreferencesGroup ();
            sys_group.title       = "System Prompt";
            sys_group.description = "Default system prompt prepended to every conversation.";
            content_box.append (sys_group);

            var sys_frame = new Gtk.Frame (null);
            sys_frame.add_css_class ("card");
            var sys_scroll = new Gtk.ScrolledWindow ();
            sys_scroll.min_content_height = 100;
            sys_scroll.max_content_height = 200;
            system_prompt_view = new Gtk.TextView ();
            system_prompt_view.wrap_mode     = Gtk.WrapMode.WORD;
            system_prompt_view.top_margin    = 8;
            system_prompt_view.bottom_margin = 8;
            system_prompt_view.left_margin   = 10;
            system_prompt_view.right_margin  = 10;
            sys_scroll.set_child (system_prompt_view);
            sys_frame.set_child (sys_scroll);

            sys_expander = new Adw.ExpanderRow ();
            sys_expander.title = "System Prompt";
            sys_expander.add_row (new Gtk.ListBoxRow () { child = sys_frame, activatable = false });
            sys_group.add (sys_expander);

            return tv;
        }

        private void show_load_page (ModelInfo model) {
            pending_model  = model;
            pending_params = model.params.copy ();

            var pub = model.publisher ();
            load_name_lbl.label  = pub != "" ? pub + "/" + model.clean_name ().down ()
                                             : model.clean_name ().down ();
            load_title_lbl.label = model.clean_name ().down ();

            var meta_parts = new GLib.Array<string> ();
            if (model.format_params () != "") meta_parts.append_val (model.format_params ());
            if (model.quant_tag ()     != "") meta_parts.append_val (model.quant_tag ());
            meta_parts.append_val (model.format.to_string ());
            meta_parts.append_val (model.format_size ());
            string[] parts_arr = {};
            for (uint i = 0; i < meta_parts.length; i++) parts_arr += meta_parts.index (i);
            load_meta_lbl.label = string.joinv ("  ·  ", parts_arr);

            // Update GPU layers slider for this model
            gpu_layers_max = model.block_count > 0 ? model.block_count : 200;
            gpu_layers_scale.set_range (0, gpu_layers_max);
            gpu_layers_scale.clear_marks ();
            gpu_layers_scale.add_mark (0,              Gtk.PositionType.BOTTOM, "CPU only");
            gpu_layers_scale.add_mark (gpu_layers_max, Gtk.PositionType.BOTTOM, "All");
            // Suggested layers based on VRAM
            int64 vram = ModelLoadDialog.probe_vram ();
            if (vram > 0 && gpu_layers_max > 0 && model.size > 0) {
                int64 bpl = model.size / gpu_layers_max;
                if (bpl > 0) {
                    int sug = (int)((int64)(vram * 0.85) / bpl);
                    if (sug > 0 && sug < gpu_layers_max)
                        gpu_layers_scale.add_mark (sug, Gtk.PositionType.BOTTOM, "Suggested");
                }
            }

            var p = pending_params;
            ctx_row.value   = p.context_length;
            batch_row.value = p.batch_size;
            ubatch_row.value = p.ubatch_size;
            int init_gpu = p.gpu_layers < 0 ? gpu_layers_max : p.gpu_layers.clamp (0, gpu_layers_max);
            gpu_layers_scale.set_value (init_gpu);
            update_gpu_layers_label (init_gpu);
            threads_row.value     = p.cpu_threads;
            flash_attn_row.active = p.flash_attention;
            mmap_row.active       = p.mmap;
            mlock_row.active      = p.mlock;

            switch (p.kv_cache_type) {
                case "q8_0": kv_type_row.selected = 1; break;
                case "q4_0": kv_type_row.selected = 2; break;
                default:     kv_type_row.selected = 0; break;
            }
            rope_scale_row.value  = p.rope_freq_scale;
            rope_base_row.value   = p.rope_freq_base;
            temp_row.value        = p.temperature;
            top_p_row.value       = p.top_p;
            top_k_row.value       = p.top_k;
            min_p_row.value       = p.min_p;
            rep_penalty_row.value = p.repeat_penalty;
            rep_last_n_row.value  = p.repeat_last_n;
            presence_row.value    = p.presence_penalty;
            frequency_row.value   = p.frequency_penalty;
            max_tokens_row.value  = p.max_tokens;
            seed_row.value        = p.seed;
            system_prompt_view.buffer.text = p.system_prompt;

            var sp = p.system_prompt;
            sys_expander.subtitle = sp == "" ? "None"
                : sp[0:int.min (50, sp.length)] + (sp.length > 50 ? "…" : "");

            stack.visible_child_name = "load";
        }

        private void on_load_clicked () {
            if (pending_model == null || pending_params == null) return;

            pending_params.context_length    = (int) ctx_row.get_value ();
            pending_params.batch_size        = (int) batch_row.get_value ();
            pending_params.ubatch_size       = (int) ubatch_row.get_value ();
            int gl = (int) gpu_layers_scale.get_value ();
            pending_params.gpu_layers        = (gl >= gpu_layers_max) ? -1 : gl;
            pending_params.cpu_threads       = (int) threads_row.get_value ();
            pending_params.flash_attention   = flash_attn_row.active;
            pending_params.mmap              = mmap_row.active;
            pending_params.mlock             = mlock_row.active;
            pending_params.enable_vision     = pending_model.has_vision;

            switch (kv_type_row.selected) {
                case 1:  pending_params.kv_cache_type = "q8_0"; break;
                case 2:  pending_params.kv_cache_type = "q4_0"; break;
                default: pending_params.kv_cache_type = "f16";  break;
            }
            pending_params.rope_freq_scale   = rope_scale_row.get_value ();
            pending_params.rope_freq_base    = (int) rope_base_row.get_value ();
            pending_params.temperature       = temp_row.get_value ();
            pending_params.top_p             = top_p_row.get_value ();
            pending_params.top_k             = (int) top_k_row.get_value ();
            pending_params.min_p             = min_p_row.get_value ();
            pending_params.repeat_penalty    = rep_penalty_row.get_value ();
            pending_params.repeat_last_n     = (int) rep_last_n_row.get_value ();
            pending_params.presence_penalty  = presence_row.get_value ();
            pending_params.frequency_penalty = frequency_row.get_value ();
            pending_params.max_tokens        = (int) max_tokens_row.get_value ();
            pending_params.seed              = (int) seed_row.get_value ();
            pending_params.system_prompt     = system_prompt_view.buffer.text;

            pending_model.params = pending_params;
            pending_model.save_params ();

            load_requested (pending_model, pending_params);
            close ();
        }

        private void update_gpu_layers_label (int v) {
            if (v == 0)
                gpu_layers_val_lbl.label = "CPU only";
            else if (v >= gpu_layers_max)
                gpu_layers_val_lbl.label = "All %d layers".printf (gpu_layers_max);
            else
                gpu_layers_val_lbl.label = "%d / %d layers".printf (v, gpu_layers_max);
        }

        // ── Form helpers ─────────────────────────────────────────────

        private Adw.SpinRow make_spin_row (string title, string subtitle,
                int min, int max, int val, int step) {
            var adj = new Gtk.Adjustment (val, min, max, step, step * 10, 0);
            var row = new Adw.SpinRow (adj, step, 0);
            row.title    = title;
            row.subtitle = subtitle;
            return row;
        }

        private Adw.SpinRow make_double_spin_row (string title, string subtitle,
                double min, double max, double val, double step) {
            var adj = new Gtk.Adjustment (val, min, max, step, step * 10, 0);
            var row = new Adw.SpinRow (adj, step, 2);
            row.title    = title;
            row.subtitle = subtitle;
            return row;
        }

        private Adw.SwitchRow make_switch_row (string title, string subtitle, bool active) {
            var row = new Adw.SwitchRow ();
            row.title    = title;
            row.subtitle = subtitle;
            row.active   = active;
            return row;
        }
    }
}

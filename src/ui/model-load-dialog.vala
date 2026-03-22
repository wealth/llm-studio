namespace LLMStudio.UI {

    public class ModelLoadDialog : Adw.Window {
        private ModelInfo   model;
        private ModelParams params;

        // Context group
        private Adw.SpinRow ctx_row;
        private Adw.SpinRow batch_row;
        private Adw.SpinRow ubatch_row;

        // Hardware group
        private Gtk.Scale   gpu_layers_scale;
        private Gtk.Label   gpu_layers_val_lbl;
        private Gtk.Label   gpu_est_lbl;
        private Gtk.Label   ram_est_lbl;
        private int         gpu_layers_max;
        private Adw.SpinRow threads_row;
        private Adw.SwitchRow flash_attn_row;
        private Adw.SwitchRow mmap_row;
        private Adw.SwitchRow mlock_row;

        // KV / RoPE group
        private Adw.ComboRow kv_type_row;
        private Adw.SpinRow  rope_scale_row;
        private Adw.SpinRow  rope_base_row;

        // Sampling group
        private Adw.SpinRow  temp_row;
        private Adw.SpinRow  top_p_row;
        private Adw.SpinRow  top_k_row;
        private Adw.SpinRow  min_p_row;
        private Adw.SpinRow  rep_penalty_row;
        private Adw.SpinRow  rep_last_n_row;
        private Adw.SpinRow  presence_row;
        private Adw.SpinRow  frequency_row;
        private Adw.SpinRow  max_tokens_row;
        private Adw.SpinRow  seed_row;

        // System prompt
        private Gtk.TextView system_prompt_view;



        public signal void load_requested (ModelInfo model, ModelParams params);

        public ModelLoadDialog (ModelInfo model, Gtk.Window parent) {
            Object (
                transient_for: parent,
                modal:         true,
                title:         "Load Model",
                default_width: 560,
                default_height: 820
            );
            this.model  = model;
            this.params = model.params.copy ();
            build_ui ();
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            set_content (toolbar_view);

            // Header
            var header = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header);

            var cancel_btn = new Gtk.Button.with_label ("Cancel");
            cancel_btn.clicked.connect (close);
            header.pack_start (cancel_btn);

            var load_btn = new Gtk.Button.with_label ("Load");
            load_btn.add_css_class ("suggested-action");
            load_btn.clicked.connect (on_load_clicked);
            header.pack_end (load_btn);

            // Model info banner
            var model_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            model_box.margin_top    = 12;
            model_box.margin_bottom = 12;
            model_box.margin_start  = 18;
            model_box.margin_end    = 18;
            model_box.add_css_class ("card");

            var model_icon = new Gtk.Image.from_icon_name ("application-x-executable-symbolic");
            model_icon.pixel_size = 48;
            model_icon.add_css_class ("dim-label");
            model_box.append (model_icon);

            var model_info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            model_info_box.valign = Gtk.Align.CENTER;
            var pub = model.publisher ();
            var display = pub != "" ? pub + "/" + model.clean_name ().down () : model.clean_name ().down ();
            var name_lbl = new Gtk.Label (display);
            name_lbl.add_css_class ("title-3");
            name_lbl.halign = Gtk.Align.START;
            name_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            var meta_parts = new GLib.Array<string> ();
            if (model.format_params () != "") meta_parts.append_val (model.format_params ());
            if (model.quant_tag () != "")     meta_parts.append_val (model.quant_tag ());
            meta_parts.append_val (model.format.to_string ());
            meta_parts.append_val (model.format_size ());
            string[] parts_arr = {};
            for (uint i = 0; i < meta_parts.length; i++) parts_arr += meta_parts.index (i);
            var meta_lbl = new Gtk.Label (string.joinv ("  ·  ", parts_arr));
            meta_lbl.add_css_class ("dim-label");
            meta_lbl.halign = Gtk.Align.START;
            var est_tags_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            est_tags_box.margin_top = 4;
            gpu_est_lbl = new Gtk.Label ("");
            gpu_est_lbl.add_css_class ("tag");
            gpu_est_lbl.add_css_class ("tag-gpu");
            gpu_est_lbl.visible = false;
            ram_est_lbl = new Gtk.Label ("");
            ram_est_lbl.add_css_class ("tag");
            ram_est_lbl.add_css_class ("tag-ram");
            ram_est_lbl.visible = false;
            est_tags_box.append (gpu_est_lbl);
            est_tags_box.append (ram_est_lbl);

            model_info_box.append (name_lbl);
            model_info_box.append (meta_lbl);
            model_info_box.append (est_tags_box);
            model_box.append (model_info_box);

            // Scrolled content
            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            toolbar_view.set_content (scroll);

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
            content_box.margin_top    = 6;
            content_box.margin_bottom = 24;
            content_box.margin_start  = 18;
            content_box.margin_end    = 18;
            scroll.set_child (content_box);

            content_box.append (model_box);

            // ---- Context group ----
            var ctx_group = new Adw.PreferencesGroup ();
            ctx_group.title = "Context & Batching";
            content_box.append (ctx_group);

            ctx_row = make_spin_row ("Context Length", "Maximum context window in tokens",
                512, 131072, params.context_length, 512);
            batch_row = make_spin_row ("Batch Size", "Logical batch size for prompt processing",
                32, 8192, params.batch_size, 64);
            ubatch_row = make_spin_row ("Physical Batch Size", "Physical batch size (affects VRAM usage)",
                32, 4096, params.ubatch_size, 64);
            ctx_group.add (ctx_row);
            ctx_group.add (batch_row);
            ctx_group.add (ubatch_row);

            // ---- Hardware group ----
            var hw_group = new Adw.PreferencesGroup ();
            hw_group.title = "Hardware Acceleration";
            content_box.append (hw_group);

            // Probe hardware for slider hints
            int64 vram_bytes = probe_gpu_vram ();
            int64 ram_bytes  = probe_system_ram ();
            gpu_layers_max   = model.block_count > 0 ? model.block_count : 200;

            int suggested_layers = 0;
            if (vram_bytes > 0 && gpu_layers_max > 0 && model.size > 0) {
                int64 bytes_per_layer = model.size / gpu_layers_max;
                if (bytes_per_layer > 0) {
                    suggested_layers = (int) ((int64)(vram_bytes * 0.85) / bytes_per_layer);
                    if (suggested_layers > gpu_layers_max) suggested_layers = gpu_layers_max;
                    if (suggested_layers < 0)             suggested_layers = 0;
                }
            }

            // Hardware info subtitle
            var hw_info_parts = new GLib.Array<string> ();
            if (vram_bytes > 0)
                hw_info_parts.append_val ("GPU: %.1f GB VRAM".printf (vram_bytes / (1024.0 * 1024.0 * 1024.0)));
            if (ram_bytes > 0)
                hw_info_parts.append_val ("RAM: %.0f GB".printf (ram_bytes / (1024.0 * 1024.0 * 1024.0)));
            if (hw_info_parts.length > 0) {
                string[] hw_arr = {};
                for (uint i = 0; i < hw_info_parts.length; i++) hw_arr += hw_info_parts.index (i);
                hw_group.description = string.joinv (" · ", hw_arr);
            }

            // GPU Layers slider
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

            var gpu_sub_lbl = new Gtk.Label (
                model.block_count > 0
                    ? "Transformer layers to offload to GPU (%d total)".printf (model.block_count)
                    : "Transformer layers to offload to GPU");
            gpu_sub_lbl.halign = Gtk.Align.START;
            gpu_sub_lbl.add_css_class ("dim-label");
            gpu_sub_lbl.add_css_class ("caption");

            gpu_layers_scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, gpu_layers_max, 1);
            gpu_layers_scale.hexpand     = true;
            gpu_layers_scale.draw_value  = false;
            gpu_layers_scale.add_mark (0,              Gtk.PositionType.BOTTOM, "CPU only");
            gpu_layers_scale.add_mark (gpu_layers_max, Gtk.PositionType.BOTTOM, "All");
            if (suggested_layers > 0 && suggested_layers < gpu_layers_max)
                gpu_layers_scale.add_mark (suggested_layers, Gtk.PositionType.BOTTOM, "Suggested");

            int init_gpu = params.gpu_layers < 0
                ? gpu_layers_max
                : params.gpu_layers.clamp (0, gpu_layers_max);
            gpu_layers_scale.set_value (init_gpu);
            update_gpu_layers_label (init_gpu);
            gpu_layers_scale.value_changed.connect (() => {
                update_gpu_layers_label ((int) gpu_layers_scale.get_value ());
                update_estimates ();
            });

            gpu_box.append (gpu_header);
            gpu_box.append (gpu_sub_lbl);
            gpu_box.append (gpu_layers_scale);
            var gpu_row = new Adw.PreferencesRow ();
            gpu_row.activatable = false;
            gpu_row.focusable   = false;
            gpu_row.set_child (gpu_box);
            hw_group.add (gpu_row);

            threads_row = make_spin_row ("CPU Threads", "Number of CPU threads to use (-1 = auto)",
                -1, 256, params.cpu_threads, 1);
            flash_attn_row = make_switch_row ("Flash Attention", "Use flash attention for faster inference",
                params.flash_attention);
            mmap_row  = make_switch_row ("Memory Map", "Use memory-mapped file I/O for model weights",
                params.mmap);
            mlock_row = make_switch_row ("Memory Lock", "Lock model weights in RAM (prevents swapping)",
                params.mlock);
            hw_group.add (threads_row);
            hw_group.add (flash_attn_row);
            hw_group.add (mmap_row);
            hw_group.add (mlock_row);

            // ---- KV cache / RoPE group ----
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
            switch (params.kv_cache_type) {
                case "q8_0": kv_type_row.selected = 1; break;
                case "q4_0": kv_type_row.selected = 2; break;
                default:     kv_type_row.selected = 0; break;
            }
            kv_group.add (kv_type_row);
            kv_type_row.notify["selected"].connect (() => update_estimates ());

            rope_scale_row = make_double_spin_row ("RoPE Frequency Scale",
                "Scale factor for RoPE frequencies (for context extension)", 0.01, 8.0, params.rope_freq_scale, 0.01);
            rope_base_row  = make_spin_row ("RoPE Base Frequency",
                "Base frequency for RoPE (0 = model default)", 0, 1000000, params.rope_freq_base, 1000);
            kv_group.add (rope_scale_row);
            kv_group.add (rope_base_row);

            // ---- Sampling group ----
            var samp_group = new Adw.PreferencesGroup ();
            samp_group.title = "Sampling Defaults";
            samp_group.description = "These are default values used in chat. They can be overridden per-request.";
            content_box.append (samp_group);

            temp_row      = make_double_spin_row ("Temperature",
                "Controls randomness. Lower = more focused, higher = more creative",
                0.0, 2.0, params.temperature, 0.01);
            top_p_row     = make_double_spin_row ("Top-P",
                "Nucleus sampling probability threshold",
                0.0, 1.0, params.top_p, 0.01);
            top_k_row     = make_spin_row ("Top-K",
                "Only sample from the top K tokens (0 = disabled)",
                0, 200, params.top_k, 1);
            min_p_row     = make_double_spin_row ("Min-P",
                "Minimum probability relative to the most likely token",
                0.0, 1.0, params.min_p, 0.01);
            rep_penalty_row = make_double_spin_row ("Repeat Penalty",
                "Penalise recently repeated tokens",
                1.0, 2.0, params.repeat_penalty, 0.01);
            rep_last_n_row = make_spin_row ("Repeat Last N",
                "How many recent tokens to check for repeat penalty",
                0, 2048, params.repeat_last_n, 8);
            presence_row  = make_double_spin_row ("Presence Penalty",
                "Penalise tokens that already appear in the output",
                -2.0, 2.0, params.presence_penalty, 0.05);
            frequency_row = make_double_spin_row ("Frequency Penalty",
                "Penalise tokens proportionally to how often they appear",
                -2.0, 2.0, params.frequency_penalty, 0.05);
            max_tokens_row = make_spin_row ("Max Tokens",
                "Maximum tokens to generate (-1 = unlimited)",
                -1, 32768, params.max_tokens, 128);
            seed_row = make_spin_row ("Seed",
                "Random seed for reproducible outputs (-1 = random)",
                -1, int.MAX, params.seed, 1);

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

            // ---- System prompt group ----
            var sys_group = new Adw.PreferencesGroup ();
            sys_group.title = "System Prompt";
            sys_group.description = "Default system prompt prepended to every conversation.";
            content_box.append (sys_group);

            var sys_frame = new Gtk.Frame (null);
            sys_frame.add_css_class ("card");
            var sys_scroll = new Gtk.ScrolledWindow ();
            sys_scroll.min_content_height = 100;
            sys_scroll.max_content_height = 200;
            system_prompt_view = new Gtk.TextView ();
            system_prompt_view.wrap_mode       = Gtk.WrapMode.WORD;
            system_prompt_view.top_margin      = 8;
            system_prompt_view.bottom_margin   = 8;
            system_prompt_view.left_margin     = 10;
            system_prompt_view.right_margin    = 10;
            system_prompt_view.buffer.text     = params.system_prompt;
            sys_scroll.set_child (system_prompt_view);
            sys_frame.set_child (sys_scroll);

            var sys_expander = new Adw.ExpanderRow ();
            sys_expander.title = "System Prompt";
            sys_expander.subtitle = params.system_prompt == "" ? "None" : params.system_prompt[0:int.min (50, params.system_prompt.length)] + "…";
            sys_expander.add_row (new Gtk.ListBoxRow () { child = sys_frame, activatable = false });
            sys_group.add (sys_expander);

            // Wire context length changes to re-estimate and run initial estimate
            ctx_row.notify["value"].connect (() => update_estimates ());
            update_estimates ();
        }

        private Adw.SpinRow make_spin_row (string title, string subtitle, int min, int max, int val, int step) {
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

        private void update_gpu_layers_label (int v) {
            if (v == 0)
                gpu_layers_val_lbl.label = "CPU only";
            else if (v >= gpu_layers_max)
                gpu_layers_val_lbl.label = "All %d layers".printf (gpu_layers_max);
            else
                gpu_layers_val_lbl.label = "%d / %d layers".printf (v, gpu_layers_max);
        }

        private void update_estimates () {
            if (model.size <= 0 || gpu_layers_max <= 0) {
                gpu_est_lbl.visible = false;
                ram_est_lbl.visible = false;
                return;
            }
            int gpu_layers = (int) gpu_layers_scale.get_value ();
            int ctx        = (int) ctx_row.get_value ();

            // Weight bytes per layer
            double bpl = (double) model.size / gpu_layers_max;

            // KV cache bytes per token per layer (fp16 baseline = 4096 B, halved/quartered for q8/q4)
            double kv_bptl = 4096.0;
            switch (kv_type_row.selected) {
                case 1: kv_bptl = 2048.0; break;  // q8_0
                case 2: kv_bptl = 1024.0; break;  // q4_0
            }

            double gpu_bytes = gpu_layers * (bpl + ctx * kv_bptl);
            double ram_bytes = (gpu_layers_max - gpu_layers) * (bpl + ctx * kv_bptl);

            double gb = 1024.0 * 1024.0 * 1024.0;
            gpu_est_lbl.label = "GPU: ~%.1f GB".printf (gpu_bytes / gb);
            ram_est_lbl.label = "RAM: ~%.1f GB".printf (ram_bytes / gb);
            gpu_est_lbl.visible = true;
            ram_est_lbl.visible = true;
        }

        // Returns total VRAM in bytes from the first detected GPU, or 0 if not detected.
        internal static int64 probe_vram () { return probe_gpu_vram (); }
        private static int64 probe_gpu_vram () {
            // AMD: /sys/class/drm/card*/device/mem_info_vram_total
            try {
                var drm = GLib.File.new_for_path ("/sys/class/drm");
                var enumerator = drm.enumerate_children (
                    GLib.FileAttribute.STANDARD_NAME, GLib.FileQueryInfoFlags.NONE);
                GLib.FileInfo? fi;
                while ((fi = enumerator.next_file ()) != null) {
                    string card = fi.get_name ();
                    if (!card.has_prefix ("card")) continue;
                    string vpath = "/sys/class/drm/%s/device/mem_info_vram_total".printf (card);
                    try {
                        string content;
                        GLib.FileUtils.get_contents (vpath, out content);
                        int64 v = int64.parse (content.strip ());
                        if (v > 0) return v;
                    } catch {}
                }
            } catch {}
            // NVIDIA: /proc/driver/nvidia/gpus/*/information
            try {
                var ngpus = GLib.File.new_for_path ("/proc/driver/nvidia/gpus");
                var enumerator = ngpus.enumerate_children (
                    GLib.FileAttribute.STANDARD_NAME, GLib.FileQueryInfoFlags.NONE);
                GLib.FileInfo? fi;
                while ((fi = enumerator.next_file ()) != null) {
                    string ipath = "/proc/driver/nvidia/gpus/%s/information".printf (fi.get_name ());
                    try {
                        string content;
                        GLib.FileUtils.get_contents (ipath, out content);
                        foreach (string line in content.split ("\n")) {
                            if (!line.down ().contains ("video memory:")) continue;
                            string[] tok = line.split (":");
                            if (tok.length < 2) continue;
                            string val_str = tok[1].strip ();
                            if (val_str.has_suffix (" MB")) {
                                int64 mb = int64.parse (val_str[0:val_str.length - 3]);
                                if (mb > 0) return mb * 1024 * 1024;
                            }
                        }
                    } catch {}
                }
            } catch {}
            return 0;
        }

        // Returns total system RAM in bytes from /proc/meminfo, or 0 if not readable.
        private static int64 probe_system_ram () {
            try {
                string content;
                GLib.FileUtils.get_contents ("/proc/meminfo", out content);
                foreach (string line in content.split ("\n")) {
                    if (!line.has_prefix ("MemTotal:")) continue;
                    string[] tok = line.split (":");
                    if (tok.length < 2) continue;
                    string val_str = tok[1].strip ();
                    if (val_str.has_suffix (" kB")) {
                        int64 kb = int64.parse (val_str[0:val_str.length - 3]);
                        if (kb > 0) return kb * 1024;
                    }
                }
            } catch {}
            return 0;
        }

        private void on_load_clicked () {
            // Harvest values
            params.context_length    = (int) ctx_row.get_value ();
            params.batch_size        = (int) batch_row.get_value ();
            params.ubatch_size       = (int) ubatch_row.get_value ();
            int gl = (int) gpu_layers_scale.get_value ();
            params.gpu_layers        = (gl >= gpu_layers_max) ? -1 : gl;
            params.cpu_threads       = (int) threads_row.get_value ();
            params.flash_attention   = flash_attn_row.active;
            params.mmap              = mmap_row.active;
            params.mlock             = mlock_row.active;
            params.enable_vision     = model.has_vision;

            switch (kv_type_row.selected) {
                case 1:  params.kv_cache_type = "q8_0"; break;
                case 2:  params.kv_cache_type = "q4_0"; break;
                default: params.kv_cache_type = "f16";  break;
            }

            params.rope_freq_scale   = rope_scale_row.get_value ();
            params.rope_freq_base    = (int) rope_base_row.get_value ();
            params.temperature       = temp_row.get_value ();
            params.top_p             = top_p_row.get_value ();
            params.top_k             = (int) top_k_row.get_value ();
            params.min_p             = min_p_row.get_value ();
            params.repeat_penalty    = rep_penalty_row.get_value ();
            params.repeat_last_n     = (int) rep_last_n_row.get_value ();
            params.presence_penalty  = presence_row.get_value ();
            params.frequency_penalty = frequency_row.get_value ();
            params.max_tokens        = (int) max_tokens_row.get_value ();
            params.seed              = (int) seed_row.get_value ();
            params.system_prompt     = system_prompt_view.buffer.text;

            model.params = params;
            model.save_params ();

            load_requested (model, params);
            close ();
        }
    }
}

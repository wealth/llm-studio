namespace LLMStudio.UI {

    // ── First-run install dialog ────────────────────────────────────────────

    public class EngineInstallDialog : Adw.Window {
        private EngineManager        engine_manager;
        private EngineRelease        release;
        private GLib.Cancellable     cancel;

        private Adw.StatusPage       status_page;
        private Gtk.ProgressBar      progress_bar;
        private Gtk.Label            progress_lbl;
        private Gtk.Button           action_btn;
        private Gtk.Button           skip_btn;
        private Gtk.ScrolledWindow   log_scroll;
        private Gtk.TextView         log_view;
        private Gtk.Box              log_box;

        private bool installing = false;
        private GpuVariant selected_gpu;

        public signal void engine_ready ();

        public EngineInstallDialog (EngineRelease rel, EngineManager mgr, GpuVariant detected_gpu, Gtk.Window parent) {
            Object (transient_for: parent, modal: true, default_width: 480, default_height: 400);
            this.release        = rel;
            this.engine_manager = mgr;
            this.cancel         = new GLib.Cancellable ();
            this.selected_gpu   = detected_gpu;
            build_ui (detected_gpu);
            connect_signals ();
        }

        private void build_ui (GpuVariant detected_gpu) {
            title = "Engine Setup";

            var toolbar = new Adw.ToolbarView ();
            var header  = new Adw.HeaderBar ();
            header.add_css_class ("flat");
            header.show_end_title_buttons = false;
            toolbar.add_top_bar (header);

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            toolbar.set_content (root);
            set_content (toolbar);

            // Status page (icon + title + description)
            status_page = new Adw.StatusPage ();
            status_page.icon_name   = "folder-download-symbolic";
            status_page.title       = "Install Inference Engine";
            status_page.description =
                "LLM Studio needs <b>llama.cpp</b> to run models.\n" +
                "Release <b>%s</b> will be downloaded and installed automatically.".printf (
                    release.tag);
            status_page.vexpand = true;
            root.append (status_page);

            // GPU variant selector
            var gpu_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            gpu_box.margin_start  = 32;
            gpu_box.margin_end    = 32;
            gpu_box.margin_bottom = 8;
            gpu_box.margin_top    = 0;
            gpu_box.add_css_class ("card");

            var gpu_lbl = new Gtk.Label ("GPU Acceleration");
            gpu_lbl.hexpand       = true;
            gpu_lbl.halign        = Gtk.Align.START;
            gpu_lbl.margin_top    = 10;
            gpu_lbl.margin_bottom = 10;
            gpu_lbl.margin_start  = 12;

            var gpu_variants = new Gtk.StringList (null);
            gpu_variants.append ("CPU only");
            gpu_variants.append ("CUDA (NVIDIA)");
            gpu_variants.append ("ROCm (AMD)");
            gpu_variants.append ("Vulkan");
            var gpu_combo = new Gtk.DropDown (gpu_variants, null);
            gpu_combo.margin_end    = 12;
            gpu_combo.margin_top    = 6;
            gpu_combo.margin_bottom = 6;
            gpu_combo.valign = Gtk.Align.CENTER;
            switch (detected_gpu) {
                case GpuVariant.CUDA:   gpu_combo.selected = 1; break;
                case GpuVariant.ROCM:   gpu_combo.selected = 2; break;
                case GpuVariant.VULKAN: gpu_combo.selected = 3; break;
                default:                gpu_combo.selected = 0; break;
            }
            gpu_combo.notify["selected"].connect (() => {
                switch (gpu_combo.selected) {
                    case 1:  selected_gpu = GpuVariant.CUDA;   break;
                    case 2:  selected_gpu = GpuVariant.ROCM;   break;
                    case 3:  selected_gpu = GpuVariant.VULKAN; break;
                    default: selected_gpu = GpuVariant.NONE;   break;
                }
            });

            gpu_box.append (gpu_lbl);
            gpu_box.append (gpu_combo);
            root.append (gpu_box);

            // Progress area (initially hidden)
            var progress_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            progress_box.margin_start  = 32;
            progress_box.margin_end    = 32;
            progress_box.margin_bottom = 12;

            progress_bar = new Gtk.ProgressBar ();
            progress_bar.visible = false;

            progress_lbl = new Gtk.Label ("");
            progress_lbl.add_css_class ("caption");
            progress_lbl.add_css_class ("dim-label");
            progress_lbl.halign  = Gtk.Align.START;
            progress_lbl.visible = false;

            progress_box.append (progress_bar);
            progress_box.append (progress_lbl);
            root.append (progress_box);

            // Collapsible log view
            log_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            log_box.margin_start  = 16;
            log_box.margin_end    = 16;
            log_box.margin_bottom = 8;
            log_box.visible       = false;

            log_scroll = new Gtk.ScrolledWindow ();
            log_scroll.vexpand         = true;
            log_scroll.height_request  = 120;
            log_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            log_view = new Gtk.TextView ();
            log_view.editable      = false;
            log_view.cursor_visible = false;
            log_view.add_css_class ("monospace");
            log_view.add_css_class ("caption");
            log_view.pixels_below_lines = 0;
            log_scroll.set_child (log_view);
            log_box.append (log_scroll);
            root.append (log_box);

            // Button row
            var btn_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            btn_row.halign        = Gtk.Align.CENTER;
            btn_row.margin_bottom = 24;
            btn_row.margin_top    = 4;

            skip_btn = new Gtk.Button.with_label ("Skip for Now");
            skip_btn.add_css_class ("pill");

            action_btn = new Gtk.Button.with_label ("Install Engine");
            action_btn.add_css_class ("pill");
            action_btn.add_css_class ("suggested-action");

            btn_row.append (skip_btn);
            btn_row.append (action_btn);
            root.append (btn_row);
        }

        private void connect_signals () {
            action_btn.clicked.connect (on_action_clicked);
            skip_btn.clicked.connect (() => close ());

            engine_manager.log_line.connect (on_log_line);
            engine_manager.download_progress.connect (on_download_progress);
        }

        private void on_action_clicked () {
            if (!installing) {
                start_install ();
            } else {
                cancel.cancel ();
                action_btn.sensitive = false;
                action_btn.label     = "Cancelling…";
            }
        }

        private void start_install () {
            installing = true;
            action_btn.label = "Cancel";
            action_btn.remove_css_class ("suggested-action");
            action_btn.add_css_class ("destructive-action");
            skip_btn.sensitive = false;

            status_page.description =
                "Downloading and installing <b>%s</b>…\n\nThis may take a few minutes.".printf (
                    release.asset_name);

            progress_bar.visible  = true;
            progress_lbl.visible  = true;
            log_box.visible       = true;

            do_install_with_gpu_check.begin ();
        }

        private async void do_install_with_gpu_check () {
            // Re-fetch release for the selected GPU variant
            try {
                var new_release = yield engine_manager.check_latest (selected_gpu, cancel);
                if (cancel.is_cancelled ()) { on_install_cancelled (); return; }
                if (new_release == null) {
                    on_install_error ("No matching release found for the selected GPU variant. Try a different option.");
                    return;
                }
                release = new_release;
                status_page.description =
                    "Downloading and installing <b>%s</b>…\n\nThis may take a few minutes.".printf (
                        release.asset_name);
            } catch (Error e) {
                on_install_error ("Failed to fetch release: " + e.message);
                return;
            }
            yield do_install ();
        }

        private async void do_install () {
            try {
                yield engine_manager.install_release (release, cancel);
                on_install_done ();
            } catch (Error e) {
                if (e is IOError.CANCELLED)
                    on_install_cancelled ();
                else
                    on_install_error (e.message);
            }
        }

        private void on_install_done () {
            installing = false;
            status_page.icon_name   = "emblem-ok-symbolic";
            status_page.title       = "Engine Ready";
            status_page.description = "llama.cpp %s has been installed successfully.".printf (
                release.tag);

            progress_bar.fraction = 1.0;
            progress_lbl.label    = "Done";

            action_btn.label     = "Get Started";
            action_btn.remove_css_class ("destructive-action");
            action_btn.add_css_class ("suggested-action");
            action_btn.sensitive = true;
            skip_btn.visible     = false;

            action_btn.clicked.disconnect (on_action_clicked);
            action_btn.clicked.connect (() => {
                engine_ready ();
                close ();
            });
        }

        private void on_install_cancelled () {
            installing = false;
            status_page.icon_name   = "dialog-warning-symbolic";
            status_page.title       = "Installation Cancelled";
            status_page.description = "You can install the engine later from Preferences.";

            progress_bar.visible = false;
            progress_lbl.visible = false;

            action_btn.label     = "Install Engine";
            action_btn.remove_css_class ("destructive-action");
            action_btn.add_css_class ("suggested-action");
            action_btn.sensitive = true;
            skip_btn.sensitive   = true;
            cancel               = new GLib.Cancellable ();
            installing           = false;
        }

        private void on_install_error (string msg) {
            installing = false;
            status_page.icon_name   = "dialog-error-symbolic";
            status_page.title       = "Installation Failed";
            status_page.description = msg;

            action_btn.label     = "Retry";
            action_btn.remove_css_class ("destructive-action");
            action_btn.add_css_class ("suggested-action");
            action_btn.sensitive = true;
            skip_btn.sensitive   = true;
            cancel               = new GLib.Cancellable ();
            installing           = false;
        }

        private void on_log_line (string text) {
            var buf = log_view.buffer;
            Gtk.TextIter iter;
            buf.get_end_iter (out iter);
            buf.insert (ref iter, text + "\n", -1);

            // Auto-scroll
            var mark = buf.get_mark ("insert");
            log_view.scroll_to_mark (mark, 0.0, false, 0.0, 1.0);
        }

        private void on_download_progress (int64 done, int64 total) {
            if (total > 0) {
                double frac = (double) done / (double) total;
                progress_bar.fraction = frac;
                progress_lbl.label    = "%.1f / %.1f MB".printf (
                    done  / 1048576.0,
                    total / 1048576.0);
            } else {
                progress_bar.pulse ();
                progress_lbl.label = "%.1f MB downloaded".printf (done / 1048576.0);
            }
        }
    }

}

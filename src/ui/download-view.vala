namespace LLMStudio.UI {

    public class HubSearchView : Gtk.Box {
        private HuggingFace.HFClient hf_client;
        private ModelManager         model_manager;
        private GLib.Settings        settings;

        private Gtk.SearchEntry      search_entry;
        private Gtk.DropDown         filter_dropdown;
        private Gtk.ListBox          results_list;
        private Adw.StatusPage       empty_state;
        private Gtk.Spinner          search_spinner;
        private Gtk.Stack            content_stack;
        private Gtk.ListBox          downloads_list;
        private GLib.List<HuggingFace.DownloadGroup> active_groups;
        private GLib.Cancellable?    search_cancel;

        private int    active_count  = 0;
        private string history_path;
        private GLib.List<HuggingFace.DownloadRecord> history;

        public signal void active_count_changed (int count);

        public HubSearchView (HuggingFace.HFClient client, ModelManager mgr, GLib.Settings settings) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.hf_client     = client;
            this.model_manager = mgr;
            this.settings      = settings;
            this.active_groups    = new GLib.List<HuggingFace.DownloadGroup> ();
            this.history          = new GLib.List<HuggingFace.DownloadRecord> ();

            var data_dir = GLib.Path.build_filename (
                GLib.Environment.get_user_data_dir (), "llm-studio2");
            GLib.DirUtils.create_with_parents (data_dir, 0755);
            history_path = GLib.Path.build_filename (data_dir, "downloads.json");

            build_ui ();
            load_history ();
        }

        // Downloads panel exposed for embedding in the header popover.
        public Gtk.Widget downloads_widget { get; private set; }

        private void build_ui () {
            // ── Search bar ────────────────────────────────────────────────
            var search_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            search_box.margin_start  = 12;
            search_box.margin_end    = 12;
            search_box.margin_top    = 10;
            search_box.margin_bottom = 10;
            append (search_box);

            search_entry = new Gtk.SearchEntry ();
            search_entry.hexpand    = true;
            search_entry.placeholder_text = "Search HuggingFace models…";
            search_entry.activate.connect (on_search);

            var filter_strings = new Gtk.StringList (null);
            filter_strings.append ("All");
            filter_strings.append ("GGUF");
            filter_strings.append ("MLX");
            filter_types = filter_strings;
            filter_dropdown = new Gtk.DropDown (filter_strings, null);
            filter_dropdown.tooltip_text = "Filter by type";
            filter_dropdown.selected = 1;  // GGUF by default
            filter_dropdown.notify["selected"].connect (() => {
                if (search_entry.text.strip () != "") on_search ();
            });

            search_spinner = new Gtk.Spinner ();
            search_spinner.visible = false;

            var search_btn = new Gtk.Button.from_icon_name ("system-search-symbolic");
            search_btn.add_css_class ("suggested-action");
            search_btn.clicked.connect (on_search);

            search_box.append (search_entry);
            search_box.append (filter_dropdown);
            search_box.append (search_spinner);
            search_box.append (search_btn);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // ── Results ───────────────────────────────────────────────────
            var results_scroll = new Gtk.ScrolledWindow ();
            results_scroll.vexpand = true;
            results_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            append (results_scroll);

            content_stack = new Gtk.Stack ();
            results_scroll.set_child (content_stack);

            empty_state = new Adw.StatusPage ();
            empty_state.icon_name   = "folder-remote-symbolic";
            empty_state.title       = "Search HuggingFace";
            empty_state.description = "Search for GGUF models to download";
            content_stack.add_named (empty_state, "empty");

            results_list = new Gtk.ListBox ();
            results_list.selection_mode = Gtk.SelectionMode.SINGLE;
            results_list.add_css_class ("boxed-list-separate");
            results_list.margin_start  = 8;
            results_list.margin_end    = 8;
            results_list.margin_top    = 4;
            results_list.margin_bottom = 8;
            results_list.row_activated.connect (on_result_activated);
            content_stack.add_named (results_list, "results");

            var loading_state = new Adw.StatusPage ();
            loading_state.icon_name = "content-loading-symbolic";
            loading_state.title     = "Searching…";
            content_stack.add_named (loading_state, "loading");

            // ── Downloads panel (exposed via property) ────────────────────
            var dl_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            dl_panel.width_request  = 380;
            dl_panel.height_request = 460;

            var dl_header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            dl_header_box.margin_start  = 14;
            dl_header_box.margin_end    = 8;
            dl_header_box.margin_top    = 10;
            dl_header_box.margin_bottom = 8;

            var dl_title = new Gtk.Label ("Downloads");
            dl_title.add_css_class ("heading");
            dl_title.halign  = Gtk.Align.START;
            dl_title.hexpand = true;
            dl_header_box.append (dl_title);

            var clear_btn = new Gtk.Button.with_label ("Clear");
            clear_btn.add_css_class ("flat");
            clear_btn.valign       = Gtk.Align.CENTER;
            clear_btn.tooltip_text = "Remove all downloads from list";
            clear_btn.clicked.connect (clear_downloads);
            dl_header_box.append (clear_btn);

            dl_panel.append (dl_header_box);
            dl_panel.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var dl_scroll = new Gtk.ScrolledWindow ();
            dl_scroll.vexpand = true;
            dl_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            dl_panel.append (dl_scroll);

            downloads_list = new Gtk.ListBox ();
            downloads_list.selection_mode = Gtk.SelectionMode.NONE;
            downloads_list.add_css_class ("background");
            downloads_list.set_header_func ((row, before) => {
                if (before != null && row.get_header () == null)
                    row.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            });
            var dl_empty = new Adw.StatusPage ();
            dl_empty.icon_name   = "folder-download-symbolic";
            dl_empty.title       = "No Downloads";
            dl_empty.description = "Download models from search results";
            downloads_list.set_placeholder (dl_empty);
            dl_scroll.set_child (downloads_list);

            downloads_widget = dl_panel;
        }

        private Gtk.StringList? filter_types;

        private void on_search () {
            var query = search_entry.text.strip ();

            search_cancel?.cancel ();
            search_cancel = new GLib.Cancellable ();

            content_stack.visible_child_name = "loading";
            search_spinner.visible  = true;
            search_spinner.spinning = true;

            string? filter_lib = null;
            switch (filter_dropdown.selected) {
                case 1: filter_lib = "gguf"; break;
                case 2: filter_lib = "mlx";  break;
            }

            do_search.begin (query, filter_lib);
        }

        private async void do_search (string query, string? filter_lib) {
            try {
                var results = yield hf_client.search_models (query, filter_lib, 30, 0);

                // Clear results list
                var child = results_list.get_first_child ();
                while (child != null) {
                    var next = child.get_next_sibling ();
                    results_list.remove ((Gtk.Widget) child);
                    child = next;
                }

                foreach (var m in results) {
                    results_list.append (make_result_row (m));
                }

                content_stack.visible_child_name = results.length () == 0 ? "empty" : "results";
                if (results.length () == 0) {
                    empty_state.title       = "No Results";
                    empty_state.description = "Try a different search query";
                }
            } catch (Error e) {
                content_stack.visible_child_name = "empty";
                empty_state.title       = "Search Failed";
                empty_state.description = e.message;
            }

            search_spinner.visible  = false;
            search_spinner.spinning = false;
        }

        private Gtk.ListBoxRow make_result_row (HuggingFace.HFModel model) {
            var row = new Gtk.ListBoxRow ();
            row.set_data<string> ("model-id", model.id);

            var outer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            outer.margin_top    = 10;
            outer.margin_bottom = 10;
            outer.margin_start  = 14;
            outer.margin_end    = 14;

            /* Avatar */
            var avatar = new Gtk.Image.from_icon_name ("avatar-default-symbolic");
            avatar.pixel_size = 32;
            avatar.valign     = Gtk.Align.CENTER;
            outer.append (avatar);
            hf_client.fetch_avatar.begin (model.author, (obj, res) => {
                var texture = hf_client.fetch_avatar.end (res);
                if (texture != null) avatar.set_from_paintable (texture);
            });

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            box.hexpand = true;
            outer.append (box);

            var top_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            var name_lbl = new Gtk.Label (model.model_name);
            name_lbl.add_css_class ("body");
            name_lbl.halign   = Gtk.Align.START;
            name_lbl.hexpand  = true;
            name_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;

            if (model.has_gguf ()) {
                var gguf_badge = new Gtk.Label ("GGUF");
                gguf_badge.add_css_class ("badge");
                gguf_badge.add_css_class ("accent");
                top_row.append (name_lbl);
                top_row.append (gguf_badge);
            } else {
                top_row.append (name_lbl);
            }

            var author_lbl = new Gtk.Label (model.author);
            author_lbl.add_css_class ("caption");
            author_lbl.add_css_class ("dim-label");
            author_lbl.halign = Gtk.Align.START;

            var stats_lbl = new Gtk.Label ("↓ %s  ♥ %lld".printf (
                model.format_downloads (), model.likes));
            stats_lbl.add_css_class ("caption");
            stats_lbl.add_css_class ("dim-label");
            stats_lbl.halign = Gtk.Align.END;
            stats_lbl.hexpand = true;

            var bottom_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            bottom_row.append (author_lbl);
            bottom_row.append (stats_lbl);

            box.append (top_row);
            box.append (bottom_row);
            row.child = outer;

            // Store model object directly
            row.set_data<HuggingFace.HFModel> ("hf-model", model);
            return row;
        }

        private void on_result_activated (Gtk.ListBoxRow row) {
            var model = row.get_data<HuggingFace.HFModel> ("hf-model");
            if (model == null) return;
            fetch_and_show_files.begin (model);
        }

        private async void fetch_and_show_files (HuggingFace.HFModel model) {
            HuggingFace.HFModel full_model = model;
            try {
                full_model = yield hf_client.get_model_info (model.id);
            } catch (Error e) {
                warning ("Could not fetch model info for %s: %s", model.id, e.message);
            }
            show_model_files_dialog (full_model);
        }

        private void show_model_files_dialog (HuggingFace.HFModel model) {
            var dialog = new Adw.Window ();
            dialog.title         = model.model_name;
            dialog.default_width  = 520;
            dialog.default_height = 600;
            dialog.modal          = true;
            dialog.transient_for  = get_root () as Gtk.Window;

            var toolbar_view = new Adw.ToolbarView ();
            dialog.set_content (toolbar_view);

            var header = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header);

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            toolbar_view.set_content (content_box);

            // Model info
            var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            info_box.margin_start  = 18;
            info_box.margin_end    = 18;
            info_box.margin_top    = 14;
            info_box.margin_bottom = 14;

            var model_title = new Gtk.Label (model.id);
            model_title.add_css_class ("title-3");
            model_title.halign = Gtk.Align.START;
            model_title.wrap   = true;

            var title_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            title_row.append (model_title);
            if (model.has_mmproj ()) {
                var vtag = new Gtk.Label ("Vision");
                vtag.add_css_class ("badge");
                vtag.add_css_class ("badge-vision");
                vtag.valign = Gtk.Align.CENTER;
                title_row.append (vtag);
            }
            info_box.append (title_row);

            if (model.description != null && model.description != "") {
                var desc_lbl = new Gtk.Label (model.description[0:int.min(200, model.description.length)]);
                desc_lbl.add_css_class ("body");
                desc_lbl.halign    = Gtk.Align.START;
                desc_lbl.wrap      = true;
                desc_lbl.add_css_class ("dim-label");
                info_box.append (desc_lbl);
            }

            content_box.append (info_box);
            content_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // File list — GGUF only, no mmproj
            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            content_box.append (scroll);

            var file_list = new Gtk.ListBox ();
            file_list.selection_mode = Gtk.SelectionMode.NONE;
            file_list.add_css_class ("background");
            file_list.set_header_func ((row, before) => {
                if (before != null && row.get_header () == null)
                    row.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            });
            scroll.set_child (file_list);

            int file_count = 0;
            var groups = model.get_gguf_file_groups ();
            foreach (var grp in groups) {
                file_count++;

                var row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                row_box.margin_top    = 8;
                row_box.margin_bottom = 8;
                row_box.margin_start  = 14;
                row_box.margin_end    = 10;

                // Quant badge
                if (grp.quant != "") {
                    var qbadge = new Gtk.Label (grp.quant);
                    qbadge.add_css_class ("badge");
                    qbadge.add_css_class ("quant");
                    qbadge.valign      = Gtk.Align.CENTER;
                    qbadge.width_chars = 9;
                    row_box.append (qbadge);
                }

                // Name
                var name_lbl = new Gtk.Label (grp.display_name ());
                name_lbl.halign    = Gtk.Align.START;
                name_lbl.hexpand   = true;
                name_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
                row_box.append (name_lbl);

                // Parts count hint
                if (grp.part_count () > 1) {
                    var parts_lbl = new Gtk.Label ("%d parts".printf (grp.part_count ()));
                    parts_lbl.add_css_class ("caption");
                    parts_lbl.add_css_class ("dim-label");
                    parts_lbl.valign = Gtk.Align.CENTER;
                    row_box.append (parts_lbl);
                }

                // Total size
                var size_lbl = new Gtk.Label (grp.format_size ());
                size_lbl.add_css_class ("caption");
                size_lbl.add_css_class ("dim-label");
                size_lbl.add_css_class ("monospace");
                size_lbl.valign = Gtk.Align.CENTER;
                row_box.append (size_lbl);

                // Download button
                var dl_btn = new Gtk.Button.from_icon_name ("folder-download-symbolic");
                dl_btn.add_css_class ("flat");
                dl_btn.tooltip_text = model.has_mmproj ()
                    ? "Download model + vision projection (mmproj)"
                    : "Download";
                dl_btn.valign = Gtk.Align.CENTER;
                var grp_ref   = grp;
                var model_ref = model;
                dl_btn.clicked.connect (() => {
                    dialog.close ();
                    start_download_group (model_ref, grp_ref, model_ref.get_best_mmproj ());
                });
                row_box.append (dl_btn);

                var frow = new Gtk.ListBoxRow ();
                frow.activatable = false;
                frow.selectable  = false;
                frow.child = row_box;
                file_list.append (frow);
            }

            if (file_count == 0) {
                var empty = new Adw.StatusPage ();
                empty.icon_name   = "folder-open-symbolic";
                empty.title       = "No GGUF files";
                empty.description = "This repository has no downloadable GGUF model files";
                content_box.append (empty);
            }

            dialog.present ();
        }

        // Starts downloading all files in a quant group (multi-part + optional mmproj)
        // and shows a single aggregated row in the downloads panel.
        private void start_download_group (HuggingFace.HFModel model,
                                           HuggingFace.HFModelFileGroup file_grp,
                                           HuggingFace.HFModelFile? mmproj = null) {
            // Use short_id() to avoid doubling the author when modelId contains "author/name".
            var dest_dir = GLib.Path.build_filename (
                model_manager.get_models_dir (), model.author, model.short_id ());

            var group = new HuggingFace.DownloadGroup ();
            group.model_id     = model.id;
            group.model_repo   = model.id;
            group.display_name = file_grp.base_stem;
            group.dest_dir     = dest_dir;
            foreach (var f in file_grp.files) group.filenames.append (f.filename);
            if (mmproj != null) group.filenames.append (mmproj.filename);

            active_groups.append (group);
            add_download_group_row (group);

            launch_group_downloads (group);
        }

        // (Re-)launches downloads for every filename in a group.
        private void launch_group_downloads (HuggingFace.DownloadGroup group) {
            foreach (var fname in group.filenames) {
                string fref = fname;
                hf_client.download_file.begin (group.model_id, fref, group.dest_dir,
                    (obj, res) => {
                        try {
                            var task = hf_client.download_file.end (res);
                            group.add_task (task);
                            upsert_history (group.model_id, task.filename, task.dest_path,
                                            "in_progress", 0, null);
                        } catch (Error e) {
                            show_toast ("Download failed: " + e.message);
                        }
                    }
                );
            }
        }

        // Creates one UI row that aggregates progress for all tasks in the group.
        private void add_download_group_row (HuggingFace.DownloadGroup group) {
            active_count++;
            active_count_changed (active_count);

            // Mark every file as in_progress for resume on next launch.
            foreach (var fname in group.filenames) {
                upsert_history (group.model_id, fname,
                                GLib.Path.build_filename (group.dest_dir, fname),
                                "in_progress", 0, null);
            }

            var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            row_box.margin_top    = 10;
            row_box.margin_bottom = 10;
            row_box.margin_start  = 14;
            row_box.margin_end    = 14;

            // ── Header: name + action button ─────────────────────────────
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            var name_lbl = new Gtk.Label (group.display_name);
            name_lbl.halign    = Gtk.Align.START;
            name_lbl.hexpand   = true;
            name_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            name_lbl.add_css_class ("body");
            header.append (name_lbl);

            var action_btn = new Gtk.Button.from_icon_name ("process-stop-symbolic");
            action_btn.add_css_class ("flat");
            action_btn.add_css_class ("circular");
            action_btn.tooltip_text = "Cancel";
            action_btn.valign       = Gtk.Align.CENTER;
            header.append (action_btn);

            row_box.append (header);

            // ── Repo label ───────────────────────────────────────────────
            var repo_lbl = new Gtk.Label (group.model_repo);
            repo_lbl.halign = Gtk.Align.START;
            repo_lbl.add_css_class ("caption");
            repo_lbl.add_css_class ("dim-label");
            row_box.append (repo_lbl);

            // ── Status stack ─────────────────────────────────────────────
            var status_stack = new Gtk.Stack ();
            status_stack.transition_type     = Gtk.StackTransitionType.CROSSFADE;
            status_stack.transition_duration = 150;

            var progress_bar = new Gtk.ProgressBar ();
            progress_bar.show_text = true;
            progress_bar.text      = "Starting…";
            status_stack.add_named (progress_bar, "running");

            var done_lbl = new Gtk.Label ("");
            done_lbl.halign = Gtk.Align.START;
            done_lbl.add_css_class ("caption");
            done_lbl.add_css_class ("success");
            status_stack.add_named (done_lbl, "done");

            var fail_lbl = new Gtk.Label ("");
            fail_lbl.halign = Gtk.Align.START;
            fail_lbl.wrap   = true;
            fail_lbl.add_css_class ("caption");
            fail_lbl.add_css_class ("error");
            status_stack.add_named (fail_lbl, "failed");

            var cancel_lbl = new Gtk.Label ("Cancelled");
            cancel_lbl.halign = Gtk.Align.START;
            cancel_lbl.add_css_class ("caption");
            cancel_lbl.add_css_class ("dim-label");
            status_stack.add_named (cancel_lbl, "cancelled");

            status_stack.visible_child_name = "running";
            row_box.append (status_stack);

            var row = new Gtk.ListBoxRow ();
            row.activatable = false;
            row.selectable  = false;
            row.child       = row_box;
            downloads_list.append (row);

            // ── Progress updates ─────────────────────────────────────────
            group.progress_changed.connect (() => {
                progress_bar.fraction = group.get_progress ();
                progress_bar.text     = group.format_progress ();
            });

            // ── Terminal state ───────────────────────────────────────────
            group.all_finished.connect (() => {
                active_count--;
                active_count_changed (active_count);

                if (group.is_all_completed ()) {
                    done_lbl.label = "✓ Complete  " + group.format_total_size ();
                    status_stack.visible_child_name = "done";
                    action_btn.visible = false;
                    show_toast ("Downloaded " + group.display_name);
                    foreach (var t in group.tasks)
                        model_manager.add_model_path (t.dest_path);
                    foreach (var t in group.tasks)
                        upsert_history (group.model_id, t.filename, t.dest_path,
                                        "complete", t.total_size, null);

                } else if (group.has_failures ()) {
                    fail_lbl.label = "✗ Failed: " + (group.first_error () ?? "unknown error");
                    status_stack.visible_child_name = "failed";
                    action_btn.icon_name    = "view-refresh-symbolic";
                    action_btn.tooltip_text = "Retry";
                    foreach (var t in group.tasks)
                        upsert_history (group.model_id, t.filename, t.dest_path,
                                        t.failed ? "failed" : (t.cancelled ? "cancelled" : "complete"),
                                        t.total_size, t.error_msg);

                } else {
                    // All cancelled (no failures)
                    status_stack.visible_child_name = "cancelled";
                    action_btn.icon_name    = "view-refresh-symbolic";
                    action_btn.tooltip_text = "Restart";
                    foreach (var fname in group.filenames)
                        upsert_history (group.model_id, fname,
                                        GLib.Path.build_filename (group.dest_dir, fname),
                                        "cancelled", 0, null);
                }
            });

            // ── Action button (Cancel / Retry / Restart) ─────────────────
            action_btn.clicked.connect (() => {
                if (status_stack.visible_child_name == "running") {
                    group.cancel_all ();
                } else {
                    retry_group (group, status_stack, progress_bar, action_btn);
                }
            });
        }

        // Resets a finished group back to running state and re-launches all downloads.
        private void retry_group (HuggingFace.DownloadGroup group,
                                  Gtk.Stack         status_stack,
                                  Gtk.ProgressBar   progress_bar,
                                  Gtk.Button        action_btn) {
            group.cancel_all ();
            group.clear_tasks ();

            progress_bar.fraction = 0.0;
            progress_bar.text     = "Starting…";
            status_stack.visible_child_name = "running";
            action_btn.icon_name    = "process-stop-symbolic";
            action_btn.tooltip_text = "Cancel";
            action_btn.visible      = true;

            active_count++;
            active_count_changed (active_count);

            launch_group_downloads (group);
        }

        /* ── Persistent history ──────────────────────────────────────── */

        /* Insert or update the record matching (model_id, filename). */
        private void upsert_history (string model_id, string filename, string dest_path,
                                     string status, int64 total_size, string? error_msg) {
            var rec = new HuggingFace.DownloadRecord ();
            rec.model_id   = model_id;
            rec.filename   = filename;
            rec.dest_path  = dest_path;
            rec.status     = status;
            rec.total_size = total_size;
            rec.error_msg  = error_msg;

            /* Replace existing entry with same model_id+filename, or append. */
            var updated = new GLib.List<HuggingFace.DownloadRecord> ();
            bool found = false;
            foreach (var existing in history) {
                if (existing.model_id == model_id && existing.filename == filename) {
                    updated.append (rec);
                    found = true;
                } else {
                    updated.append (existing);
                }
            }
            if (!found) updated.append (rec);
            history = (owned) updated;
            save_history ();
        }

        private void save_history () {
            var arr = new Json.Array ();
            foreach (var rec in history) {
                var obj = new Json.Object ();
                obj.set_string_member ("model_id",   rec.model_id);
                obj.set_string_member ("filename",   rec.filename);
                obj.set_string_member ("dest_path",  rec.dest_path);
                obj.set_string_member ("status",     rec.status);
                obj.set_int_member    ("total_size", rec.total_size);
                if (rec.error_msg != null)
                    obj.set_string_member ("error_msg", rec.error_msg);
                var node = new Json.Node (Json.NodeType.OBJECT);
                node.set_object (obj);
                arr.add_element (node);
            }
            var root_node = new Json.Node (Json.NodeType.ARRAY);
            root_node.set_array (arr);
            var gen = new Json.Generator ();
            gen.set_root (root_node);
            try {
                gen.to_file (history_path);
            } catch (Error e) {
                warning ("Could not save download history: %s", e.message);
            }
        }

        private void load_history () {
            if (!GLib.FileUtils.test (history_path, GLib.FileTest.EXISTS)) return;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (history_path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
                root.get_array ().foreach_element ((arr, i, node) => {
                    if (node.get_node_type () != Json.NodeType.OBJECT) return;
                    var obj = node.get_object ();
                    var rec = new HuggingFace.DownloadRecord ();
                    rec.model_id   = obj.has_member ("model_id")   ? obj.get_string_member ("model_id")   : "";
                    rec.filename   = obj.has_member ("filename")   ? obj.get_string_member ("filename")   : "";
                    rec.dest_path  = obj.has_member ("dest_path")  ? obj.get_string_member ("dest_path")  : "";
                    rec.status     = obj.has_member ("status")     ? obj.get_string_member ("status")     : "";
                    rec.total_size = obj.has_member ("total_size") ? obj.get_int_member    ("total_size") : 0;
                    rec.error_msg  = obj.has_member ("error_msg")  ? obj.get_string_member ("error_msg")  : null;
                    history.append (rec);

                    if (rec.status == "in_progress" && rec.dest_path != "") {
                        /* Resume the interrupted download in a single-file group. */
                        var dest_dir = GLib.Path.get_dirname (rec.dest_path);
                        var grp = new HuggingFace.DownloadGroup ();
                        grp.model_id     = rec.model_id;
                        grp.model_repo   = rec.model_id;
                        grp.display_name = rec.filename;
                        grp.dest_dir     = dest_dir;
                        grp.filenames.append (rec.filename);
                        active_groups.append (grp);
                        hf_client.download_file.begin (rec.model_id, rec.filename, dest_dir,
                            (obj2, res) => {
                                try {
                                    var task = hf_client.download_file.end (res);
                                    grp.add_task (task);
                                    add_download_group_row (grp);
                                } catch (Error e) {
                                    warning ("Resume failed for %s: %s", rec.filename, e.message);
                                    upsert_history (rec.model_id, rec.filename, rec.dest_path,
                                                    "failed", rec.total_size, e.message);
                                    active_groups.remove (grp);
                                    add_history_row (rec);
                                }
                            });
                    } else {
                        add_history_row (rec);
                    }
                });
            } catch (Error e) {
                warning ("Could not load download history: %s", e.message);
            }
        }

        private void add_history_row (HuggingFace.DownloadRecord rec) {
            var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            row_box.margin_top    = 10;
            row_box.margin_bottom = 10;
            row_box.margin_start  = 14;
            row_box.margin_end    = 14;

            // Show clean name (strip part suffix; part info not needed in history)
            string hist_name = rec.filename;
            int pnum = ModelInfo.part_number (rec.filename);
            int ptot = ModelInfo.part_total (rec.filename);
            if (pnum > 0 && ptot > 1) {
                string stem = hist_name.has_suffix (".gguf")
                    ? hist_name.substring (0, hist_name.length - 5) : hist_name;
                hist_name = ModelInfo.strip_part_suffix (stem)
                    + ".gguf [%d/%d]".printf (pnum, ptot);
            }
            var name_lbl = new Gtk.Label (hist_name);
            name_lbl.halign    = Gtk.Align.START;
            name_lbl.hexpand   = true;
            name_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            name_lbl.add_css_class ("body");

            var model_lbl = new Gtk.Label (rec.model_id);
            model_lbl.halign = Gtk.Align.START;
            model_lbl.add_css_class ("caption");
            model_lbl.add_css_class ("dim-label");

            string status_text;
            switch (rec.status) {
                case "complete":  status_text = "✓ Complete"; break;
                case "failed":    status_text = "✗ Failed" + (rec.error_msg != null ? ": " + rec.error_msg : ""); break;
                case "cancelled": status_text = "Cancelled"; break;
                default:          status_text = rec.status; break;
            }
            var status_lbl = new Gtk.Label (status_text);
            status_lbl.halign = Gtk.Align.START;
            status_lbl.add_css_class ("caption");
            if (rec.status == "complete")
                status_lbl.add_css_class ("success");
            else if (rec.status == "failed")
                status_lbl.add_css_class ("error");
            else
                status_lbl.add_css_class ("dim-label");

            row_box.append (name_lbl);
            row_box.append (model_lbl);
            row_box.append (status_lbl);

            var row = new Gtk.ListBoxRow ();
            row.activatable = false;
            row.selectable  = false;
            row.child       = row_box;
            downloads_list.append (row);
        }

        private void clear_downloads () {
            /* Cancel all active groups. */
            foreach (var grp in active_groups)
                grp.cancel_all ();
            active_groups = new GLib.List<HuggingFace.DownloadGroup> ();

            /* Clear the UI list. */
            var child = downloads_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                downloads_list.remove ((Gtk.Widget) child);
                child = next;
            }

            /* Clear history. */
            history = new GLib.List<HuggingFace.DownloadRecord> ();
            save_history ();

            active_count = 0;
            active_count_changed (0);
        }

        private void show_toast (string msg) {
            Gtk.Widget? w = this;
            while (w != null) {
                if (w is Adw.ToastOverlay) {
                    ((Adw.ToastOverlay) w).add_toast (new Adw.Toast (msg));
                    return;
                }
                w = w.get_parent ();
            }
        }
    }
}

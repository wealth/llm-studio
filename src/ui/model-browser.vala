namespace LLMStudio.UI {

    public class ModelBrowser : Gtk.Box {
        private ModelManager   model_manager;
        private BackendManager backend_manager;
        private GLib.Settings  settings;

        private Gtk.ListBox      model_list;
        private Adw.StatusPage   empty_state;
        private Gtk.Stack        content_stack;
        private Gtk.SearchEntry  search_entry;
        private Gtk.Label        model_count_lbl;

        private string  filter_text = "";
        private string  sort_mode   = "name";   // "name" | "size"

        /* Column size groups — ensure every row shares the same column widths. */
        private Gtk.SizeGroup sg_arch;
        private Gtk.SizeGroup sg_params;
        private Gtk.SizeGroup sg_publisher;
        private Gtk.SizeGroup sg_quant;
        private Gtk.SizeGroup sg_size;

        public signal void load_model_requested (ModelInfo model);
        public signal void open_hub_requested   ();

        public ModelBrowser (ModelManager mgr, BackendManager backend, GLib.Settings settings) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.model_manager   = mgr;
            this.backend_manager = backend;
            this.settings        = settings;
            build_ui ();
            connect_signals ();
            refresh_list ();
        }

        private void build_ui () {
            sg_arch      = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            sg_params    = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            sg_publisher = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            sg_quant     = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
            sg_size      = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);

            // ── Toolbar ───────────────────────────────────────────────────
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            toolbar.margin_start  = 12;
            toolbar.margin_end    = 12;
            toolbar.margin_top    = 8;
            toolbar.margin_bottom = 8;

            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = "Filter models…";
            search_entry.hexpand = true;
            search_entry.changed.connect (() => {
                filter_text = search_entry.text.down ();
                refresh_list ();
            });
            toolbar.append (search_entry);

            model_count_lbl = new Gtk.Label ("");
            model_count_lbl.add_css_class ("dim-label");
            toolbar.append (model_count_lbl);

            // Sort group
            var sort_name_btn = new Gtk.ToggleButton.with_label ("Name");
            sort_name_btn.add_css_class ("flat");
            sort_name_btn.active = true;
            sort_name_btn.toggled.connect (() => {
                if (sort_name_btn.active) { sort_mode = "name"; refresh_list (); }
            });

            var sort_size_btn = new Gtk.ToggleButton.with_label ("Size");
            sort_size_btn.add_css_class ("flat");
            sort_size_btn.set_group (sort_name_btn);
            sort_size_btn.toggled.connect (() => {
                if (sort_size_btn.active) { sort_mode = "size"; refresh_list (); }
            });

            var sort_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            sort_box.add_css_class ("linked");
            sort_box.append (sort_name_btn);
            sort_box.append (sort_size_btn);
            toolbar.append (sort_box);

            var refresh_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            refresh_btn.tooltip_text = "Scan for models";
            refresh_btn.add_css_class ("flat");
            refresh_btn.clicked.connect (() => model_manager.scan_async.begin ());
            toolbar.append (refresh_btn);

            var add_btn = new Gtk.Button.from_icon_name ("document-open-symbolic");
            add_btn.tooltip_text = "Add model file";
            add_btn.add_css_class ("flat");
            add_btn.clicked.connect (on_add_file);
            toolbar.append (add_btn);

            var hub_btn = new Gtk.Button.with_label ("Browse Hub");
            hub_btn.add_css_class ("pill");
            hub_btn.clicked.connect (() => open_hub_requested ());
            toolbar.append (hub_btn);

            append (toolbar);
            append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // ── Content stack ─────────────────────────────────────────────
            content_stack = new Gtk.Stack ();
            content_stack.vexpand = true;
            append (content_stack);

            // Empty state
            empty_state = new Adw.StatusPage ();
            empty_state.icon_name   = "drive-harddisk-symbolic";
            empty_state.title       = "No Models Found";
            empty_state.description = "Download models from the Hub or add GGUF files.";
            var empty_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            empty_actions.halign = Gtk.Align.CENTER;
            var empty_hub_btn = new Gtk.Button.with_label ("Browse HuggingFace Hub");
            empty_hub_btn.add_css_class ("pill");
            empty_hub_btn.add_css_class ("suggested-action");
            empty_hub_btn.clicked.connect (() => open_hub_requested ());
            var empty_add_btn = new Gtk.Button.with_label ("Add Model File");
            empty_add_btn.add_css_class ("pill");
            empty_add_btn.clicked.connect (on_add_file);
            empty_actions.append (empty_hub_btn);
            empty_actions.append (empty_add_btn);
            empty_state.child = empty_actions;
            content_stack.add_named (empty_state, "empty");

            // Model list
            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand           = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            content_stack.add_named (scroll, "list");

            model_list = new Gtk.ListBox ();
            model_list.selection_mode = Gtk.SelectionMode.NONE;
            model_list.add_css_class  ("background");
            model_list.set_header_func (list_header_func);
            scroll.set_child (model_list);

            model_manager.models.items_changed.connect ((pos, removed, added) => {
                refresh_list ();
                content_stack.visible_child_name =
                    model_manager.models.get_n_items () == 0 ? "empty" : "list";
            });
        }

        private void connect_signals () {
            backend_manager.model_loaded.connect   (m => refresh_list ());
            backend_manager.model_unloaded.connect (refresh_list);
        }

        private void refresh_list () {
            // Collect + filter
            var items = new GLib.Array<ModelInfo> ();
            for (uint i = 0; i < model_manager.models.get_n_items (); i++) {
                var m = (ModelInfo) model_manager.models.get_item (i);
                if (filter_text == "" || m.clean_name ().down ().contains (filter_text)
                        || m.quant_tag ().down ().contains (filter_text)
                        || m.publisher ().down ().contains (filter_text)
                        || (m.family ?? "").down ().contains (filter_text))
                    items.append_val (m);
            }

            // Sort
            if (sort_mode == "size") {
                // Simple insertion sort by size descending
                for (uint i = 1; i < items.length; i++) {
                    var key = items.index (i);
                    int j = (int) i - 1;
                    while (j >= 0 && items.index ((uint) j).size < key.size) {
                        items.data[j + 1] = items.data[j];
                        j--;
                    }
                    items.data[j + 1] = key;
                }
            } else {
                // Sort by display_name ascending
                for (uint i = 1; i < items.length; i++) {
                    var key = items.index (i);
                    int j = (int) i - 1;
                    while (j >= 0 && items.index ((uint) j).display_name ()
                            > key.display_name ()) {
                        items.data[j + 1] = items.data[j];
                        j--;
                    }
                    items.data[j + 1] = key;
                }
            }

            // Clear list
            var child = model_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                model_list.remove ((Gtk.Widget) child);
                child = next;
            }

            uint n = items.length;
            model_count_lbl.label = n == 0 ? "" : "%u model%s".printf (n, n == 1 ? "" : "s");
            content_stack.visible_child_name = (model_manager.models.get_n_items () == 0 || n == 0)
                ? "empty" : "list";

            for (uint i = 0; i < n; i++)
                model_list.append (make_model_row (items.index (i)));
        }

        private void list_header_func (Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
            if (before == null)
                row.set_header (null);
            else if (row.get_header () == null)
                row.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        }

        private Gtk.ListBoxRow make_model_row (ModelInfo model) {
            var row = new Gtk.ListBoxRow ();
            row.selectable  = false;
            row.activatable = false;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            box.margin_top    = 6;
            box.margin_bottom = 6;
            box.margin_start  = 14;
            box.margin_end    = 6;

            // ── Arch badge ────────────────────────────────────────────────
            var arch_lbl = new Gtk.Label (model.family ?? "");
            arch_lbl.add_css_class ("badge");
            arch_lbl.add_css_class ("dim-label");
            arch_lbl.valign    = Gtk.Align.CENTER;
            arch_lbl.halign    = Gtk.Align.START;
            arch_lbl.ellipsize = Pango.EllipsizeMode.END;
            sg_arch.add_widget (arch_lbl);
            box.append (arch_lbl);

            // ── Params ────────────────────────────────────────────────────
            var params_lbl = new Gtk.Label (model.format_params ());
            params_lbl.add_css_class ("caption");
            params_lbl.add_css_class ("dim-label");
            params_lbl.valign = Gtk.Align.CENTER;
            params_lbl.halign = Gtk.Align.END;
            sg_params.add_widget (params_lbl);
            box.append (params_lbl);

            // ── Publisher ─────────────────────────────────────────────────
            var pub_lbl = new Gtk.Label (model.publisher ());
            pub_lbl.add_css_class ("caption");
            pub_lbl.add_css_class ("dim-label");
            pub_lbl.valign    = Gtk.Align.CENTER;
            pub_lbl.halign    = Gtk.Align.START;
            pub_lbl.ellipsize = Pango.EllipsizeMode.END;
            sg_publisher.add_widget (pub_lbl);
            box.append (pub_lbl);

            // ── Name + capability icons (expands) ─────────────────────────
            var name_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            name_box.valign  = Gtk.Align.CENTER;
            name_box.hexpand = true;

            var name_lbl = new Gtk.Label (model.clean_name ().down ());
            name_lbl.halign   = Gtk.Align.START;
            name_lbl.hexpand  = true;
            name_lbl.ellipsize = Pango.EllipsizeMode.END;
            name_box.append (name_lbl);

            if (model.has_vision) {
                var tag = new Gtk.Label ("Vision");
                tag.add_css_class ("badge");
                tag.add_css_class ("badge-vision");
                tag.valign = Gtk.Align.CENTER;
                name_box.append (tag);
            }
            if (model.has_tools) {
                var tag = new Gtk.Label ("Tools");
                tag.add_css_class ("badge");
                tag.add_css_class ("badge-tools");
                tag.valign = Gtk.Align.CENTER;
                name_box.append (tag);
            }
            if (model.has_thinking) {
                var tag = new Gtk.Label ("Thinking");
                tag.add_css_class ("badge");
                tag.add_css_class ("badge-thinking");
                tag.valign = Gtk.Align.CENTER;
                name_box.append (tag);
            }
            box.append (name_box);

            // ── Quant badge ───────────────────────────────────────────────
            var quant = model.quant_tag ();
            var quant_lbl = new Gtk.Label (quant != "" ? quant : "");
            quant_lbl.add_css_class ("badge");
            quant_lbl.add_css_class ("quant");
            quant_lbl.valign  = Gtk.Align.CENTER;
            quant_lbl.visible = quant != "";
            sg_quant.add_widget (quant_lbl);
            box.append (quant_lbl);

            // ── Size ──────────────────────────────────────────────────────
            var size_lbl = new Gtk.Label (model.format_size ());
            size_lbl.add_css_class ("caption");
            size_lbl.add_css_class ("dim-label");
            size_lbl.add_css_class ("monospace");
            size_lbl.halign = Gtk.Align.END;
            size_lbl.valign = Gtk.Align.CENTER;
            sg_size.add_widget (size_lbl);
            box.append (size_lbl);

            // ── Actions ───────────────────────────────────────────────────
            bool is_loaded = backend_manager.loaded_model?.path == model.path;

            var load_btn = new Gtk.Button.from_icon_name (
                is_loaded ? "media-playback-stop-symbolic" : "media-playback-start-symbolic");
            load_btn.add_css_class ("flat");
            load_btn.tooltip_text = is_loaded ? "Unload" : "Load";
            load_btn.valign = Gtk.Align.CENTER;
            load_btn.clicked.connect (() => {
                if (backend_manager.loaded_model?.path == model.path)
                    backend_manager.unload_model.begin ();
                else
                    load_model_requested (model);
            });

            var del_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            del_btn.add_css_class ("flat");
            del_btn.tooltip_text = "Delete model";
            del_btn.valign = Gtk.Align.CENTER;
            del_btn.clicked.connect (() => confirm_delete (model));

            box.append (load_btn);
            box.append (del_btn);

            row.child = box;
            return row;
        }

        private void confirm_delete (ModelInfo model) {
            var dlg = new Adw.AlertDialog (
                "Delete \"%s\"?".printf (model.clean_name ().down ()),
                "The file will be permanently deleted from disk and cannot be recovered."
            );
            dlg.add_response ("cancel", "Cancel");
            dlg.add_response ("delete", "Delete");
            dlg.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dlg.default_response = "cancel";
            dlg.response.connect ((response) => {
                if (response != "delete") return;
                model_manager.remove_model (model);
                int total = ModelInfo.part_total (model.name);
                if (total > 1) {
                    // Multi-part model: delete all parts and sidecar
                    string dir  = GLib.Path.get_dirname (model.path);
                    string stem = ModelInfo.strip_part_suffix (
                        model.name.has_suffix (".gguf")
                            ? model.name.substring (0, model.name.length - 5) : model.name);
                    for (int n = 1; n <= total; n++) {
                        string ppath = GLib.Path.build_filename (
                            dir, "%s-%05d-of-%05d.gguf".printf (stem, n, total));
                        try { GLib.FileUtils.unlink (ppath); } catch {}
                    }
                    var sidecar = model.path + ".llmstudio.json";
                    if (GLib.FileUtils.test (sidecar, GLib.FileTest.EXISTS))
                        try { GLib.FileUtils.unlink (sidecar); } catch {}
                } else {
                    try {
                        GLib.FileUtils.unlink (model.path);
                        var sidecar = model.path + ".llmstudio.json";
                        if (GLib.FileUtils.test (sidecar, GLib.FileTest.EXISTS))
                            GLib.FileUtils.unlink (sidecar);
                    } catch (Error e) {
                        warning ("Could not delete model file %s: %s", model.path, e.message);
                    }
                }
            });
            dlg.present (get_root () as Gtk.Window);
        }

        private void on_add_file () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Open Model File";
            var filter_gguf = new Gtk.FileFilter ();
            filter_gguf.name = "GGUF Models";
            filter_gguf.add_pattern ("*.gguf");
            var filter_all = new Gtk.FileFilter ();
            filter_all.name = "All Files";
            filter_all.add_pattern ("*");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter_gguf);
            filters.append (filter_all);
            dialog.filters = filters;
            dialog.open.begin (get_root () as Gtk.Window, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    model_manager.add_model_path (file.get_path ());
                } catch (Error e) {
                    if (!(e is Gtk.DialogError)) warning ("File dialog: %s", e.message);
                }
            });
        }
    }
}

namespace LLMStudio {

    // Converts a subset of Markdown to Pango markup for Gtk.Label (use_markup=true).
    public class Markdown {

        public static string to_pango (string input) {
            if (input == "") return "";

            var  lines       = input.split ("\n");
            var  out_lines   = new GLib.Array<string> ();
            bool in_code     = false;
            bool in_math     = false;
            var  code_buf    = new StringBuilder ();
            var  math_buf    = new StringBuilder ();
            var  table_rows  = new GLib.Array<string> ();

            for (int i = 0; i < lines.length; i++) {
                unowned string line = lines[i];

                // ── Already inside a fenced code block ───────────────────
                if (in_code) {
                    if (line.has_prefix ("```") || line.has_prefix ("~~~")) {
                        in_code = false;
                        out_lines.append_val ("<tt>" + esc (code_buf.str) + "</tt>");
                    } else {
                        if (code_buf.len > 0) code_buf.append_c ('\n');
                        code_buf.append (line);
                    }
                    continue;
                }

                // ── Already inside a $$ math block ───────────────────────
                if (in_math) {
                    if (line.strip () == "$$") {
                        in_math = false;
                        out_lines.append_val (render_math_block (math_buf.str));
                    } else {
                        if (math_buf.len > 0) math_buf.append_c ('\n');
                        math_buf.append (line);
                    }
                    continue;
                }

                // ── Flush pending table when non-table line arrives ───────
                if (table_rows.length > 0 && !is_table_row (line)) {
                    out_lines.append_val (render_table (table_rows));
                    table_rows.remove_range (0, table_rows.length);
                }

                // ── Fenced code block opener ──────────────────────────────
                if (line.has_prefix ("```") || line.has_prefix ("~~~")) {
                    in_code = true;
                    code_buf.truncate (0);
                    continue;
                }

                // ── Block math $$ ─────────────────────────────────────────
                string stripped = line.strip ();
                if (stripped.has_prefix ("$$")) {
                    if (stripped == "$$") {
                        in_math = true;
                        math_buf.truncate (0);
                    } else if (stripped.has_suffix ("$$") && stripped.length > 4) {
                        // single-line: $$...$$
                        out_lines.append_val (
                            render_math_block (stripped.substring (2, stripped.length - 4)));
                    }
                    continue;
                }

                // ── Table row ────────────────────────────────────────────
                if (is_table_row (line)) {
                    table_rows.append_val (line);
                    continue;
                }

                out_lines.append_val (process_line (line));
            }

            // Flush unclosed blocks
            if (in_code && code_buf.len > 0)
                out_lines.append_val ("<tt>" + esc (code_buf.str) + "</tt>");
            if (in_math && math_buf.len > 0)
                out_lines.append_val (render_math_block (math_buf.str));
            if (table_rows.length > 0)
                out_lines.append_val (render_table (table_rows));

            string[] parts = {};
            for (uint i = 0; i < out_lines.length; i++)
                parts += out_lines.index (i);
            return string.joinv ("\n", parts);
        }

        // ── Math rendering ───────────────────────────────────────────────

        private static string render_math_block (string raw_latex) {
            return "<tt>" + latex_fmt (esc (raw_latex)) + "</tt>";
        }

        // Takes already-HTML-escaped LaTeX and converts it to readable Pango markup.
        // Greek letters, symbols, \frac, subscripts, and superscripts are all handled.
        private static string latex_fmt (string s_in) {
            string s = s_in;
            try {
                GLib.Regex re;

                // ── Greek letters (var-variants first to avoid prefix matching) ──
                s = s.replace ("\\vartheta",  "ϑ").replace ("\\varepsilon", "ε")
                     .replace ("\\varrho",    "ϱ").replace ("\\varsigma",   "ς")
                     .replace ("\\varphi",    "ϕ").replace ("\\varpi",      "ϖ");
                s = s.replace ("\\alpha",   "α").replace ("\\Alpha",   "Α")
                     .replace ("\\beta",    "β").replace ("\\Beta",    "Β")
                     .replace ("\\gamma",   "γ").replace ("\\Gamma",   "Γ")
                     .replace ("\\delta",   "δ").replace ("\\Delta",   "Δ")
                     .replace ("\\epsilon", "ε").replace ("\\Epsilon", "Ε")
                     .replace ("\\zeta",    "ζ").replace ("\\Zeta",    "Ζ")
                     .replace ("\\eta",     "η").replace ("\\Eta",     "Η")
                     .replace ("\\theta",   "θ").replace ("\\Theta",   "Θ")
                     .replace ("\\iota",    "ι").replace ("\\Iota",    "Ι")
                     .replace ("\\kappa",   "κ").replace ("\\Kappa",   "Κ")
                     .replace ("\\lambda",  "λ").replace ("\\Lambda",  "Λ")
                     .replace ("\\mu",      "μ").replace ("\\Mu",      "Μ")
                     .replace ("\\nu",      "ν").replace ("\\Nu",      "Ν")
                     .replace ("\\xi",      "ξ").replace ("\\Xi",      "Ξ")
                     .replace ("\\pi",      "π").replace ("\\Pi",      "Π")
                     .replace ("\\rho",     "ρ").replace ("\\Rho",     "Ρ")
                     .replace ("\\sigma",   "σ").replace ("\\Sigma",   "Σ")
                     .replace ("\\tau",     "τ").replace ("\\Tau",     "Τ")
                     .replace ("\\upsilon", "υ").replace ("\\Upsilon", "Υ")
                     .replace ("\\phi",     "φ").replace ("\\Phi",     "Φ")
                     .replace ("\\chi",     "χ").replace ("\\Chi",     "Χ")
                     .replace ("\\psi",     "ψ").replace ("\\Psi",     "Ψ")
                     .replace ("\\omega",   "ω").replace ("\\Omega",   "Ω");

                // ── Math symbols (longer/specific variants before shorter ones) ──
                s = s.replace ("\\infty",         "∞")   // before \in
                     .replace ("\\notin",         "∉")   // before \in
                     .replace ("\\subseteq",      "⊆")   // before \subset
                     .replace ("\\supseteq",      "⊇")   // before \supset
                     .replace ("\\neq",           "≠")   // before \ne
                     .replace ("\\leq",           "≤")   // before \le
                     .replace ("\\geq",           "≥")   // before \ge
                     .replace ("\\Leftrightarrow","⇔")
                     .replace ("\\leftrightarrow","↔")
                     .replace ("\\Rightarrow",    "⇒")
                     .replace ("\\Leftarrow",     "⇐")
                     .replace ("\\rightarrow",    "→")
                     .replace ("\\leftarrow",     "←")
                     .replace ("\\times",  "×").replace ("\\cdots", "⋯")
                     .replace ("\\cdot",   "·").replace ("\\ldots", "…")
                     .replace ("\\partial","∂").replace ("\\nabla",  "∇")
                     .replace ("\\sqrt",   "√").replace ("\\hbar",   "ℏ")
                     .replace ("\\ell",    "ℓ").replace ("\\to",     "→")
                     .replace ("\\pm",     "±").replace ("\\mp",     "∓")
                     .replace ("\\ne",     "≠").replace ("\\le",     "≤")
                     .replace ("\\ge",     "≥").replace ("\\in",     "∈")
                     .replace ("\\approx", "≈").replace ("\\equiv",  "≡")
                     .replace ("\\propto", "∝").replace ("\\forall", "∀")
                     .replace ("\\exists", "∃").replace ("\\subset", "⊂")
                     .replace ("\\supset", "⊃").replace ("\\cup",    "∪")
                     .replace ("\\cap",    "∩").replace ("\\int",    "∫")
                     .replace ("\\sum",    "∑").replace ("\\prod",   "∏");

                // ── Structural commands ───────────────────────────────────

                // \text{content} → content
                re = new GLib.Regex ("\\\\text\\{([^}]*)\\}");
                s  = re.replace (s, -1, 0, "\\1");

                // \operatorname{name} → name
                re = new GLib.Regex ("\\\\operatorname\\{([^}]*)\\}");
                s  = re.replace (s, -1, 0, "\\1");

                // \sqrt{x} → √(x)
                re = new GLib.Regex ("\\\\sqrt\\{([^{}]*)\\}");
                s  = re.replace (s, -1, 0, "√(\\1)");

                // \frac{a}{b} → (a/b) — repeated for nesting
                re = new GLib.Regex ("\\\\frac\\{([^{}]*)\\}\\{([^{}]*)\\}");
                for (int iter = 0; iter < 6; iter++) {
                    string prev = s;
                    s = re.replace (s, -1, 0, "(\\1/\\2)");
                    if (s == prev) break;
                }

                // ── Subscripts and superscripts ───────────────────────────

                // _{content} → <sub>content</sub>
                re = new GLib.Regex ("_\\{([^}]*)\\}");
                s  = re.replace (s, -1, 0, "<sub>\\1</sub>");

                // _x (single ASCII char)
                re = new GLib.Regex ("_([0-9a-zA-Z])");
                s  = re.replace (s, -1, 0, "<sub>\\1</sub>");

                // ^{content} → <sup>content</sup>
                re = new GLib.Regex ("\\^\\{([^}]*)\\}");
                s  = re.replace (s, -1, 0, "<sup>\\1</sup>");

                // ^x (single char: digit, letter, or sign)
                re = new GLib.Regex ("\\^([0-9a-zA-Z+\\-])");
                s  = re.replace (s, -1, 0, "<sup>\\1</sup>");

                // ── Clean up ──────────────────────────────────────────────

                // Remove remaining braces
                s = s.replace ("{", "").replace ("}", "");

                // LaTeX spacing commands
                s = s.replace ("\\,", "\u2009")
                     .replace ("\\;", " ")
                     .replace ("\\:", " ")
                     .replace ("\\ ", " ")
                     .replace ("\\!", "");

                // Any remaining unknown \command → strip
                re = new GLib.Regex ("\\\\[a-zA-Z]+");
                s  = re.replace (s, -1, 0, "");

            } catch (GLib.RegexError e) { /* leave as-is */ }
            return s;
        }

        // ── Table helpers ────────────────────────────────────────────────

        private static bool is_table_row (string line) {
            return line.strip ().has_prefix ("|");
        }

        private static bool is_table_separator (string line) {
            if (!line.contains ("|") || !line.contains ("-")) return false;
            for (int i = 0; i < line.length; i++) {
                char c = line[i];
                if (c != '|' && c != '-' && c != ':' && c != ' ' && c != '\t') return false;
            }
            return true;
        }

        private static string[] parse_table_row (string line) {
            string s = line.strip ();
            if (s.has_prefix ("|")) s = s.substring (1);
            if (s.has_suffix ("|")) s = s.substring (0, s.length - 1);
            var parts = s.split ("|");
            string[] result = {};
            foreach (var p in parts)
                result += p.strip ();
            return result;
        }

        // Returns the display character count of a Pango markup string by
        // stripping tags and unescaping HTML entities.
        private static int markup_visual_len (string markup) {
            try {
                var re = new GLib.Regex ("<[^>]+>");
                string plain = re.replace (markup, -1, 0, "");
                plain = plain.replace ("&amp;", "&")
                             .replace ("&lt;",  "<")
                             .replace ("&gt;",  ">");
                return (int) plain.char_count ();
            } catch {
                return (int) markup.char_count ();
            }
        }

        private static string render_table (GLib.Array<string> rows) {
            if (rows.length == 0) return "";

            int n_rows = (int) rows.length;

            // First pass: find separator row and column count
            int sep_row  = -1;
            int num_cols = 0;
            for (int i = 0; i < n_rows; i++) {
                if (is_table_separator (rows.index (i))) {
                    sep_row = i;
                } else {
                    var cells = parse_table_row (rows.index (i));
                    if (cells.length > num_cols) num_cols = cells.length;
                }
            }
            if (num_cols == 0) return "";

            // Second pass: format all cells and compute per-column visual widths.
            // Store formatted cells in a flat array [row * num_cols + col].
            var fmt_data  = new string[n_rows * num_cols];
            var vlen_data = new int[n_rows * num_cols];
            int[] widths  = new int[num_cols];

            for (int i = 0; i < n_rows; i++) {
                if (i == sep_row) continue;
                var cells = parse_table_row (rows.index (i));
                for (int j = 0; j < num_cols; j++) {
                    string raw = j < cells.length ? cells[j] : "";
                    string fmt = inline_fmt (raw);
                    int    vl  = markup_visual_len (fmt);
                    fmt_data[i * num_cols + j]  = fmt;
                    vlen_data[i * num_cols + j] = vl;
                    if (vl > widths[j]) widths[j] = vl;
                }
            }

            // Third pass: render rows with correct padding
            var  rendered    = new GLib.Array<string> ();
            bool header_done = false;

            for (int i = 0; i < n_rows; i++) {
                if (i == sep_row) continue;

                bool is_hdr = sep_row > 0 && i < sep_row;
                var  sb     = new StringBuilder ("<tt>");

                for (int j = 0; j < num_cols; j++) {
                    if (j > 0) sb.append (" │ ");
                    string cell = fmt_data[i * num_cols + j] ?? "";
                    int    vl   = vlen_data[i * num_cols + j];
                    int    pad  = widths[j] - vl;

                    if (is_hdr) {
                        sb.append ("<b>"); sb.append (cell); sb.append ("</b>");
                    } else {
                        sb.append (cell);
                    }
                    for (int k = 0; k < pad; k++) sb.append_c (' ');
                }
                sb.append ("</tt>");
                rendered.append_val (sb.str);

                // Separator line right after the header row
                if (is_hdr && !header_done) {
                    header_done = true;
                    var sep_sb = new StringBuilder ("<tt><span alpha=\"50%\">");
                    for (int j = 0; j < num_cols; j++) {
                        if (j > 0) sep_sb.append ("─┼─");
                        for (int k = 0; k < widths[j]; k++) sep_sb.append ("─");
                    }
                    sep_sb.append ("</span></tt>");
                    rendered.append_val (sep_sb.str);
                }
            }

            string[] parts = {};
            for (uint i = 0; i < rendered.length; i++)
                parts += rendered.index (i);
            return string.joinv ("\n", parts);
        }

        // ── Line-level processing ────────────────────────────────────────

        private static string process_line (string line) {
            // ATX headings
            if (line.has_prefix ("### "))
                return "<b>" + inline_fmt (line.substring (4)) + "</b>";
            if (line.has_prefix ("## "))
                return "<span size=\"large\" weight=\"bold\">" +
                       inline_fmt (line.substring (3)) + "</span>";
            if (line.has_prefix ("# "))
                return "<span size=\"x-large\" weight=\"bold\">" +
                       inline_fmt (line.substring (2)) + "</span>";

            // Horizontal rule
            if (line == "---" || line == "***" || line == "___" || line == "- - -")
                return "<span alpha=\"50%\">────────────────────────────────</span>";

            // Blockquote
            if (line.has_prefix ("> "))
                return "<span alpha=\"70%\">│ " + inline_fmt (line.substring (2)) + "</span>";

            // Unordered list
            if (line.has_prefix ("- ") || line.has_prefix ("* ") || line.has_prefix ("+ "))
                return "  •  " + inline_fmt (line.substring (2));

            // Ordered list  (1. text, 2. text …)
            int k = 0;
            while (k < line.length && line.get_char (k).isdigit ()) k++;
            if (k > 0 && k + 1 < line.length
                    && line.get_char (k) == '.' && line.get_char (k + 1) == ' ')
                return "  •  " + inline_fmt (line.substring (k + 2));

            return inline_fmt (line);
        }

        // ── Inline formatting ─────────────────────────────────────────────

        private static string inline_fmt (string text) {
            string s = esc (text);
            try {
                GLib.Regex re;

                // Inline code first — protect its content from further passes
                re = new GLib.Regex ("`([^`\n]+)`");
                s  = re.replace (s, -1, 0, "<tt>\\1</tt>");

                // Inline math \(...\) — wrap content with latex_fmt
                re = new GLib.Regex ("\\\\\\((.+?)\\\\\\)");
                s  = re.replace_eval (s, -1, 0, 0, (m, r) => {
                    r.append ("<tt>");
                    r.append (latex_fmt (m.fetch (1) ?? ""));
                    r.append ("</tt>");
                    return false;
                });

                // Inline math \[...\]
                re = new GLib.Regex ("\\\\\\[(.+?)\\\\\\]");
                s  = re.replace_eval (s, -1, 0, 0, (m, r) => {
                    r.append ("<tt>");
                    r.append (latex_fmt (m.fetch (1) ?? ""));
                    r.append ("</tt>");
                    return false;
                });

                // Inline math $...$ — only when content has a LaTeX char (\^_{)
                // to avoid matching prices like $100
                re = new GLib.Regex ("\\$(?!\\$)([^\\$\\n]*[\\\\^_{][^\\$\\n]*)\\$(?!\\$)");
                s  = re.replace_eval (s, -1, 0, 0, (m, r) => {
                    r.append ("<tt>");
                    r.append (latex_fmt (m.fetch (1) ?? ""));
                    r.append ("</tt>");
                    return false;
                });

                // Bold + italic: ***…***
                re = new GLib.Regex ("\\*{3}(.+?)\\*{3}");
                s  = re.replace (s, -1, 0, "<b><i>\\1</i></b>");

                // Bold: **…** or __…__
                re = new GLib.Regex ("\\*{2}(.+?)\\*{2}");
                s  = re.replace (s, -1, 0, "<b>\\1</b>");
                re = new GLib.Regex ("_{2}(.+?)_{2}");
                s  = re.replace (s, -1, 0, "<b>\\1</b>");

                // Italic: *…*  (not inside words)
                re = new GLib.Regex ("\\*([^*\n]+)\\*");
                s  = re.replace (s, -1, 0, "<i>\\1</i>");

                // Italic: _…_  (word-boundary guarded)
                re = new GLib.Regex ("(?<!\\w)_([^_\n]+)_(?!\\w)");
                s  = re.replace (s, -1, 0, "<i>\\1</i>");

            } catch (GLib.RegexError e) { /* leave text as-is */ }
            return s;
        }

        private static string esc (string s) {
            return s.replace ("&", "&amp;")
                    .replace ("<", "&lt;")
                    .replace (">", "&gt;");
        }
    }
}

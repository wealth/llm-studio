namespace LLMStudio {

    /* Vala binding to our isolated C cmark wrapper. */
    [CCode (cname = "llm_cmark_to_html", cheader_filename = "utils/cmark-glue.h")]
    extern string llm_cmark_to_html (string markdown);

    public class HtmlRenderer {

        /* Base URI for WebKit load_html() — makes KaTeX JS/CSS/fonts resolvable
           via relative paths from the libjs-katex system package.             */
        public const string BASE_URI = "file:///usr/share/javascript/katex/";

        /* Render a Markdown string to an HTML fragment via libcmark.  */
        public static string render_markdown (string md) {
            if (md == "") return "";
            return llm_cmark_to_html (md);
        }

        /* Escape a string for safe embedding as a JavaScript double-quoted
           string literal.  Also escapes < > to avoid XSS via innerHTML.
           Uses a StringBuilder loop to avoid GLib.Regex (which throws on
           invalid UTF-8, possible during incremental streaming).          */
        public static string js_str (string s) {
            var sb = new StringBuilder.sized (s.length + 16);
            unowned uint8[] bytes = s.data;
            for (int i = 0; i < bytes.length; i++) {
                uint8 c = bytes[i];
                switch (c) {
                    case '\\': sb.append ("\\\\"); break;
                    case '"':  sb.append ("\\\""); break;
                    case '\n': sb.append ("\\n");  break;
                    case '\r': sb.append ("\\r");  break;
                    case '\t': sb.append ("\\t");  break;
                    case '<':  sb.append ("\\x3c"); break;
                    case '>':  sb.append ("\\x3e"); break;
                    default:   sb.append_c ((char) c); break;
                }
            }
            return sb.str;
        }

        /* Escape plain text for safe embedding in HTML markup.  */
        public static string html_esc (string s) {
            var sb = new StringBuilder.sized (s.length + 16);
            unowned uint8[] bytes = s.data;
            for (int i = 0; i < bytes.length; i++) {
                uint8 c = bytes[i];
                switch (c) {
                    case '&': sb.append ("&amp;");  break;
                    case '<': sb.append ("&lt;");   break;
                    case '>': sb.append ("&gt;");   break;
                    case '"': sb.append ("&quot;"); break;
                    default:  sb.append_c ((char) c); break;
                }
            }
            return sb.str;
        }

        /* Return the complete initial HTML page (empty conversation).  */
        public static string get_page_html () {
            return
                "<!DOCTYPE html>\n" +
                "<html><head><meta charset=\"utf-8\">" +
                "<meta name=\"color-scheme\" content=\"light dark\">\n" +
                "<link rel=\"stylesheet\" href=\"katex.min.css\">\n" +
                "<script src=\"katex.min.js\"></script>\n" +
                "<script src=\"contrib/auto-render.js\"></script>\n" +
                "<style>" + CSS + "</style>\n" +
                "</head><body><div id=\"chat\"></div></body></html>";
        }

        /* Build the full HTML page for an entire conversation (used by
           load_session to load all messages at once).                    */
        public static string get_session_html (GLib.List<ChatMessage> messages,
                                               string model_name)
        {
            var sb = new StringBuilder ();
            sb.append (
                "<!DOCTYPE html>\n" +
                "<html><head><meta charset=\"utf-8\">" +
                "<meta name=\"color-scheme\" content=\"light dark\">\n" +
                "<link rel=\"stylesheet\" href=\"katex.min.css\">\n" +
                "<script src=\"katex.min.js\"></script>\n" +
                "<script src=\"contrib/auto-render.js\"></script>\n" +
                "<style>" + CSS + "</style>\n" +
                "</head><body><div id=\"chat\">\n");

            int id = 0;
            foreach (var msg in messages) {
                if (msg.role == "user") {
                    sb.append (user_html (id, msg.content, msg.attachments));
                } else if (msg.role == "assistant") {
                    string name = msg.model_name != "" ? msg.model_name : model_name;
                    sb.append (assistant_html (id, msg, name));
                    id++;
                }
            }

            sb.append ("\n</div><script>llmRenderAll();</script></body></html>");
            return sb.str;
        }

        /* ── Private HTML builders ───────────────────────────────────── */

        private static string user_html (int idx, string text,
                                         GLib.List<ChatAttachment>? attachments = null)
        {
            var sb = new StringBuilder ();
            sb.append ("<div class=\"user-row\" id=\"u-");
            sb.append (idx.to_string ());
            sb.append ("\"><div class=\"user-col\">");

            if (attachments != null) {
                foreach (var att in attachments) {
                    if (att.is_image ()) {
                        sb.append ("<img class=\"att-img\" src=\"");
                        sb.append (html_esc (att.to_data_uri ()));
                        sb.append ("\" alt=\"");
                        sb.append (html_esc (att.filename));
                        sb.append ("\">");
                    } else {
                        sb.append ("<div class=\"att-chip\">&#x1F4C4; ");
                        sb.append (html_esc (att.filename));
                        sb.append ("</div>");
                    }
                }
            }

            if (text != "") {
                sb.append ("<div class=\"user-bubble\" data-raw=\"");
                sb.append (html_esc (text));
                sb.append ("\">");
                sb.append (render_markdown (text));
                sb.append ("</div>");
            }

            sb.append ("<div class=\"user-actions\">");
            sb.append ("<button onclick=\"llmCopyUser(%d)\">Copy</button>".printf (idx));
            sb.append ("<button onclick=\"llmDeleteExchange(%d)\">Delete</button>".printf (idx));
            sb.append ("</div>");

            sb.append ("</div></div>\n");
            return sb.str;
        }

        private static string assistant_html (int id,
                                              unowned ChatMessage msg,
                                              string model_name)
        {
            string sid = "m%d".printf (id);
            var sb = new StringBuilder ();
            sb.append ("<div class=\"asst-row\" id=\"asst-" + sid + "\"");

            /* data-raw on the outer row for llmCopyRow() */
            string raw_resp = msg.content;
            if (msg.rounds.length () > 0) {
                unowned ChatRound last = msg.rounds.last ().data;
                raw_resp = last.response;
            } else if (msg.content.has_prefix ("<think>")) {
                /* extract response portion for copy */
                int end = msg.content.index_of ("</think>");
                if (end >= 0)
                    raw_resp = msg.content.substring (end + 8).strip ();
            }
            sb.append (" data-raw=\"");
            sb.append (html_esc (raw_resp));
            sb.append ("\">");

            sb.append ("<div class=\"asst-name\">" + html_esc (model_name) + "</div>");
            sb.append ("<div class=\"rounds\" id=\"asst-" + sid + "-rounds\">");

            if (msg.rounds.length () > 0) {
                int r = 1;
                foreach (unowned var round in msg.rounds) {
                    sb.append (round_html (sid, r, round));
                    r++;
                }
            } else {
                /* Legacy / simple message — parse think from content */
                sb.append (round_html_from_content (sid, 1, msg.content));
            }

            sb.append ("</div>");

            sb.append ("<div class=\"asst-stats\" id=\"asst-" + sid + "-stats\">");
            sb.append (html_esc (msg.stats_text));
            sb.append ("</div>");

            sb.append ("<div class=\"asst-actions\" id=\"asst-" + sid + "-acts\">");
            sb.append ("<button onclick=\"llmCopyRow('" + sid + "')\">Copy</button>");
            sb.append ("<button onclick=\"llmDeleteExchange(%d)\">Delete</button>".printf (id));
            sb.append ("</div>");

            sb.append ("</div>\n");
            return sb.str;
        }

        /* Render one round from a ChatRound (used for persisted multi-round messages). */
        private static string round_html (string sid, int r, unowned ChatRound round) {
            string rid        = sid + "-r%d".printf (r);
            string think_html = round.think    != "" ? render_markdown (round.think)    : "";
            string resp_html  = round.response != "" ? render_markdown (round.response) : "";
            var sb = new StringBuilder ();

            if (think_html != "") {
                sb.append ("<details class=\"think\" id=\"asst-" + rid + "-think\" open>");
            } else {
                sb.append ("<details class=\"think\" id=\"asst-" + rid + "-think\" hidden>");
            }
            sb.append ("<summary>Thinking\u2026</summary>");
            sb.append ("<div class=\"tk\" id=\"asst-" + rid + "-think-body\">");
            sb.append (think_html);
            sb.append ("</div></details>");

            sb.append ("<div class=\"tool-calls\" id=\"asst-" + rid + "-tools\">");
            foreach (unowned var tc in round.tool_calls) {
                sb.append ("<details class=\"tool-call\" open><summary>");
                sb.append (html_esc (tc.display));
                sb.append ("</summary><div class=\"tool-result\">");
                sb.append (html_esc (tc.result));
                sb.append ("</div></details>");
            }
            sb.append ("</div>");

            sb.append ("<div class=\"asst-content\" id=\"asst-" + rid + "-resp\">");
            sb.append (resp_html);
            sb.append ("</div>");

            return sb.str;
        }

        /* Render one round from a plain content string (legacy / simple messages). */
        private static string round_html_from_content (string sid, int r, string content) {
            string rid   = sid + "-r%d".printf (r);
            string think = "";
            string resp  = content;

            if (content.has_prefix ("<think>")) {
                string remaining = content.substring (7);
                while (true) {
                    int end = remaining.index_of ("</think>");
                    if (end < 0) { think += remaining; resp = ""; break; }
                    think    += remaining.substring (0, end);
                    remaining = remaining.substring (end + 8).strip ();
                    if (remaining.has_prefix ("<think>")) {
                        think += "\n\n"; remaining = remaining.substring (7);
                    } else { resp = remaining; break; }
                }
                think = think.strip ();
                resp  = resp.strip ();
            }

            string think_html = think != "" ? render_markdown (think) : "";
            string resp_html  = resp  != "" ? render_markdown (resp)  : "";
            var sb = new StringBuilder ();

            if (think_html != "") {
                sb.append ("<details class=\"think\" id=\"asst-" + rid + "-think\" open>");
            } else {
                sb.append ("<details class=\"think\" id=\"asst-" + rid + "-think\" hidden>");
            }
            sb.append ("<summary>Thinking\u2026</summary>");
            sb.append ("<div class=\"tk\" id=\"asst-" + rid + "-think-body\">");
            sb.append (think_html);
            sb.append ("</div></details>");

            sb.append ("<div class=\"tool-calls\" id=\"asst-" + rid + "-tools\"></div>");

            sb.append ("<div class=\"asst-content\" id=\"asst-" + rid + "-resp\">");
            sb.append (resp_html);
            sb.append ("</div>");

            return sb.str;
        }

        /* ── CSS ─────────────────────────────────────────────────────── */

        private const string CSS = """
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#ffffff;--fg:#2d2d2d;--user-bg:#1c71d8;--user-fg:#ffffff;
  --code-bg:rgba(0,0,0,.06);--border:rgba(0,0,0,.12);
  --think-bg:rgba(0,0,0,.03);--dim:#767676;
}
@media(prefers-color-scheme:dark){:root{
  --bg:#242424;--fg:#deddda;--user-bg:#1c71d8;--user-fg:#ffffff;
  --code-bg:rgba(255,255,255,.08);--border:rgba(255,255,255,.12);
  --think-bg:rgba(255,255,255,.04);--dim:#9a9996;
}}
html,body{background:var(--bg);color:var(--fg);
  font-family:-apple-system,system-ui,Cantarell,sans-serif;
  font-size:14px;line-height:1.6;word-wrap:break-word;overflow-wrap:break-word;
  -webkit-user-select:text;user-select:text}
.katex-error{color:inherit !important}
body{padding:0}
#chat{width:100%;max-width:1080px;margin:0 auto;padding:0 16px 24px;box-sizing:border-box}
.user-row{display:flex;justify-content:flex-end;margin:8px 0 4px 80px}
.user-col{display:flex;flex-direction:column;align-items:flex-end;gap:4px;max-width:100%}
.user-bubble{background:var(--user-bg);color:var(--user-fg);
  border-radius:18px 18px 4px 18px;padding:10px 14px;
  white-space:pre-wrap;word-break:break-word;max-width:100%}
.user-bubble p{margin:.4em 0;white-space:normal}
.user-bubble p:first-child{margin-top:0}.user-bubble p:last-child{margin-bottom:0}
.user-bubble ul,.user-bubble ol{padding-left:1.4em;margin:.3em 0;white-space:normal}
.user-bubble li{margin:.1em 0}
.user-bubble code{font-family:"JetBrains Mono","Fira Code","Cascadia Code",monospace;
  font-size:.88em;background:rgba(255,255,255,.2);padding:1px 5px;border-radius:4px}
.user-bubble pre{background:rgba(0,0,0,.25);border-radius:8px;padding:10px 12px;
  overflow-x:auto;margin:.5em 0;white-space:normal}
.user-bubble pre code{background:none;padding:0;font-size:.86em;white-space:pre}
.user-bubble blockquote{border-left:3px solid rgba(255,255,255,.5);
  margin:.5em 0;padding-left:10px;opacity:.85}
.user-bubble a{color:rgba(255,255,255,.9)}
.att-img{max-width:320px;max-height:220px;border-radius:12px;object-fit:contain;display:block}
.att-chip{background:rgba(28,113,216,.15);color:var(--fg);border-radius:10px;
  padding:4px 10px;font-size:12px}
.asst-row{margin:16px 0 8px}
.asst-name{font-size:11px;color:var(--dim);font-weight:500;margin-bottom:6px}
details.tool-call{background:var(--think-bg);border:1px solid var(--border);
  border-radius:8px;padding:2px 10px;margin-bottom:8px;font-size:12px;color:var(--dim)}
details.tool-call summary{cursor:pointer;padding:4px 0}
details.tool-call pre{font-size:11px;max-height:160px;overflow-y:auto;
  white-space:pre-wrap;word-break:break-word;margin-top:4px}
details.think{background:var(--think-bg);border:1px solid var(--border);
  border-radius:8px;padding:2px 10px;margin-bottom:10px;
  font-size:13px;color:var(--dim)}
details.think .katex,details.think .katex-display{color:var(--fg)}
details.think summary{cursor:pointer;padding:4px 0;font-style:italic}
details.think[open] summary{margin-bottom:4px}
.asst-content h1,.asst-content h2,.asst-content h3,
.asst-content h4,.asst-content h5,.asst-content h6
  {margin:.9em 0 .3em;line-height:1.3}
.asst-content h1{font-size:1.5em}.asst-content h2{font-size:1.3em}
.asst-content h3{font-size:1.15em}
.asst-content p{margin:.5em 0}
.asst-content p:first-child{margin-top:0}.asst-content p:last-child{margin-bottom:0}
.asst-content ul,.asst-content ol{padding-left:1.6em;margin:.4em 0}
.asst-content li{margin:.15em 0}
.asst-content code{font-family:"JetBrains Mono","Fira Code","Cascadia Code",monospace;
  font-size:.88em;background:var(--code-bg);padding:1px 5px;border-radius:4px}
.asst-content pre{background:var(--code-bg);border-radius:8px;
  padding:12px 14px;overflow-x:auto;margin:.6em 0}
.asst-content pre code{background:none;padding:0;font-size:.86em;line-height:1.5}
.asst-content blockquote{border-left:3px solid var(--dim);margin:.6em 0;
  padding-left:12px;color:var(--dim)}
.asst-content hr{border:none;border-top:1px solid var(--border);margin:.8em 0}
.asst-content table{border-collapse:collapse;width:100%;margin:.6em 0;font-size:.93em}
.asst-content th,.asst-content td{border:1px solid var(--border);padding:5px 10px;text-align:left}
.asst-content th{background:var(--code-bg);font-weight:600}
.asst-content a{color:var(--user-bg)}
.katex-display{overflow-x:auto;overflow-y:hidden;margin:.7em 0}
.asst-stats{font-size:11px;color:var(--dim);margin-top:6px}
.asst-actions{margin-top:6px;display:flex;gap:4px}
.asst-actions button{background:none;border:1px solid var(--border);
  border-radius:6px;padding:2px 8px;font-size:11px;cursor:pointer;color:var(--fg)}
.asst-actions button:hover{background:var(--code-bg)}
.user-actions{display:flex;gap:4px;justify-content:flex-end;margin-top:4px}
.user-actions button{background:none;border:1px solid rgba(255,255,255,.35);
  border-radius:6px;padding:2px 8px;font-size:11px;cursor:pointer;color:rgba(255,255,255,.85)}
.user-actions button:hover{background:rgba(255,255,255,.15)}
@keyframes pulse{0%,100%{opacity:.3}50%{opacity:1}}
.dot{display:inline-block;width:6px;height:6px;border-radius:50%;
  background:var(--dim);animation:pulse 1.2s ease-in-out infinite;margin:2px}
""";

    }  // class HtmlRenderer
}  // namespace LLMStudio

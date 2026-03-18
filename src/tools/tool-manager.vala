namespace LLMStudio {

    public class ToolManager : Object {

        public bool duckduckgo_enabled    { get; set; default = false; }
        public bool visit_website_enabled { get; set; default = false; }

        private Soup.Session http_session;

        public ToolManager (GLib.Settings settings) {
            http_session         = new Soup.Session ();
            http_session.timeout = 30;

            settings.bind ("tool-duckduckgo-enabled",    this, "duckduckgo-enabled",    GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("tool-visit-website-enabled", this, "visit-website-enabled", GLib.SettingsBindFlags.DEFAULT);
        }

        /* Returns an array of enabled tool definitions, or null if none are enabled. */
        public Json.Array? get_tools_array () {
            if (!duckduckgo_enabled && !visit_website_enabled) return null;
            var arr = new Json.Array ();
            if (duckduckgo_enabled)
                arr.add_element (make_tool_def (
                    "duckduckgo_search",
                    "Search DuckDuckGo for current information, facts, or news.",
                    "query", "The search query string"));
            if (visit_website_enabled)
                arr.add_element (make_tool_def (
                    "visit_website",
                    "Fetch and read the text content of a web page.",
                    "url", "The full URL to fetch (must start with http:// or https://)"));
            return arr;
        }

        /* Execute a named tool with a JSON arguments string.  Returns the result. */
        public async string execute_async (string name, string arguments_json,
                                           GLib.Cancellable? cancel = null)
        {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (arguments_json);
                var args = parser.get_root ().get_object ();
                switch (name) {
                    case "duckduckgo_search":
                        return yield search_duckduckgo_async (
                            args.get_string_member ("query"), cancel);
                    case "visit_website":
                        return yield fetch_url_async (
                            args.get_string_member ("url"), cancel);
                    default:
                        return "Unknown tool: %s".printf (name);
                }
            } catch (Error e) {
                return "Tool error: %s".printf (e.message);
            }
        }

        // ── Private implementation ────────────────────────────────────────────

        /* Randomized real browser User-Agent strings to avoid DDG bot detection */
        private static string[] USER_AGENTS = {
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36",
            "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0",
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36"
        };

        private static string random_user_agent () {
            uint idx = GLib.Random.next_int () % USER_AGENTS.length;
            return USER_AGENTS[idx];
        }

        private async string search_duckduckgo_async (string query,
                                                       GLib.Cancellable? cancel)
        {
            try {
                string encoded = GLib.Uri.escape_string (query, null, false);
                var msg = new Soup.Message ("GET",
                    "https://duckduckgo.com/html/?q=" + encoded);
                var hdrs = msg.request_headers;
                hdrs.replace ("User-Agent",      random_user_agent ());
                hdrs.replace ("Accept",          "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8");
                hdrs.replace ("Accept-Language", "en-US,en;q=0.9");
                hdrs.replace ("Referer",         "https://duckduckgo.com/");
                hdrs.replace ("Origin",          "https://duckduckgo.com");
                hdrs.replace ("Sec-Fetch-Dest",  "document");
                hdrs.replace ("Sec-Fetch-Mode",  "navigate");
                hdrs.replace ("Sec-Fetch-Site",  "same-origin");
                hdrs.replace ("Sec-Fetch-User",  "?1");
                hdrs.replace ("Upgrade-Insecure-Requests", "1");
                var bytes = yield http_session.send_and_read_async (
                    msg, GLib.Priority.DEFAULT, cancel);
                if (msg.status_code >= 400)
                    return "Search failed (HTTP %u)".printf (msg.status_code);
                return parse_ddg_html ((string) bytes.get_data (), query);
            } catch (Error e) {
                return "Search error: %s".printf (e.message);
            }
        }

        /* Parse DuckDuckGo HTML — extracts result URLs and titles via href regex. */
        private string parse_ddg_html (string html, string query) {
            var sb = new StringBuilder ();
            sb.append ("DuckDuckGo search results for: %s\n\n".printf (query));
            try {
                /* Match anchors whose href contains an absolute https?:// URL.
                   Pattern mirrors LM Studio: \shref="[^"]*(https?[^?&"]*)[^>]*>([^<]*) */
                var re = new GLib.Regex (
                    "\\shref=\"[^\"']*(https?[^?&\"]*)[^>]*>([^<]*)",
                    GLib.RegexCompileFlags.CASELESS);

                GLib.MatchInfo mi;
                string[] urls   = {};
                string[] titles = {};
                if (re.match (html, 0, out mi)) {
                    while (mi.matches () && urls.length < 10) {
                        string url   = (mi.fetch (1) ?? "").strip ();
                        string title = (mi.fetch (2) ?? "").strip ();
                        /* Skip DDG infrastructure URLs and empty titles */
                        if (url.length > 0 && title.length > 0 &&
                            !url.contains ("duckduckgo.com") &&
                            !url.has_prefix ("javascript"))
                        {
                            urls   += url;
                            titles += title;
                        }
                        mi.next ();
                    }
                }

                int n = int.min (urls.length, 5);
                for (int i = 0; i < n; i++) {
                    string title = titles[i]
                        .replace ("&amp;",  "&").replace ("&lt;",   "<")
                        .replace ("&gt;",   ">").replace ("&quot;", "\"")
                        .replace ("&#39;",  "'").replace ("&nbsp;", " ")
                        .strip ();
                    sb.append ("%d. %s\n   %s\n\n".printf (i + 1, title, urls[i]));
                }
                if (n == 0)
                    return "No results found for: %s".printf (query);
            } catch (Error e) {
                sb.append ("(parse error: %s)".printf (e.message));
            }
            return sb.str;
        }

        private async string fetch_url_async (string url, GLib.Cancellable? cancel) {
            try {
                var msg = new Soup.Message ("GET", url);
                msg.request_headers.append ("User-Agent",
                    "Mozilla/5.0 (X11; Linux x86_64) LLMStudio/0.1");
                var bytes = yield http_session.send_and_read_async (
                    msg, GLib.Priority.DEFAULT, cancel);
                if (msg.status_code >= 400)
                    return "Failed to fetch URL (HTTP %u)".printf (msg.status_code);
                string text = strip_html ((string) bytes.get_data ());
                if (text.length > 4000)
                    text = text[0:4000] + "\n...(truncated)";
                return "Content from %s:\n\n%s".printf (url, text);
            } catch (Error e) {
                return "Failed to fetch URL: %s".printf (e.message);
            }
        }

        private static string strip_html (string html) {
            string s = html;
            try {
                var re1 = new GLib.Regex (
                    "<(script|style)[\\s>][\\s\\S]*?</(script|style)>",
                    GLib.RegexCompileFlags.CASELESS);
                s = re1.replace (s, -1, 0, "");
                var re2 = new GLib.Regex ("<[^>]+>");
                s = re2.replace (s, -1, 0, "");
                s = s.replace ("&amp;",  "&")
                      .replace ("&lt;",   "<")
                      .replace ("&gt;",   ">")
                      .replace ("&quot;", "\"")
                      .replace ("&#39;",  "'")
                      .replace ("&nbsp;", " ");
                var re3 = new GLib.Regex ("[ \\t]+");
                s = re3.replace (s, -1, 0, " ");
                var re4 = new GLib.Regex ("\\n{3,}");
                s = re4.replace (s, -1, 0, "\n\n");
            } catch (Error e) {}
            return s.strip ();
        }

        private static Json.Node make_tool_def (string name, string description,
                                                 string param_name, string param_desc)
        {
            var b = new Json.Builder ();
            b.begin_object ();
              b.set_member_name ("type");     b.add_string_value ("function");
              b.set_member_name ("function"); b.begin_object ();
                b.set_member_name ("name");        b.add_string_value (name);
                b.set_member_name ("description"); b.add_string_value (description);
                b.set_member_name ("parameters");  b.begin_object ();
                  b.set_member_name ("type"); b.add_string_value ("object");
                  b.set_member_name ("properties"); b.begin_object ();
                    b.set_member_name (param_name); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("string");
                      b.set_member_name ("description"); b.add_string_value (param_desc);
                    b.end_object ();
                  b.end_object ();
                  b.set_member_name ("required");
                  b.begin_array (); b.add_string_value (param_name); b.end_array ();
                b.end_object ();
              b.end_object ();
            b.end_object ();
            return b.get_root ();
        }
    }
}

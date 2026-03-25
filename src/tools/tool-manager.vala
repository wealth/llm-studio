namespace LLMStudio {

    public class ToolManager : Object {

        public bool duckduckgo_enabled    { get; set; default = false; }
        public bool visit_website_enabled { get; set; default = false; }
        public bool datetime_enabled      { get; set; default = false; }
        public bool screenshot_enabled      { get; set; default = false; }
        public bool input_desktop_enabled  { get; set; default = false; }

        private Soup.Session http_session;

        public ToolManager (GLib.Settings settings) {
            http_session         = new Soup.Session ();
            http_session.timeout = 30;

            settings.bind ("tool-duckduckgo-enabled",    this, "duckduckgo-enabled",    GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("tool-visit-website-enabled", this, "visit-website-enabled", GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("tool-datetime-enabled",      this, "datetime-enabled",      GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("tool-screenshot-enabled",    this, "screenshot-enabled",    GLib.SettingsBindFlags.DEFAULT);
            settings.bind ("tool-input-desktop-enabled", this, "input-desktop-enabled", GLib.SettingsBindFlags.DEFAULT);
        }

        /* Returns an array of enabled tool definitions, or null if none are enabled. */
        public Json.Array? get_tools_array () {
            if (!duckduckgo_enabled && !visit_website_enabled && !datetime_enabled &&
                !screenshot_enabled && !input_desktop_enabled) return null;
            var arr = new Json.Array ();
            if (datetime_enabled)
                arr.add_element (make_tool_def_noargs (
                    "get_datetime",
                    "Get the current date, time, and timezone on the user's system."));
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
            if (screenshot_enabled)
                arr.add_element (make_tool_def_noargs (
                    "take_screenshot",
                    "Take a screenshot of the current desktop and return it as an image for visual analysis."));
            if (input_desktop_enabled)
                arr.add_element (make_input_desktop_tool_def ());
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
                    case "get_datetime":
                        return get_current_datetime ();
                    case "duckduckgo_search":
                        return yield search_duckduckgo_async (
                            args.get_string_member ("query"), cancel);
                    case "visit_website":
                        return yield fetch_url_async (
                            args.get_string_member ("url"), cancel);
                    case "take_screenshot":
                        return yield take_screenshot_async (cancel);
                    case "input_desktop":
                        return yield execute_input_desktop_async (args, cancel);
                    default:
                        return "Unknown tool: %s".printf (name);
                }
            } catch (Error e) {
                return "Tool error: %s".printf (e.message);
            }
        }

        /* Sentinel prefix used to carry screenshot image data through the tool
           result pipeline.  chat-view.vala detects this prefix and builds the
           proper image_url content block for the backend message array.       */
        public const string SCREENSHOT_PREFIX = "SCREENSHOT_DATA_URI:";

        // ── Private implementation ────────────────────────────────────────────

        private static string get_current_datetime () {
            var now = new DateTime.now_local ();
            var tz  = now.get_timezone_abbreviation ();
            return now.format ("Date: %A, %B %-d, %Y\nTime: %H:%M:%S %Z (") + tz + ")";
        }

        private async string take_screenshot_async (GLib.Cancellable? cancel) {
            string tmp_path = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (),
                "llmstudio_ss_%u.png".printf (GLib.Random.next_int ()));
            bool ok = false;
            try {
                string[] argv = { "gnome-screenshot", "-f", tmp_path };
                var sub = new GLib.Subprocess.newv (
                    argv,
                    GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE);
                yield sub.wait_async (cancel);
                ok = sub.get_successful () &&
                     GLib.FileUtils.test (tmp_path, GLib.FileTest.EXISTS);
            } catch (Error e) {}

            if (!ok) {
                try {
                    string[] argv2 = { "scrot", tmp_path };
                    var sub2 = new GLib.Subprocess.newv (
                        argv2,
                        GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE);
                    yield sub2.wait_async (cancel);
                    ok = sub2.get_successful () &&
                         GLib.FileUtils.test (tmp_path, GLib.FileTest.EXISTS);
                } catch (Error e) {}
            }

            if (!ok)
                return "Screenshot failed: neither gnome-screenshot nor scrot is available.";

            try {
                var pixbuf = new Gdk.Pixbuf.from_file (tmp_path);
                GLib.FileUtils.remove (tmp_path);

                /* No scaling — the model must see the image at native resolution
                   so that pixel coordinates it identifies match the real screen. */
                uint8[] jpeg_data;
                pixbuf.save_to_buffer (out jpeg_data, "jpeg", "quality", "85", null);
                string b64 = GLib.Base64.encode (jpeg_data);
                return SCREENSHOT_PREFIX + "data:image/jpeg;base64," + b64;
            } catch (Error e) {
                GLib.FileUtils.remove (tmp_path);
                return "Screenshot encode error: %s".printf (e.message);
            }
        }

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

        /* ── Desktop input (ydotool / xdotool) ─────────────────────────────── */

        /* Translate a human-friendly key combo into the names ydotool expects.
           Modifiers: ydotool needs sided XKB names (Alt_L, Control_L, …).
           Special keys: ydotool uppercases and prepends KEY_ for the evdev
           lookup — use the actual evdev name (KEY_ENTER, not KEY_RETURN).
           Single letters/digits can be passed as-is (ydotool handles them). */
        private static string ydotool_normalize_keys (string keys) {
            string[] parts = keys.split ("+");
            for (int i = 0; i < parts.length; i++) {
                switch (parts[i].down ()) {
                    /* Modifiers — sided XKB names required */
                    case "alt":   parts[i] = "Alt_L";     break;
                    case "ctrl":  parts[i] = "Control_L"; break;
                    case "shift": parts[i] = "Shift_L";   break;
                    case "super": case "win": case "meta": parts[i] = "Super_L"; break;
                    /* Special keys — explicit evdev names (Linux has KEY_ENTER, not KEY_RETURN) */
                    case "return": case "enter": parts[i] = "ENTER";     break;
                    case "tab":                  parts[i] = "TAB";       break;
                    case "escape": case "esc":   parts[i] = "ESC";       break;
                    case "space":                parts[i] = "SPACE";     break;
                    case "backspace":            parts[i] = "BACKSPACE";  break;
                    case "delete": case "del":   parts[i] = "DELETE";    break;
                    case "up":                   parts[i] = "UP";        break;
                    case "down":                 parts[i] = "DOWN";      break;
                    case "left":                 parts[i] = "LEFT";      break;
                    case "right":                parts[i] = "RIGHT";     break;
                    case "home":                 parts[i] = "HOME";      break;
                    case "end":                  parts[i] = "END";       break;
                    case "pageup":               parts[i] = "PAGEUP";    break;
                    case "pagedown":             parts[i] = "PAGEDOWN";  break;
                    case "f1":  parts[i] = "F1";  break;
                    case "f2":  parts[i] = "F2";  break;
                    case "f3":  parts[i] = "F3";  break;
                    case "f4":  parts[i] = "F4";  break;
                    case "f5":  parts[i] = "F5";  break;
                    case "f6":  parts[i] = "F6";  break;
                    case "f7":  parts[i] = "F7";  break;
                    case "f8":  parts[i] = "F8";  break;
                    case "f9":  parts[i] = "F9";  break;
                    case "f10": parts[i] = "F10"; break;
                    case "f11": parts[i] = "F11"; break;
                    case "f12": parts[i] = "F12"; break;
                }
            }
            return string.joinv ("+", parts);
        }

        /* Run a subprocess and return "OK" on success, an error string on
           failure, or null if the binary was not found (spawn error).      */
        private async string? try_run_async (string[] argv, GLib.Cancellable? cancel) {
            try {
                var sub = new GLib.Subprocess.newv (
                    argv,
                    GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE);
                yield sub.wait_async (cancel);
                return sub.get_successful ()
                    ? "OK"
                    : "exit %d".printf (sub.get_exit_status ());
            } catch (Error e) {
                return null; /* binary not found or not executable */
            }
        }

        private static async void tool_sleep (uint ms) {
            GLib.Timeout.add (ms, () => { tool_sleep.callback (); return false; });
            yield;
        }

        private async string execute_input_desktop_async (Json.Object args,
                                                          GLib.Cancellable? cancel)
        {
            string action = args.has_member ("action")
                ? args.get_string_member ("action") : "";

            /* Optional delay before acting — gives the user time to switch focus
               away from LLM Studio so keystrokes reach the intended window.     */
            if (args.has_member ("delay_ms")) {
                int delay = (int) args.get_int_member ("delay_ms");
                if (delay > 0 && delay <= 30000)
                    yield tool_sleep ((uint) delay);
            }

            string? res = null;

            switch (action) {

                case "mouse_move": {
                    if (!args.has_member ("x") || !args.has_member ("y"))
                        return "mouse_move requires x and y.";
                    int x = (int) args.get_int_member ("x");
                    int y = (int) args.get_int_member ("y");

                    res = yield try_run_async (
                        new string[] { "ydotool", "mousemove", "--absolute",
                                       "-x", x.to_string (), "-y", y.to_string () },
                        cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Mouse moved to (%d, %d).".printf (x, y)
                            : "ydotool error: " + res;

                    res = yield try_run_async (
                        new string[] { "xdotool", "mousemove", x.to_string (), y.to_string () },
                        cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Mouse moved to (%d, %d).".printf (x, y)
                            : "xdotool error: " + res;

                    return "Input unavailable: install ydotool (Wayland) or xdotool (X11).";
                }

                case "mouse_click": {
                    string btn = args.has_member ("button")
                        ? args.get_string_member ("button") : "left";
                    /* ydotool click codes: left=0xC0, right=0xC8, middle=0xC4 */
                    string yd_btn = btn == "right" ? "0xC8" : btn == "middle" ? "0xC4" : "0xC0";
                    string xd_btn = btn == "right" ? "3"    : btn == "middle" ? "2"    : "1";
                    bool has_pos  = args.has_member ("x") && args.has_member ("y");
                    int  x = has_pos ? (int) args.get_int_member ("x") : 0;
                    int  y = has_pos ? (int) args.get_int_member ("y") : 0;
                    string pos_desc = has_pos
                        ? " at (%d, %d)".printf (x, y) : " at current position";

                    /* Try ydotool */
                    if (has_pos) {
                        res = yield try_run_async (
                            new string[] { "ydotool", "mousemove", "--absolute",
                                           "-x", x.to_string (), "-y", y.to_string () },
                            cancel);
                    } else {
                        res = yield try_run_async (
                            new string[] { "ydotool", "click", yd_btn }, cancel);
                    }
                    if (res != null || has_pos) {
                        if (has_pos && res != null && res != "OK")
                            return "ydotool move error: " + res;
                        if (has_pos && res != null) {
                            /* move succeeded, now click */
                            res = yield try_run_async (
                                new string[] { "ydotool", "click", yd_btn }, cancel);
                        }
                        if (res != null)
                            return res == "OK"
                                ? "%s click%s.".printf (btn, pos_desc)
                                : "ydotool click error: " + res;
                    }

                    /* Try xdotool */
                    if (has_pos) {
                        res = yield try_run_async (
                            new string[] { "xdotool", "mousemove", x.to_string (), y.to_string () },
                            cancel);
                        if (res != null && res != "OK")
                            return "xdotool move error: " + res;
                    }
                    res = yield try_run_async (
                        new string[] { "xdotool", "click", xd_btn }, cancel);
                    if (res != null)
                        return res == "OK"
                            ? "%s click%s.".printf (btn, pos_desc)
                            : "xdotool click error: " + res;

                    return "Input unavailable: install ydotool (Wayland) or xdotool (X11).";
                }

                case "mouse_scroll": {
                    string dir = args.has_member ("direction")
                        ? args.get_string_member ("direction") : "down";
                    int amount = args.has_member ("amount")
                        ? (int) args.get_int_member ("amount") : 3;

                    /* ydotool scroll: --axis-y positive=down, negative=up */
                    string yd_axis;
                    int    yd_val;
                    string xd_btn;
                    switch (dir) {
                        case "up":    yd_axis = "--axis-y"; yd_val = -amount; xd_btn = "4"; break;
                        case "down":  yd_axis = "--axis-y"; yd_val =  amount; xd_btn = "5"; break;
                        case "left":  yd_axis = "--axis-x"; yd_val = -amount; xd_btn = "6"; break;
                        case "right": yd_axis = "--axis-x"; yd_val =  amount; xd_btn = "7"; break;
                        default: return "Unknown scroll direction '%s' (use up/down/left/right).".printf (dir);
                    }

                    res = yield try_run_async (
                        new string[] { "ydotool", "scroll", yd_axis, yd_val.to_string () },
                        cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Scrolled %s by %d.".printf (dir, amount)
                            : "ydotool scroll error: " + res;

                    /* xdotool: click scroll buttons N times */
                    bool xd_ok = true;
                    for (int i = 0; i < amount && xd_ok; i++) {
                        res = yield try_run_async (
                            new string[] { "xdotool", "click", xd_btn }, cancel);
                        if (res == null) { xd_ok = false; break; }
                        if (res != "OK") return "xdotool scroll error: " + res;
                    }
                    if (xd_ok)
                        return "Scrolled %s by %d.".printf (dir, amount);

                    return "Input unavailable: install ydotool (Wayland) or xdotool (X11).";
                }

                case "key_press": {
                    if (!args.has_member ("keys"))
                        return "key_press requires a 'keys' parameter (e.g. \"ctrl+c\", \"Return\").";
                    string keys = args.get_string_member ("keys");

                    res = yield try_run_async (
                        new string[] { "ydotool", "key", ydotool_normalize_keys (keys) }, cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Key pressed: %s.".printf (keys)
                            : "ydotool key error: " + res;

                    res = yield try_run_async (
                        new string[] { "xdotool", "key", keys }, cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Key pressed: %s.".printf (keys)
                            : "xdotool key error: " + res;

                    return "Input unavailable: install ydotool (Wayland) or xdotool (X11).";
                }

                case "type_text": {
                    if (!args.has_member ("text"))
                        return "type_text requires a 'text' parameter.";
                    string text = args.get_string_member ("text");

                    res = yield try_run_async (
                        new string[] { "ydotool", "type", "--", text }, cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Typed %d character(s).".printf (text.char_count ())
                            : "ydotool type error: " + res;

                    res = yield try_run_async (
                        new string[] { "xdotool", "type", "--", text }, cancel);
                    if (res != null)
                        return res == "OK"
                            ? "Typed %d character(s).".printf (text.char_count ())
                            : "xdotool type error: " + res;

                    return "Input unavailable: install ydotool (Wayland) or xdotool (X11).";
                }

                default:
                    return "Unknown action '%s'. Valid: mouse_move, mouse_click, mouse_scroll, key_press, type_text.".printf (action);
            }
        }

        private static Json.Node make_input_desktop_tool_def () {
            var b = new Json.Builder ();
            b.begin_object ();
              b.set_member_name ("type");     b.add_string_value ("function");
              b.set_member_name ("function"); b.begin_object ();
                b.set_member_name ("name");        b.add_string_value ("input_desktop");
                b.set_member_name ("description"); b.add_string_value (
                    "Send mouse or keyboard input events to the GNOME desktop. " +
                    "Requires ydotool (Wayland) or xdotool (X11) to be installed.");
                b.set_member_name ("parameters"); b.begin_object ();
                  b.set_member_name ("type"); b.add_string_value ("object");
                  b.set_member_name ("properties"); b.begin_object ();

                    b.set_member_name ("action"); b.begin_object ();
                      b.set_member_name ("type"); b.add_string_value ("string");
                      b.set_member_name ("enum"); b.begin_array ();
                        b.add_string_value ("mouse_move");
                        b.add_string_value ("mouse_click");
                        b.add_string_value ("mouse_scroll");
                        b.add_string_value ("key_press");
                        b.add_string_value ("type_text");
                      b.end_array ();
                      b.set_member_name ("description"); b.add_string_value (
                          "mouse_move: move cursor; mouse_click: click a button; " +
                          "mouse_scroll: scroll wheel; key_press: press key combo; " +
                          "type_text: type a string");
                    b.end_object ();

                    b.set_member_name ("x"); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("integer");
                      b.set_member_name ("description"); b.add_string_value (
                          "Absolute X pixel coordinate (mouse_move, mouse_click)");
                    b.end_object ();

                    b.set_member_name ("y"); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("integer");
                      b.set_member_name ("description"); b.add_string_value (
                          "Absolute Y pixel coordinate (mouse_move, mouse_click)");
                    b.end_object ();

                    b.set_member_name ("button"); b.begin_object ();
                      b.set_member_name ("type"); b.add_string_value ("string");
                      b.set_member_name ("enum"); b.begin_array ();
                        b.add_string_value ("left");
                        b.add_string_value ("right");
                        b.add_string_value ("middle");
                      b.end_array ();
                      b.set_member_name ("description"); b.add_string_value (
                          "Mouse button for mouse_click (default: left)");
                    b.end_object ();

                    b.set_member_name ("direction"); b.begin_object ();
                      b.set_member_name ("type"); b.add_string_value ("string");
                      b.set_member_name ("enum"); b.begin_array ();
                        b.add_string_value ("up");
                        b.add_string_value ("down");
                        b.add_string_value ("left");
                        b.add_string_value ("right");
                      b.end_array ();
                      b.set_member_name ("description"); b.add_string_value (
                          "Scroll direction for mouse_scroll");
                    b.end_object ();

                    b.set_member_name ("amount"); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("integer");
                      b.set_member_name ("description"); b.add_string_value (
                          "Scroll wheel clicks for mouse_scroll (default: 3)");
                    b.end_object ();

                    b.set_member_name ("keys"); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("string");
                      b.set_member_name ("description"); b.add_string_value (
                          "Key combo for key_press, e.g. \"ctrl+c\", \"Return\", \"alt+F4\", \"super+l\"");
                    b.end_object ();

                    b.set_member_name ("text"); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("string");
                      b.set_member_name ("description"); b.add_string_value (
                          "Text to type for type_text");
                    b.end_object ();

                    b.set_member_name ("delay_ms"); b.begin_object ();
                      b.set_member_name ("type");        b.add_string_value ("integer");
                      b.set_member_name ("description"); b.add_string_value (
                          "Optional delay in milliseconds before sending input (max 30000). " +
                          "Use this to give the user time to switch focus to the target window " +
                          "before keystrokes or mouse events are sent.");
                    b.end_object ();

                  b.end_object (); /* properties */
                  b.set_member_name ("required");
                  b.begin_array (); b.add_string_value ("action"); b.end_array ();
                b.end_object (); /* parameters */
              b.end_object (); /* function */
            b.end_object ();
            return b.get_root ();
        }

        private static Json.Node make_tool_def_noargs (string name, string description) {
            var b = new Json.Builder ();
            b.begin_object ();
              b.set_member_name ("type");     b.add_string_value ("function");
              b.set_member_name ("function"); b.begin_object ();
                b.set_member_name ("name");        b.add_string_value (name);
                b.set_member_name ("description"); b.add_string_value (description);
                b.set_member_name ("parameters");  b.begin_object ();
                  b.set_member_name ("type");       b.add_string_value ("object");
                  b.set_member_name ("properties"); b.begin_object (); b.end_object ();
                b.end_object ();
              b.end_object ();
            b.end_object ();
            return b.get_root ();
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

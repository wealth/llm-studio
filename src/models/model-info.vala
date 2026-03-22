namespace LLMStudio {

    public enum ModelFormat {
        GGUF,
        SAFETENSORS,
        PYTORCH,
        UNKNOWN;

        public string to_string () {
            switch (this) {
                case GGUF:        return "GGUF";
                case SAFETENSORS: return "SafeTensors";
                case PYTORCH:     return "PyTorch";
                default:          return "Unknown";
            }
        }

        public static ModelFormat from_filename (string filename) {
            var lower = filename.ascii_down ();
            if (lower.has_suffix (".gguf"))        return GGUF;
            if (lower.has_suffix (".safetensors")) return SAFETENSORS;
            if (lower.has_suffix (".bin"))         return PYTORCH;
            return UNKNOWN;
        }
    }

    public class ModelParams : Object {
        // Context
        public int    context_length   { get; set; default = 4096; }
        public int    batch_size       { get; set; default = 512;  }
        public int    ubatch_size      { get; set; default = 512;  }

        // Hardware
        public int    gpu_layers       { get; set; default = -1;   }
        public int    cpu_threads      { get; set; default = -1;   }
        public bool   flash_attention  { get; set; default = true; }
        public bool   mmap             { get; set; default = true; }
        public bool   mlock            { get; set; default = false;}
        public int    tensor_split_gpu { get; set; default = 0;    }

        // KV cache
        public string kv_cache_type    { get; set; default = "f16";}
        public double rope_freq_scale  { get; set; default = 1.0; }
        public int    rope_freq_base   { get; set; default = 0;    }
        public string rope_scaling     { get; set; default = "";   }

        // Sampling defaults
        public double temperature      { get; set; default = 0.7;  }
        public double top_p            { get; set; default = 0.95; }
        public int    top_k            { get; set; default = 40;   }
        public int    min_p_enabled    { get; set; default = 0;    }
        public double min_p            { get; set; default = 0.05; }
        public double repeat_penalty   { get; set; default = 1.1;  }
        public int    repeat_last_n    { get; set; default = 64;   }
        public double presence_penalty { get; set; default = 0.0;  }
        public double frequency_penalty{ get; set; default = 0.0;  }
        public int    max_tokens       { get; set; default = -1;   }
        public int    seed             { get; set; default = -1;   }

        // System prompt
        public string system_prompt    { get; set; default = "";   }

        // Thinking mode (for models that support it, e.g. Qwen3)
        public bool   enable_thinking  { get; set; default = true; }

        // Jinja chat template override (empty = use model default)
        public string chat_template    { get; set; default = "";   }

        // Vision: load mmproj sidecar (on by default when model supports it)
        public bool   enable_vision    { get; set; default = true; }

        public Json.Node to_json () {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("context_length");    builder.add_int_value (context_length);
            builder.set_member_name ("batch_size");        builder.add_int_value (batch_size);
            builder.set_member_name ("ubatch_size");       builder.add_int_value (ubatch_size);
            builder.set_member_name ("gpu_layers");        builder.add_int_value (gpu_layers);
            builder.set_member_name ("cpu_threads");       builder.add_int_value (cpu_threads);
            builder.set_member_name ("flash_attention");   builder.add_boolean_value (flash_attention);
            builder.set_member_name ("mmap");              builder.add_boolean_value (mmap);
            builder.set_member_name ("mlock");             builder.add_boolean_value (mlock);
            builder.set_member_name ("kv_cache_type");     builder.add_string_value (kv_cache_type);
            builder.set_member_name ("rope_freq_scale");   builder.add_double_value (rope_freq_scale);
            builder.set_member_name ("rope_freq_base");    builder.add_int_value (rope_freq_base);
            builder.set_member_name ("rope_scaling");      builder.add_string_value (rope_scaling);
            builder.set_member_name ("temperature");       builder.add_double_value (temperature);
            builder.set_member_name ("top_p");             builder.add_double_value (top_p);
            builder.set_member_name ("top_k");             builder.add_int_value (top_k);
            builder.set_member_name ("min_p");             builder.add_double_value (min_p);
            builder.set_member_name ("repeat_penalty");    builder.add_double_value (repeat_penalty);
            builder.set_member_name ("repeat_last_n");     builder.add_int_value (repeat_last_n);
            builder.set_member_name ("presence_penalty");  builder.add_double_value (presence_penalty);
            builder.set_member_name ("frequency_penalty"); builder.add_double_value (frequency_penalty);
            builder.set_member_name ("max_tokens");        builder.add_int_value (max_tokens);
            builder.set_member_name ("seed");              builder.add_int_value (seed);
            builder.set_member_name ("system_prompt");     builder.add_string_value (system_prompt);
            builder.set_member_name ("enable_thinking");   builder.add_boolean_value (enable_thinking);
            builder.set_member_name ("enable_vision");     builder.add_boolean_value (enable_vision);
            builder.set_member_name ("chat_template");    builder.add_string_value (chat_template);
            builder.end_object ();
            return builder.get_root ();
        }

        public static ModelParams from_json (Json.Object obj) {
            var p = new ModelParams ();
            if (obj.has_member ("context_length"))    p.context_length    = (int) obj.get_int_member ("context_length");
            if (obj.has_member ("batch_size"))        p.batch_size        = (int) obj.get_int_member ("batch_size");
            if (obj.has_member ("ubatch_size"))       p.ubatch_size       = (int) obj.get_int_member ("ubatch_size");
            if (obj.has_member ("gpu_layers"))        p.gpu_layers        = (int) obj.get_int_member ("gpu_layers");
            if (obj.has_member ("cpu_threads"))       p.cpu_threads       = (int) obj.get_int_member ("cpu_threads");
            if (obj.has_member ("flash_attention"))   p.flash_attention   = obj.get_boolean_member ("flash_attention");
            if (obj.has_member ("mmap"))              p.mmap              = obj.get_boolean_member ("mmap");
            if (obj.has_member ("mlock"))             p.mlock             = obj.get_boolean_member ("mlock");
            if (obj.has_member ("kv_cache_type"))     p.kv_cache_type     = obj.get_string_member ("kv_cache_type");
            if (obj.has_member ("rope_freq_scale"))   p.rope_freq_scale   = obj.get_double_member ("rope_freq_scale");
            if (obj.has_member ("rope_freq_base"))    p.rope_freq_base    = (int) obj.get_int_member ("rope_freq_base");
            if (obj.has_member ("rope_scaling"))      p.rope_scaling      = obj.get_string_member ("rope_scaling");
            if (obj.has_member ("temperature"))       p.temperature       = obj.get_double_member ("temperature");
            if (obj.has_member ("top_p"))             p.top_p             = obj.get_double_member ("top_p");
            if (obj.has_member ("top_k"))             p.top_k             = (int) obj.get_int_member ("top_k");
            if (obj.has_member ("min_p"))             p.min_p             = obj.get_double_member ("min_p");
            if (obj.has_member ("repeat_penalty"))    p.repeat_penalty    = obj.get_double_member ("repeat_penalty");
            if (obj.has_member ("repeat_last_n"))     p.repeat_last_n     = (int) obj.get_int_member ("repeat_last_n");
            if (obj.has_member ("presence_penalty"))  p.presence_penalty  = obj.get_double_member ("presence_penalty");
            if (obj.has_member ("frequency_penalty")) p.frequency_penalty = obj.get_double_member ("frequency_penalty");
            if (obj.has_member ("max_tokens"))        p.max_tokens        = (int) obj.get_int_member ("max_tokens");
            if (obj.has_member ("seed"))              p.seed              = (int) obj.get_int_member ("seed");
            if (obj.has_member ("system_prompt"))     p.system_prompt     = obj.get_string_member ("system_prompt");
            if (obj.has_member ("enable_thinking"))   p.enable_thinking   = obj.get_boolean_member ("enable_thinking");
            if (obj.has_member ("enable_vision"))     p.enable_vision     = obj.get_boolean_member ("enable_vision");
            if (obj.has_member ("chat_template"))    p.chat_template     = obj.get_string_member ("chat_template");
            return p;
        }

        public ModelParams copy () {
            var p = new ModelParams ();
            p.context_length    = context_length;
            p.batch_size        = batch_size;
            p.ubatch_size       = ubatch_size;
            p.gpu_layers        = gpu_layers;
            p.cpu_threads       = cpu_threads;
            p.flash_attention   = flash_attention;
            p.mmap              = mmap;
            p.mlock             = mlock;
            p.kv_cache_type     = kv_cache_type;
            p.rope_freq_scale   = rope_freq_scale;
            p.rope_freq_base    = rope_freq_base;
            p.rope_scaling      = rope_scaling;
            p.temperature       = temperature;
            p.top_p             = top_p;
            p.top_k             = top_k;
            p.min_p             = min_p;
            p.repeat_penalty    = repeat_penalty;
            p.repeat_last_n     = repeat_last_n;
            p.presence_penalty  = presence_penalty;
            p.frequency_penalty = frequency_penalty;
            p.max_tokens        = max_tokens;
            p.seed              = seed;
            p.system_prompt     = system_prompt;
            p.enable_thinking   = enable_thinking;
            p.enable_vision     = enable_vision;
            p.chat_template     = chat_template;
            return p;
        }
    }

    public class ModelInfo : Object {
        public string      id         { get; set; default = ""; }
        public string      name       { get; set; default = ""; }
        public string      path       { get; set; default = ""; }
        public int64       size       { get; set; default = 0;  }
        public ModelFormat format     { get; set; default = ModelFormat.UNKNOWN; }
        public string?     hf_repo    { get; set; default = null; }
        public string?     description{ get; set; default = null; }
        public string?     family     { get; set; default = null; }
        public int64       parameters { get; set; default = 0;    }  // e.g. 7_000_000_000
        public string      gguf_quant { get; set; default = "";   }  // from GGUF file_type header
        public int         block_count  { get; set; default = 0;   }  // transformer layer count
        public bool        has_vision   { get; set; default = false; }
        public bool        has_tools    { get; set; default = false; }
        public bool        has_thinking { get; set; default = false; }
        public string?     default_chat_template { get; set; default = null; }
        public ModelParams params     { get; set; }

        construct {
            params = new ModelParams ();
        }

        public string format_size () {
            if (size <= 0) return "Unknown";
            double gb = size / (1024.0 * 1024.0 * 1024.0);
            if (gb >= 1.0) return "%.1f GB".printf (gb);
            double mb = size / (1024.0 * 1024.0);
            return "%.0f MB".printf (mb);
        }

        public string format_params () {
            if (parameters <= 0) return "";
            double b = parameters / 1000000000.0;
            if (b >= 1.0) return "%.0fB".printf (b);
            double m = parameters / 1000000.0;
            return "%.0fM".printf (m);
        }

        // Filename without extension (and without part suffix), for display
        public string display_name () {
            string n = name;
            if (n.has_suffix (".gguf"))        n = n.substring (0, n.length - 5);
            if (n.has_suffix (".safetensors")) n = n.substring (0, n.length - 12);
            return strip_part_suffix (n);
        }

        // Model name stripped of quantization, -GGUF suffix, and extension.
        // Prefers the repo name from hf_repo when available.
        public string clean_name () {
            string stem;
            if (hf_repo != null && hf_repo != "") {
                int idx = hf_repo.index_of ("/");
                stem = idx < 0 ? hf_repo : hf_repo.substring (idx + 1);
            } else {
                stem = GLib.Path.get_basename (path);
                if (stem.has_suffix (".gguf"))        stem = stem.substring (0, stem.length - 5);
                if (stem.has_suffix (".safetensors")) stem = stem.substring (0, stem.length - 12);
                stem = strip_part_suffix (stem);
            }
            // Strip -GGUF suffix (case-insensitive)
            if (stem.length > 5 && stem.substring (stem.length - 5).ascii_up () == "-GGUF")
                stem = stem.substring (0, stem.length - 5);
            // Strip quantization suffix from the end (e.g. -Q4_K_M, .Q4_K_M, -BF16)
            var q = quant_tag ();
            if (q != "" && stem.length > q.length + 1) {
                string tail = stem.substring (stem.length - q.length - 1);
                if (tail.get_char (0) == '-' || tail.get_char (0) == '.')
                    if (tail.substring (1).ascii_up () == q.ascii_up ())
                        stem = stem.substring (0, stem.length - q.length - 1);
            }
            return stem;
        }

        // Extract quantization tag — prefers value read from GGUF header,
        // falls back to filename heuristic.
        public string quant_tag () {
            if (gguf_quant != "") return gguf_quant;
            var stem = GLib.Path.get_basename (path);
            if (stem.has_suffix (".gguf"))        stem = stem.substring (0, stem.length - 5);
            if (stem.has_suffix (".safetensors")) stem = stem.substring (0, stem.length - 12);
            return extract_quant_from_stem (stem);
        }

        // Filename-based quant extraction (no GGUF header lookup).
        public static string extract_quant_from_stem (string stem) {
            foreach (unowned string part in stem.split_set ("-.")) {
                string up = part.ascii_up ();
                if (up == "BF16" || up == "F16" || up == "F32" || up == "FP16" || up == "FP32")
                    return up;
                if (up.length >= 2 && up.get_char (0) == 'Q' && up.get_char (1).isdigit ())
                    return up;
                if (up.length >= 3 && up.get_char (0) == 'I' && up.get_char (1) == 'Q'
                        && up.get_char (2).isdigit ())
                    return up;
                if (up.has_prefix ("MXFP"))
                    return up;
            }
            return "";
        }

        /* ── Multi-part file helpers ───────────────────────────────────── */

        private static GLib.Regex? _part_re = null;

        private static GLib.Regex? get_part_re () {
            if (_part_re == null) {
                try {
                    _part_re = new GLib.Regex ("-([0-9]+)-of-([0-9]+)$", 0, 0);
                } catch (GLib.RegexError e) {
                    warning ("part regex: %s", e.message);
                }
            }
            return _part_re;
        }

        // Returns 1-based part number, or 0 if not a multi-part filename.
        public static int part_number (string filename) {
            string stem = filename.has_suffix (".gguf")
                ? filename.substring (0, filename.length - 5) : filename;
            var re = get_part_re ();
            if (re == null) return 0;
            GLib.MatchInfo mi;
            if (!re.match (stem, 0, out mi)) return 0;
            return int.parse (mi.fetch (1));
        }

        // Returns total part count, or 0 if not a multi-part filename.
        public static int part_total (string filename) {
            string stem = filename.has_suffix (".gguf")
                ? filename.substring (0, filename.length - 5) : filename;
            var re = get_part_re ();
            if (re == null) return 0;
            GLib.MatchInfo mi;
            if (!re.match (stem, 0, out mi)) return 0;
            return int.parse (mi.fetch (2));
        }

        // Strips -NNNNN-of-MMMMM from a stem (no extension expected).
        public static string strip_part_suffix (string stem) {
            var re = get_part_re ();
            if (re == null) return stem;
            GLib.MatchInfo mi;
            if (!re.match (stem, 0, out mi)) return stem;
            int start, end;
            mi.fetch_pos (0, out start, out end);
            return stem.substring (0, start);
        }

        // For a non-first part, returns the path of part 1; null otherwise.
        public static string? part1_path (string filepath) {
            string basename = GLib.Path.get_basename (filepath);
            int pnum = part_number (basename);
            if (pnum <= 1) return null;
            int total = part_total (basename);
            if (total <= 0) return null;
            string dir  = GLib.Path.get_dirname (filepath);
            string stem = basename.has_suffix (".gguf")
                ? basename.substring (0, basename.length - 5) : basename;
            string base_name = strip_part_suffix (stem);
            return GLib.Path.build_filename (dir, "%s-00001-of-%05d.gguf".printf (base_name, total));
        }

        // HuggingFace publisher (first component of hf_repo before '/')
        public string publisher () {
            // Prefer explicit hf_repo (set when downloaded through the Hub)
            if (hf_repo != null && hf_repo != "") {
                int idx = hf_repo.index_of ("/");
                return idx < 0 ? hf_repo : hf_repo.substring (0, idx);
            }
            // Infer from LM-Studio-style layout: publisher/repo/file.gguf
            // Try grandparent first, fall back to parent for flat publisher/file.gguf
            var file_dir  = GLib.Path.get_dirname (path);
            var pub_dir   = GLib.Path.get_dirname (file_dir);
            var grandparent = GLib.Path.get_basename (pub_dir);
            if (is_publisher_name (grandparent)) return grandparent;
            var parent = GLib.Path.get_basename (file_dir);
            if (is_publisher_name (parent)) return parent;
            return "";
        }

        private static bool is_publisher_name (string s) {
            if (s == "" || s == "." || s == "/") return false;
            if (s.has_prefix (".")) return false;
            switch (s.down ()) {
                case "models": case "model": case "gguf": case "gguf-models":
                case "downloads": case "download": case "llm": case "llms":
                case "ai": case "local": case "weights": case "checkpoints":
                case "hub": case "cache": case "blobs": case "snapshots":
                    return false;
            }
            return true;
        }

        public Json.Node to_json () {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("id");     builder.add_string_value (id);
            builder.set_member_name ("name");   builder.add_string_value (name);
            builder.set_member_name ("path");   builder.add_string_value (path);
            builder.set_member_name ("size");   builder.add_int_value (size);
            builder.set_member_name ("format"); builder.add_string_value (format.to_string ());
            if (hf_repo != null) {
                builder.set_member_name ("hf_repo");
                builder.add_string_value (hf_repo);
            }
            if (description != null) {
                builder.set_member_name ("description");
                builder.add_string_value (description);
            }
            if (family != null) {
                builder.set_member_name ("family");
                builder.add_string_value (family);
            }
            builder.set_member_name ("parameters"); builder.add_int_value (parameters);
            builder.set_member_name ("params");     builder.add_value (params.to_json ());
            builder.end_object ();
            return builder.get_root ();
        }

        public static ModelInfo from_json (Json.Object obj) {
            var m = new ModelInfo ();
            if (obj.has_member ("id"))          m.id          = obj.get_string_member ("id");
            if (obj.has_member ("name"))        m.name        = obj.get_string_member ("name");
            if (obj.has_member ("path"))        m.path        = obj.get_string_member ("path");
            if (obj.has_member ("size"))        m.size        = obj.get_int_member ("size");
            if (obj.has_member ("hf_repo"))     m.hf_repo     = obj.get_string_member ("hf_repo");
            if (obj.has_member ("description")) m.description = obj.get_string_member ("description");
            if (obj.has_member ("family"))      m.family      = obj.get_string_member ("family");
            if (obj.has_member ("parameters"))  m.parameters  = obj.get_int_member ("parameters");
            if (obj.has_member ("params"))
                m.params = ModelParams.from_json (obj.get_object_member ("params"));
            return m;
        }

        public static ModelInfo from_file (string filepath) {
            var m = new ModelInfo ();
            m.path = filepath;
            m.name = GLib.Path.get_basename (filepath);
            m.format = ModelFormat.from_filename (filepath);
            m.id = GLib.Checksum.compute_for_string (GLib.ChecksumType.MD5, filepath);

            try {
                var file = GLib.File.new_for_path (filepath);
                var info = file.query_info ("standard::size", GLib.FileQueryInfoFlags.NONE);
                m.size = info.get_size ();
            } catch (Error e) {
                warning ("Could not stat model file %s: %s", filepath, e.message);
            }

            // Read GGUF metadata (architecture, parameter count, quantization)
            if (m.format == ModelFormat.GGUF)
                GgufReader.read_metadata (filepath, m);

            // For multi-part files (part 1 only), accumulate total size across all parts.
            if (m.format == ModelFormat.GGUF && part_number (m.name) == 1) {
                int total = part_total (m.name);
                if (total > 1) {
                    string dir  = GLib.Path.get_dirname (filepath);
                    string stem = m.name.substring (0, m.name.length - 5);  // strip .gguf
                    string base_name = strip_part_suffix (stem);
                    for (int n = 2; n <= total; n++) {
                        string part_name = "%s-%05d-of-%05d.gguf".printf (base_name, n, total);
                        string part_path = GLib.Path.build_filename (dir, part_name);
                        try {
                            var pf   = GLib.File.new_for_path (part_path);
                            var pfi  = pf.query_info ("standard::size", GLib.FileQueryInfoFlags.NONE);
                            m.size  += pfi.get_size ();
                        } catch { /* part not yet downloaded */ }
                    }
                }
            }

            // Detect vision capability from mmproj sidecar file.
            // Many models (Qwen3.5-VL, LLaVA, …) store vision weights in a
            // separate mmproj-*.gguf file next to the main model file.
            if (!m.has_vision) {
                var dir = GLib.Path.get_dirname (filepath);
                try {
                    var dir_file  = GLib.File.new_for_path (dir);
                    var enumerator = dir_file.enumerate_children (
                        GLib.FileAttribute.STANDARD_NAME,
                        GLib.FileQueryInfoFlags.NONE);
                    GLib.FileInfo? fi;
                    while ((fi = enumerator.next_file ()) != null) {
                        string n = fi.get_name ().down ();
                        if (n.has_prefix ("mmproj") && n.has_suffix (".gguf")) {
                            m.has_vision = true;
                            break;
                        }
                    }
                } catch (Error e) { /* non-critical */ }
            }

            // Try loading saved params
            var params_path = filepath + ".llmstudio.json";
            if (GLib.FileUtils.test (params_path, GLib.FileTest.EXISTS)) {
                try {
                    string data;
                    GLib.FileUtils.get_contents (params_path, out data);
                    var parser = new Json.Parser ();
                    parser.load_from_data (data);
                    var root = parser.get_root ().get_object ();
                    if (root.has_member ("params"))
                        m.params = ModelParams.from_json (root.get_object_member ("params"));
                } catch (Error e) {
                    warning ("Could not load params for %s: %s", filepath, e.message);
                }
            }

            return m;
        }

        public void save_params () {
            var params_path = path + ".llmstudio.json";
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("params");
            builder.add_value (params.to_json ());
            builder.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            gen.pretty = true;

            try {
                GLib.FileUtils.set_contents (params_path, gen.to_data (null));
            } catch (Error e) {
                warning ("Could not save params for %s: %s", path, e.message);
            }
        }
    }

    public class ChatAttachment : Object {
        public string filename  { get; set; default = ""; }
        public string mime_type { get; set; default = ""; }
        /* base64-encoded bytes for images; raw text for text files */
        public string data      { get; set; default = ""; }

        public bool is_image () {
            return mime_type.has_prefix ("image/");
        }

        public string to_data_uri () {
            return "data:" + mime_type + ";base64," + data;
        }

        public Json.Object to_json () {
            var obj = new Json.Object ();
            obj.set_string_member ("filename",  filename);
            obj.set_string_member ("mime_type", mime_type);
            obj.set_string_member ("data",      data);
            return obj;
        }

        public static ChatAttachment from_json (Json.Object obj) {
            var a = new ChatAttachment ();
            if (obj.has_member ("filename"))  a.filename  = obj.get_string_member ("filename");
            if (obj.has_member ("mime_type")) a.mime_type = obj.get_string_member ("mime_type");
            if (obj.has_member ("data"))      a.data      = obj.get_string_member ("data");
            return a;
        }
    }

    /* A single tool call executed during an agentic round. */
    public class ChatToolCall : Object {
        public string display { get; set; default = ""; }
        public string result  { get; set; default = ""; }
    }

    /* One agentic round: optional think block, zero or more tool calls, optional response. */
    public class ChatRound : Object {
        public string think          { get; set; default = ""; }
        public string response       { get; set; default = ""; }
        public double think_duration { get; set; default = -1; }  // seconds, -1 = unknown
        /* Field (not property) to avoid GLib.List "duplicating list" Vala bug. */
        public GLib.List<ChatToolCall> tool_calls;
        construct { tool_calls = new GLib.List<ChatToolCall> (); }
    }

    public class ChatMessage : Object {
        public string   role       { get; set; default = "user"; }
        public string   content    { get; set; default = "";     }
        public bool     streaming  { get; set; default = false;  }
        public int      token_count{ get; set; default = 0;      }
        public DateTime timestamp  { get; set; }
        public string   model_name { get; set; default = "";     }
        public string   stats_text { get; set; default = "";     }

        /* Multimodal attachments and agentic rounds. Fields (not properties)
           to avoid GLib.List "duplicating list" Vala bug.                  */
        public GLib.List<ChatAttachment> attachments;
        public GLib.List<ChatRound>      rounds;

        construct {
            timestamp   = new DateTime.now_local ();
            attachments = new GLib.List<ChatAttachment> ();
            rounds      = new GLib.List<ChatRound> ();
        }

        public bool has_attachments () {
            return attachments.length () > 0;
        }

        public ChatMessage.user (string text) {
            role    = "user";
            content = text;
        }

        public ChatMessage.assistant (string text) {
            role    = "assistant";
            content = text;
        }

        public ChatMessage.system (string text) {
            role    = "system";
            content = text;
        }
    }

}

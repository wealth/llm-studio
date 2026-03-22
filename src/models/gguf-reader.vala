namespace LLMStudio {

    // Reads GGUF binary headers to populate ModelInfo metadata.
    // Spec: https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
    public class GgufReader {

        private const uint32 GGUF_MAGIC   = 0x46554747; // "GGUF" LE
        private const uint8  GGUF_TYPE_UINT8   = 0;
        private const uint8  GGUF_TYPE_INT8    = 1;
        private const uint8  GGUF_TYPE_UINT16  = 2;
        private const uint8  GGUF_TYPE_INT16   = 3;
        private const uint8  GGUF_TYPE_UINT32  = 4;
        private const uint8  GGUF_TYPE_INT32   = 5;
        private const uint8  GGUF_TYPE_FLOAT32 = 6;
        private const uint8  GGUF_TYPE_BOOL    = 7;
        private const uint8  GGUF_TYPE_STRING  = 8;
        private const uint8  GGUF_TYPE_ARRAY   = 9;
        private const uint8  GGUF_TYPE_UINT64  = 10;
        private const uint8  GGUF_TYPE_INT64   = 11;
        private const uint8  GGUF_TYPE_FLOAT64 = 12;

        // LLAMA_FTYPE enum → quant string
        private static string ftype_to_string (uint32 ft) {
            switch (ft) {
                case 0:  return "F32";
                case 1:  return "F16";
                case 2:  return "Q4_0";
                case 3:  return "Q4_1";
                case 7:  return "Q8_0";
                case 8:  return "Q5_0";
                case 9:  return "Q5_1";
                case 10: return "Q2_K";
                case 11: return "Q3_K_S";
                case 12: return "Q3_K_M";
                case 13: return "Q3_K_L";
                case 14: return "Q4_K_S";
                case 15: return "Q4_K_M";
                case 16: return "Q5_K_S";
                case 17: return "Q5_K_M";
                case 18: return "Q6_K";
                case 19: return "Q8_K";
                case 20: return "IQ2_XXS";
                case 21: return "IQ2_XS";
                case 22: return "IQ3_XXS";
                case 23: return "IQ1_S";
                case 24: return "IQ4_NL";
                case 25: return "IQ3_S";
                case 26: return "IQ3_M";
                case 27: return "IQ2_S";
                case 28: return "IQ4_XS";
                case 29: return "IQ1_M";
                case 30: return "BF16";
                case 31: return "Q4_0_4_4";
                case 32: return "Q4_0_4_8";
                case 33: return "Q4_0_8_8";
                case 34: return "TQ1_0";
                case 35: return "TQ2_0";
                default: return "";
            }
        }

        // Reads GGUF metadata and populates model fields.
        // Silently returns on any parse error.
        public static void read_metadata (string path, ModelInfo model) {
            try {
                var file   = GLib.File.new_for_path (path);
                var stream = file.read ();
                var dis    = new GLib.DataInputStream (stream);
                dis.set_byte_order (GLib.DataStreamByteOrder.LITTLE_ENDIAN);

                // ── Magic ────────────────────────────────────────────────
                uint32 magic = dis.read_uint32 ();
                if (magic != GGUF_MAGIC) return;

                // ── Version ──────────────────────────────────────────────
                uint32 version = dis.read_uint32 ();
                if (version == 0 || version > 3) return;

                // ── Counts ───────────────────────────────────────────────
                uint64 n_tensors, n_kv;
                if (version == 1) {
                    n_tensors = (uint64) dis.read_uint32 ();
                    n_kv      = (uint64) dis.read_uint32 ();
                } else {
                    n_tensors = dis.read_uint64 ();
                    n_kv      = dis.read_uint64 ();
                }

                // ── KV pairs ─────────────────────────────────────────────
                int found = 0;

                for (uint64 i = 0; i < n_kv; i++) {
                    if (found >= 8) break;

                    string key      = read_string (dis, version);
                    uint32 val_type = dis.read_uint32 ();

                    if (key == "general.architecture" && val_type == GGUF_TYPE_STRING) {
                        model.family = read_string (dis, version);
                        found++;
                    } else if (key == "general.name" && val_type == GGUF_TYPE_STRING) {
                        /* Store model name hint for vision/tools fallback below */
                        string gname = read_string (dis, version);
                        if (model.name == "" || model.name == GLib.Path.get_basename (model.path))
                            {}  /* keep filename as name */
                        /* Use gname only for capability heuristics via a temp field */
                        /* We'll stash it in description if empty */
                        if (model.description == null || model.description == "")
                            model.description = gname;
                        found++;
                    } else if (key == "general.parameter_count") {
                        if (val_type == GGUF_TYPE_UINT64) {
                            model.parameters = (int64) dis.read_uint64 ();
                            found++;
                        } else if (val_type == GGUF_TYPE_INT64) {
                            model.parameters = dis.read_int64 ();
                            found++;
                        } else {
                            skip_value (dis, val_type, version);
                        }
                    } else if (key == "general.file_type" && val_type == GGUF_TYPE_UINT32) {
                        model.gguf_quant = ftype_to_string (dis.read_uint32 ());
                        found++;
                    } else if (key.has_suffix (".block_count") && !key.has_prefix ("clip.")
                            && (val_type == GGUF_TYPE_UINT32 || val_type == GGUF_TYPE_UINT64)) {
                        model.block_count = val_type == GGUF_TYPE_UINT64
                            ? (int) dis.read_uint64 ()
                            : (int) dis.read_uint32 ();
                        found++;
                    } else if (key == "clip.has_vision_encoder" && val_type == GGUF_TYPE_BOOL) {
                        model.has_vision = dis.read_byte () != 0;
                        found++;
                    } else if (key == "tokenizer.chat_template" && val_type == GGUF_TYPE_STRING) {
                        string tmpl = read_string (dis, version);
                        model.default_chat_template = tmpl;
                        model.has_tools = tmpl.contains ("tool_call")
                            || tmpl.contains ("function_call")
                            || tmpl.contains ("<tool_response>")
                            || tmpl.contains ("[TOOL_CALLS]")
                            || tmpl.contains ("tool_code");
                        model.has_thinking = tmpl.contains ("<think>")
                            || tmpl.contains ("</think>")
                            || tmpl.contains ("/think")
                            || tmpl.contains ("thinking_mode");
                        found++;
                    } else {
                        skip_value (dis, val_type, version);
                    }
                }

                // Architecture-based vision fallback
                if (!model.has_vision && model.family != null) {
                    string fam = model.family.down ();
                    model.has_vision = fam.contains ("llava")
                        || fam.contains ("vision")
                        || fam.has_suffix ("_vl")   // qwen2_vl, qwen3_vl …
                        || fam.has_suffix ("vl")    // qwen2vl, qwen3vl …
                        || fam.contains ("intern_vl")
                        || fam.contains ("minicpm")
                        || fam.contains ("moondream")
                        || fam.contains ("phi3v")
                        || fam.contains ("gemma3");
                }

                // general.name / filename fallback for VL models whose architecture
                // string doesn't carry a vision suffix (e.g. some Qwen3-VL releases)
                if (!model.has_vision) {
                    string[] candidates = {
                        model.name.down (),
                        (model.description ?? "").down ()
                    };
                    foreach (string s in candidates) {
                        if (s == "") continue;
                        if (s.contains ("-vl-")   || s.contains ("_vl_")
                         || s.contains ("-vl.")   || s.contains ("_vl.")
                         || s.has_suffix ("-vl")  || s.has_suffix ("_vl")
                         || s.contains ("vision") || s.contains ("visual")) {
                            model.has_vision = true;
                            break;
                        }
                    }
                }

                // Family/name fallback for thinking models
                if (!model.has_thinking) {
                    string[] candidates = {
                        (model.family ?? "").down (),
                        model.name.down (),
                        (model.description ?? "").down ()
                    };
                    foreach (string s in candidates) {
                        if (s == "") continue;
                        if (s.contains ("qwq")
                         || s.contains ("deepseek_r1") || s.contains ("deepseek-r1")
                         || s.has_suffix ("-r1") || s.has_suffix ("_r1")
                         || s.contains ("-r1-") || s.contains ("_r1_")
                         || s.contains ("thinking")) {
                            model.has_thinking = true;
                            break;
                        }
                    }
                }
            } catch (Error e) {
                // Non-GGUF or truncated file — silently ignore
            }
        }

        // ── Helpers ──────────────────────────────────────────────────────

        private static string read_string (GLib.DataInputStream dis, uint32 version) throws Error {
            uint64 len;
            if (version == 1)
                len = (uint64) dis.read_uint32 ();
            else
                len = dis.read_uint64 ();

            if (len == 0) return "";
            if (len > 1048576) throw new IOError.FAILED ("string too long"); // sanity cap

            uint8[] buf = new uint8[len + 1];
            size_t bytes_read;
            dis.read_all (buf[0:len], out bytes_read);
            buf[len] = 0;
            return (string) buf;
        }

        private static void skip_value (GLib.DataInputStream dis, uint32 val_type, uint32 version) throws Error {
            switch (val_type) {
                case GGUF_TYPE_UINT8:
                case GGUF_TYPE_INT8:
                case GGUF_TYPE_BOOL:
                    dis.read_byte ();
                    break;
                case GGUF_TYPE_UINT16:
                case GGUF_TYPE_INT16:
                    dis.read_uint16 ();
                    break;
                case GGUF_TYPE_UINT32:
                case GGUF_TYPE_INT32:
                case GGUF_TYPE_FLOAT32:
                    dis.read_uint32 ();
                    break;
                case GGUF_TYPE_UINT64:
                case GGUF_TYPE_INT64:
                case GGUF_TYPE_FLOAT64:
                    dis.read_uint64 ();
                    break;
                case GGUF_TYPE_STRING:
                    read_string (dis, version);
                    break;
                case GGUF_TYPE_ARRAY:
                    skip_array (dis, version);
                    break;
                default:
                    throw new IOError.FAILED ("unknown GGUF type %u", val_type);
            }
        }

        private static void skip_array (GLib.DataInputStream dis, uint32 version) throws Error {
            uint32 elem_type = dis.read_uint32 ();
            uint64 count;
            if (version == 1)
                count = (uint64) dis.read_uint32 ();
            else
                count = dis.read_uint64 ();

            for (uint64 i = 0; i < count; i++)
                skip_value (dis, elem_type, version);
        }
    }
}

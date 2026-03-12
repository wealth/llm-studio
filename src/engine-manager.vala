namespace LLMStudio {

    public enum GpuVariant {
        NONE,
        CUDA,
        ROCM,
        VULKAN;

        public string to_string () {
            switch (this) {
                case CUDA:   return "cuda";
                case ROCM:   return "rocm";
                case VULKAN: return "vulkan";
                default:     return "none";
            }
        }

        public string label () {
            switch (this) {
                case CUDA:   return "CUDA (NVIDIA)";
                case ROCM:   return "ROCm (AMD)";
                case VULKAN: return "Vulkan";
                default:     return "CPU only";
            }
        }
    }

    public class EngineRelease : Object {
        public string tag          { get; set; default = ""; }
        public string asset_name   { get; set; default = ""; }
        public string download_url { get; set; default = ""; }
        public int64  asset_size   { get; set; default = 0;  }
        public string published_at { get; set; default = ""; }

        public string short_tag () {
            // "b4321" → "b4321", "v0.0.1" → "v0.0.1"
            return tag;
        }
    }

    public class EngineManager : Object {
        private GLib.Settings settings;
        private Soup.Session  session;
        private string        engines_dir;

        private const string GITHUB_API       = "https://api.github.com";
        private const string LLAMA_CPP_REPO   = "ggml-org/llama.cpp";

        public string?  installed_version  { get; private set; default = null; }
        public string   engines_directory  { get { return engines_dir; } }
        public string?  llama_server_path  { owned get { return find_binary ("llama-server"); } }

        public signal void log_line            (string text);
        public signal void download_progress   (int64 downloaded, int64 total);

        public EngineManager (GLib.Settings settings) {
            this.settings = settings;
            this.session  = new Soup.Session ();
            this.session.user_agent = "LLMStudio/0.1";
            this.session.timeout    = 30;

            // Honour settings override, fall back to XDG data dir
            engines_dir = settings.get_string ("engines-directory");
            if (engines_dir == "")
                engines_dir = GLib.Path.build_filename (
                    GLib.Environment.get_home_dir (),
                    ".local", "share", "llm-studio", "engines");

            load_installed_version ();
        }

        // ── Version bookkeeping ──────────────────────────────────────────────

        private string version_file () {
            return GLib.Path.build_filename (engines_dir, "llama.cpp", "version.txt");
        }

        private void load_installed_version () {
            var path = version_file ();
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) return;
            try {
                string data;
                GLib.FileUtils.get_contents (path, out data);
                installed_version = data.strip ();
            } catch (Error e) {
                warning ("Could not read engine version: %s", e.message);
            }
        }

        private void save_installed_version (string tag) {
            installed_version = tag;
            try {
                GLib.FileUtils.set_contents (version_file (), tag);
            } catch (Error e) {
                warning ("Could not write engine version: %s", e.message);
            }
        }

        // ── State queries ────────────────────────────────────────────────────

        public bool engine_installed () {
            var p = llama_server_path;
            return p != null && GLib.FileUtils.test (p, GLib.FileTest.EXISTS);
        }

        public bool is_newer (string latest_tag) {
            if (installed_version == null || installed_version == "") return true;
            return latest_tag != installed_version;
        }

        public GpuVariant detect_gpu () {
            bool has_vulkan = false;
            string[] vulkan_paths = {
                "/usr/lib/x86_64-linux-gnu/libvulkan.so.1",
                "/usr/lib/libvulkan.so.1",
                "/usr/lib64/libvulkan.so.1"
            };
            foreach (var vp in vulkan_paths) {
                if (GLib.FileUtils.test (vp, GLib.FileTest.EXISTS)) {
                    has_vulkan = true;
                    break;
                }
            }

            // Official llama.cpp releases do NOT ship a Linux CUDA build.
            // For NVIDIA on Linux, the Vulkan build is the best official option.
            if (GLib.FileUtils.test ("/dev/nvidia0", GLib.FileTest.EXISTS))
                return has_vulkan ? GpuVariant.VULKAN : GpuVariant.NONE;

            // AMD ROCm: /dev/kfd is the compute device node
            if (GLib.FileUtils.test ("/dev/kfd", GLib.FileTest.EXISTS))
                return GpuVariant.ROCM;

            if (has_vulkan)
                return GpuVariant.VULKAN;

            return GpuVariant.NONE;
        }

        // ── GitHub API ───────────────────────────────────────────────────────

        public async EngineRelease? check_latest (
            GpuVariant gpu = GpuVariant.NONE,
            GLib.Cancellable? cancel = null
        ) throws Error {
            var url = "%s/repos/%s/releases/latest".printf (GITHUB_API, LLAMA_CPP_REPO);
            var msg = new Soup.Message ("GET", url);
            msg.request_headers.replace ("Accept", "application/vnd.github.v3+json");

            var bytes  = yield session_fetch (msg, cancel);
            var data   = bytes.get_data ();
            var parser = new Json.Parser ();
            parser.load_from_data ((string) data, (ssize_t) data.length);
            var root = parser.get_root ();

            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                throw new IOError.FAILED ("Unexpected GitHub API response");

            var obj = root.get_object ();
            if (obj.has_member ("message"))
                throw new IOError.FAILED ("GitHub API: " + obj.get_string_member ("message"));

            var release       = new EngineRelease ();
            release.tag          = obj.get_string_member ("tag_name");
            release.published_at = obj.has_member ("published_at") ?
                obj.get_string_member ("published_at") : "";

            var arch = detect_arch ();
            log_line ("Platform arch: %s".printf (arch));

            // Find the best matching asset zip
            if (obj.has_member ("assets")) {
                obj.get_array_member ("assets").foreach_element ((arr, i, node) => {
                    if (node.get_node_type () != Json.NodeType.OBJECT) return;
                    if (release.download_url != "") return; // already found
                    var asset = node.get_object ();
                    var name  = asset.get_string_member ("name");
                    if (asset_matches (name, arch, gpu)) {
                        release.asset_name   = name;
                        release.download_url = asset.get_string_member ("browser_download_url");
                        release.asset_size   = asset.get_int_member ("size");
                        log_line ("Found asset: " + name);
                    }
                });
            }

            if (release.download_url == "") {
                log_line ("Warning: no matching asset found in release %s".printf (release.tag));
                return null;
            }

            return release;
        }

        private string detect_arch () {
            try {
                var proc = new GLib.Subprocess.newv (
                    new string[] {"uname", "-m"},
                    GLib.SubprocessFlags.STDOUT_PIPE);
                var ds   = new GLib.DataInputStream (proc.get_stdout_pipe ());
                var line = ds.read_line ();
                if (line != null) {
                    var a = line.strip ().down ();
                    // Match asset naming: x64 for x86_64, arm64 for aarch64
                    if (a.contains ("aarch64") || a.contains ("arm64")) return "arm64";
                    if (a.contains ("x86_64")  || a.contains ("amd64")) return "x64";
                }
            } catch (Error e) {}
            return "x64";
        }

        private bool asset_matches (string name, string arch, GpuVariant gpu) {
            bool is_archive = name.has_suffix (".tar.gz") || name.has_suffix (".zip");
            if (!is_archive)           return false;
            if (!name.contains (arch)) return false;

            switch (gpu) {
                case GpuVariant.CUDA:
                    return name.contains ("cuda") &&
                           (name.contains ("ubuntu") || name.contains ("linux"));
                case GpuVariant.ROCM:
                    return name.contains ("rocm") &&
                           (name.contains ("ubuntu") || name.contains ("linux"));
                case GpuVariant.VULKAN:
                    return name.contains ("vulkan") &&
                           (name.contains ("ubuntu") || name.contains ("linux"));
                default: // NONE — CPU only
                    if (name.contains ("cuda"))    return false;
                    if (name.contains ("rocm"))    return false;
                    if (name.contains ("vulkan"))  return false;
                    if (name.contains ("kompute")) return false;
                    if (name.contains ("sycl"))    return false;
                    if (name.contains ("opencl"))  return false;
                    return name.contains ("ubuntu") || name.contains ("linux");
            }
        }

        // ── Install / Update ─────────────────────────────────────────────────

        public async void install_release (
            EngineRelease     release,
            GLib.Cancellable? cancel = null
        ) throws Error {
            var install_dir = GLib.Path.build_filename (engines_dir, "llama.cpp");
            var zip_path    = GLib.Path.build_filename (engines_dir, release.asset_name);

            GLib.DirUtils.create_with_parents (install_dir, 0755);

            // 1. Download
            log_line ("Downloading %s…".printf (release.asset_name));
            yield download_to_file (release.download_url, zip_path, release.asset_size, cancel);

            if (cancel != null && cancel.is_cancelled ()) {
                try { GLib.FileUtils.unlink (zip_path); } catch (Error e) {}
                throw new IOError.CANCELLED ("Download cancelled");
            }

            // 2. Extract
            log_line ("Extracting archive…");
            if (release.asset_name.has_suffix (".tar.gz"))
                yield extract_targz (zip_path, install_dir, cancel);
            else
                yield extract_zip (zip_path, install_dir, cancel);

            // 3. Clean up zip
            try { GLib.FileUtils.unlink (zip_path); } catch (Error e) {}

            // 4. chmod +x on all files that look like executables
            mark_executables (install_dir);

            // 5. Record version
            save_installed_version (release.tag);

            // 6. Update settings path
            var server = llama_server_path;
            if (server != null) {
                settings.set_string ("llama-server-path",    server);
                settings.set_string ("ik-llama-server-path", server);
                log_line ("Engine ready: " + server);
            } else {
                throw new IOError.FAILED (
                    "Could not find llama-server binary after extraction. " +
                    "Files were placed in: " + install_dir);
            }
        }

        private async void download_to_file (
            string            url,
            string            dest,
            int64             known_size,
            GLib.Cancellable? cancel
        ) throws Error {
            var msg = new Soup.Message ("GET", url);
            var istream = yield session.send_async (msg, GLib.Priority.DEFAULT, cancel);
            if (msg.status_code >= 400)
                throw new IOError.FAILED ("HTTP %u fetching release asset".printf (msg.status_code));

            int64 total = known_size > 0 ? known_size :
                msg.response_headers.get_content_length ();

            var file    = GLib.File.new_for_path (dest);
            var ostream = yield file.replace_async (null, false,
                GLib.FileCreateFlags.REPLACE_DESTINATION,
                GLib.Priority.DEFAULT, cancel);

            var buf    = new uint8[65536];
            int64 done = 0;
            while (cancel == null || !cancel.is_cancelled ()) {
                ssize_t n = yield istream.read_async (buf, GLib.Priority.DEFAULT, cancel);
                if (n <= 0) break;
                yield ostream.write_all_async (buf[0:n], GLib.Priority.DEFAULT, cancel, null);
                done += n;
                download_progress (done, total);
            }
            yield ostream.close_async ();
            yield istream.close_async ();
        }

        private async void extract_targz (
            string            archive_path,
            string            dest_dir,
            GLib.Cancellable? cancel
        ) throws Error {
            // --strip-components=1 handles releases that wrap everything in a top-level dir
            string[] cmd = {"tar", "-xzf", archive_path, "-C", dest_dir, "--strip-components=1"};
            log_line ("Running: " + string.joinv (" ", cmd));

            var proc = new GLib.Subprocess.newv (
                cmd,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);

            var ds = new GLib.DataInputStream (proc.get_stdout_pipe ());
            string? line;
            while ((line = yield ds.read_line_async (GLib.Priority.DEFAULT, cancel)) != null)
                log_line (line);

            yield proc.wait_async (cancel);
            int exit_code = proc.get_exit_status ();
            if (exit_code != 0) {
                // Retry without --strip-components in case it's a flat archive
                log_line ("Retrying without --strip-components…");
                string[] cmd2 = {"tar", "-xzf", archive_path, "-C", dest_dir};
                var proc2 = new GLib.Subprocess.newv (
                    cmd2,
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
                var ds2 = new GLib.DataInputStream (proc2.get_stdout_pipe ());
                while ((line = yield ds2.read_line_async (GLib.Priority.DEFAULT, cancel)) != null)
                    log_line (line);
                yield proc2.wait_check_async (cancel);
            }
        }

        private async void extract_zip (
            string            zip_path,
            string            dest_dir,
            GLib.Cancellable? cancel
        ) throws Error {
            // Try unzip first, fall back to python3
            string[] unzip_cmd = {"unzip", "-o", "-j", zip_path, "-d", dest_dir};

            // -j = junk paths (flat extract), so all files land directly in dest_dir
            log_line ("Running: " + string.joinv (" ", unzip_cmd));

            var proc = new GLib.Subprocess.newv (
                unzip_cmd,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);

            var ds = new GLib.DataInputStream (proc.get_stdout_pipe ());
            string? line;
            while ((line = yield ds.read_line_async (GLib.Priority.DEFAULT, cancel)) != null)
                log_line (line);

            yield proc.wait_async (cancel);
            int exit_code = proc.get_exit_status ();

            if (exit_code != 0) {
                // Fallback: try python3 zipfile module
                log_line ("unzip failed (exit %d), trying python3…".printf (exit_code));
                yield extract_zip_python (zip_path, dest_dir, cancel);
            }
        }

        private async void extract_zip_python (
            string zip_path, string dest_dir, GLib.Cancellable? cancel
        ) throws Error {
            var script = """
import zipfile, os, sys
with zipfile.ZipFile(sys.argv[1]) as z:
    for m in z.infolist():
        m.filename = os.path.basename(m.filename)
        if m.filename:
            z.extract(m, sys.argv[2])
""";
            var proc = new GLib.Subprocess.newv (
                new string[] {"python3", "-c", script, zip_path, dest_dir},
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);

            var ds = new GLib.DataInputStream (proc.get_stdout_pipe ());
            string? line;
            while ((line = yield ds.read_line_async (GLib.Priority.DEFAULT, cancel)) != null)
                log_line (line);

            yield proc.wait_check_async (cancel);
        }

        private void mark_executables (string dir) {
            // Walk directory and chmod +x anything that has no extension or is a known binary
            try {
                var d = GLib.Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (name.has_suffix (".txt") ||
                        name.has_suffix (".md")  ||
                        name.has_suffix (".so")  ||
                        name.has_suffix (".dll")) continue;
                    var path = GLib.Path.build_filename (dir, name);
                    if (GLib.FileUtils.test (path, GLib.FileTest.IS_REGULAR)) {
                        // Check ELF magic bytes
                        if (is_elf (path)) {
                            try {
                                new GLib.Subprocess.newv (
                                    new string[] {"chmod", "+x", path},
                                    GLib.SubprocessFlags.NONE);
                                log_line ("chmod +x " + name);
                            } catch (Error e) {}
                        }
                    }
                }
            } catch (Error e) {
                warning ("mark_executables: %s", e.message);
            }
        }

        private bool is_elf (string path) {
            try {
                var f  = GLib.File.new_for_path (path);
                var is = f.read ();
                var buf = new uint8[4];
                is.read (buf);
                is.close ();
                // ELF magic: 0x7f 'E' 'L' 'F'
                return buf[0] == 0x7f && buf[1] == 'E' && buf[2] == 'L' && buf[3] == 'F';
            } catch (Error e) {
                return false;
            }
        }

        private string? find_binary (string name) {
            var base_dir = GLib.Path.build_filename (engines_dir, "llama.cpp");
            // Try flat in base dir
            var exact = GLib.Path.build_filename (base_dir, name);
            if (GLib.FileUtils.test (exact, GLib.FileTest.EXISTS)) return exact;
            // Try one level deep (in case tar extracted into a subdirectory)
            try {
                var d = GLib.Dir.open (base_dir);
                string? entry;
                while ((entry = d.read_name ()) != null) {
                    var sub = GLib.Path.build_filename (base_dir, entry, name);
                    if (GLib.FileUtils.test (sub, GLib.FileTest.EXISTS)) return sub;
                }
            } catch {}
            return null;
        }

        // ── Helpers ──────────────────────────────────────────────────────────

        private async GLib.Bytes session_fetch (
            Soup.Message msg, GLib.Cancellable? cancel
        ) throws Error {
            var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancel);
            if (msg.status_code == 0)
                throw new IOError.FAILED ("No response from server (TLS or network error)");
            if (msg.status_code >= 400)
                throw new IOError.FAILED ("HTTP %u".printf (msg.status_code));
            return bytes;
        }
    }
}

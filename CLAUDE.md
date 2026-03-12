# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Configure (first time or after dependency changes)
meson setup build --buildtype=debugoptimized

# Build
ninja -C build

# Set up GSettings schema (required before running)
mkdir -p ~/.local/share/glib-2.0/schemas
cp data/dev.llmstudio.LLMStudio.gschema.xml ~/.local/share/glib-2.0/schemas/
glib-compile-schemas ~/.local/share/glib-2.0/schemas/

# Run
GSETTINGS_SCHEMA_DIR="$HOME/.local/share/glib-2.0/schemas" ./build/src/llm-studio
```

No test suite exists. Validate changes by building and running the app.

## Project Overview

GTK4/Libadwaita/Vala LM Studio clone. App ID: `dev.llmstudio.LLMStudio`.

## Dependencies

- gtk4, libadwaita-1, json-glib-1.0
- **libsoup-2.4** (NOT soup-3.0 — the system has 2.74.3 only; used for HTTP client/server)
- **webkitgtk-6.0** (GTK4 WebKit — for chat rendering; `libwebkitgtk-6.0-dev`)
- **libcmark** (CommonMark markdown→HTML; `libcmark-dev`)
- **libjs-katex + fonts-katex** (KaTeX for LaTeX math; installed to `/usr/share/javascript/katex/`)
- glib-2.0 ≥ 2.76

### Soup isolation (important)
`webkitgtk-6.0` internally uses `libsoup-3.0` whose headers conflict with `libsoup-2.4`. To avoid this, webkit and cmark are compiled in an **isolated static library** (`libllmstudio-glue.a`) that has no soup-2.4 in its include path. The main executable receives only link flags (`-lwebkitgtk-6.0 -lcmark`), not their compile flags. See `src/meson.build`.

## Architecture

**Startup flow**: `main.vala` → `Application` (creates all subsystems) → `Window` (wires UI to subsystems)

**Subsystems** (all created in `application.vala`, passed to `Window`):
- `ModelManager` — scans directories for GGUF/SafeTensors models, stores per-model params in `.llmstudio.json` sidecar files
- `BackendManager` — manages the active inference backend; emits signals (`status_changed`, `model_loaded`, `chunk_received`, etc.)
- `HFClient` — HuggingFace REST API client for model search and download
- `OpenAIServer` — Soup.Server-based OpenAI-compatible HTTP API (non-streaming)
- `EngineManager` — downloads/manages llama.cpp binary releases from GitHub
- `ChatHistory` — conversation persistence

**Backends** (`src/backend/`):
- `LlamaBackend` — spawns `llama-server` subprocess on a random port (8080–8180), communicates via HTTP
- `IKLlamaBackend` — same pattern for ik_llama.cpp fork
- `VllmBackend` — connects to existing vLLM server or spawns it
- `BackendManager` handles switching between backends (unload old → load new)

**UI** (`src/ui/`): `AdwApplicationWindow` → `AdwToastOverlay` → `AdwToolbarView` → `AdwOverlaySplitView`. Left: `Sidebar` (nav buttons) + model status. Right: `Gtk.Stack` with 5 pages (Chat, Models, Hub, Server, Logs).

**Chat rendering** (`src/ui/chat-view.vala`): Single `WebKit.WebView` renders the entire conversation as HTML. During streaming, tokens are appended via `llm_webkit_run_js()` JS calls. When streaming ends, `HtmlRenderer.render_markdown()` (libcmark) converts the full response to HTML and `renderMathInElement()` (KaTeX) renders any `$...$` or `$$...$$` LaTeX. Think blocks (`<think>...</think>`) are shown live during streaming and collapsed into a `<details>` element on completion. `src/utils/html-renderer.vala` owns the CSS, JS, and page template; `src/ui/webkit-glue.c` and `src/utils/cmark-glue.c` are the isolated C wrappers.

## Vala / libsoup-2.4 Gotchas

- `Adw.Spinner` doesn't exist → use `Gtk.Spinner`
- Underscore numeric literals (`1_000_000`) fail in float context → use `1000000.0`
- `ref` params not allowed in async methods → use member variables or return new values
- `GLib.List<T>` as a property causes "duplicating list" errors → use fields instead
- `GLib.List.copy()` returns `unowned` → caller must use `(owned)` or `unowned`
- `uri.get_port()` returns `uint` → cast to `int`
- No `send_and_read_async` in soup-2.4 → use `send_async` + `MemoryOutputStream.splice_async`
- `send_async(msg, cancellable)` — no priority parameter
- Server handlers need `Soup.ClientContext client` as last parameter
- Use `msg.status_code` (property, not `get_status()`) and `msg.method` (not `get_method()`)
- Use `server.pause_message(msg)` / `server.unpause_message(msg)` for async server responses

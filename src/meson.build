sources = files(
  # Entry point
  'main.vala',
  'application.vala',
  'window.vala',

  # Engine management
  'engine-manager.vala',

  # Utilities
  'utils/html-renderer.vala',

  # Data models
  'models/model-info.vala',
  'models/gguf-reader.vala',
  'models/model-manager.vala',
  'models/chat-history.vala',

  # HuggingFace integration
  'huggingface/hf-model.vala',
  'huggingface/hf-client.vala',

  # Tools
  'tools/tool-manager.vala',

  # Inference backends
  'backend/backend.vala',
  'backend/backend-manager.vala',
  'backend/llama-backend.vala',
  'backend/vllm-backend.vala',

  # OpenAI-compatible API server
  'api/openai-server.vala',

  # UI components
  'ui/sidebar.vala',
  'ui/chat-sidebar-panel.vala',
  'ui/chat-view.vala',
  'ui/chat-params-panel.vala',
  'ui/model-browser.vala',
  'ui/model-settings-panel.vala',
  'ui/model-load-dialog.vala',
  'ui/model-picker-dialog.vala',
  'ui/server-panel.vala',
  'ui/preferences-dialog.vala',
  'ui/download-view.vala',
  'ui/logs-view.vala',
  'ui/engine-dialog.vala',
)

resources = gnome.compile_resources(
  'llm-studio-resources',
  '../data/llm-studio.gresource.xml',
  source_dir: '../data',
)

# C glue static library — compiled with webkitgtk-6.0 and cmark-gfm deps.
glue_inc = include_directories('.')
glue_lib = static_library(
  'llmstudio-glue',
  files('ui/webkit-glue.c', 'utils/cmark-glue.c'),
  include_directories: glue_inc,
  dependencies: [gtk4_dep, webkit_dep, cmark_dep, cmark_ext_dep],
)

executable(
  'llm-studio',
  sources, resources,
  vala_args: [
    '--pkg', 'gtk4',
    '--pkg', 'libadwaita-1',
    '--pkg', 'libsoup-3.0',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gobject-2.0',
    '--target-glib=2.76',
    '--enable-experimental',
  ],
  c_args: [
    '-I' + meson.current_source_dir(),
    '-I' + meson.current_source_dir() / 'ui',
    '-I' + meson.current_source_dir() / 'utils',
  ],
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_dep,
    gtk4_dep,
    adw_dep,
    soup3_dep,
    json_glib_dep,
    webkit_link,
    cmark_link,
    cmark_ext_link,
  ],
  link_with: [glue_lib],
  install: true,
)

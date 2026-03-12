project('llm-studio', 'vala', 'c',
  version: '0.1.0',
  meson_version: '>= 0.62.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ]
)

gnome = import('gnome')
cc    = meson.get_compiler('c')

glib_dep       = dependency('glib-2.0',       version: '>= 2.76')
gobject_dep    = dependency('gobject-2.0',    version: '>= 2.76')
gio_dep        = dependency('gio-2.0',        version: '>= 2.76')
gtk4_dep       = dependency('gtk4',           version: '>= 4.12')
adw_dep        = dependency('libadwaita-1',   version: '>= 1.4')
soup3_dep      = dependency('libsoup-3.0',    version: '>= 3.0')
json_glib_dep  = dependency('json-glib-1.0',  version: '>= 1.6')

# Full deps used only when compiling the isolated C glue static library.
webkit_dep          = dependency('webkitgtk-6.0')
cmark_dep           = dependency('libcmark-gfm')
cmark_ext_dep       = cc.find_library('cmark-gfm-extensions',
                        dirs: ['/usr/lib/x86_64-linux-gnu',
                               '/usr/lib/aarch64-linux-gnu',
                               '/usr/lib'])

# Link-only deps for the main executable (no -I flags).
webkit_link         = cc.find_library('webkitgtk-6.0')
cmark_link          = cc.find_library('cmark-gfm')
cmark_ext_link      = cmark_ext_dep

subdir('data')
subdir('src')

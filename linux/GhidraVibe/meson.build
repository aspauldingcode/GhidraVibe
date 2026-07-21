project('ghidra-vibe', 'c',
  version: '0.1.0',
  default_options: ['warning_level=2', 'c_std=c11'])

cc = meson.get_compiler('c')

gtk = dependency('gtk4', version: '>=4.10')
adw = dependency('libadwaita-1', version: '>=1.4')
json = dependency('json-glib-1.0')
soup = dependency('libsoup-3.0', required: false)
webkit = dependency('webkitgtk-6.0', required: false)
# graph_view.c uses hypot()/sqrt(); glibc splits these into libm.
libm = cc.find_library('m', required: false)

help_deps = [gtk, adw, json, libm]
if webkit.found()
  help_deps += webkit
endif

executable('ghidra-vibe',
  sources: [
    'src/main.c',
    'src/a11y.c',
    'src/dock.c',
    'src/mcp_client.c',
    'src/stock_tools.c',
    'src/graph_view.c',
    'src/help_view.c',
    'src/splash.c',
    'src/theme.c',
    'src/dsc_setup.c',
  ],
  dependencies: help_deps,
  c_args: webkit.found() ? ['-DHAVE_WEBKIT=1'] : [],
  install: true,
)

install_data('data/ghidra-vibe.desktop',
  install_dir: get_option('datadir') / 'applications')

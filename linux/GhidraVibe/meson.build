project('ghidra-vibe', 'c',
  version: '0.1.0',
  default_options: ['warning_level=2', 'c_std=c11'])

gtk = dependency('gtk4', version: '>=4.10')
adw = dependency('libadwaita-1', version: '>=1.4')
json = dependency('json-glib-1.0')
soup = dependency('libsoup-3.0', required: false)

conf = configuration_data()
conf.set_quoted('GHIDRA_VIBE_DATADIR', get_option('prefix') / get_option('datadir') / 'ghidra-vibe')

executable('ghidra-vibe',
  sources: [
    'src/main.c',
    'src/a11y.c',
    'src/dock.c',
    'src/mcp_client.c',
    'src/stock_tools.c',
    'src/graph_view.c',
  ],
  dependencies: [gtk, adw, json],
  install: true,
)

install_data('data/ghidra-vibe.desktop',
  install_dir: get_option('datadir') / 'applications')

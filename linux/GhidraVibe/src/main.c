/* GhidraVibe GTK — CodeBrowser / Project Window docking shell (native, not Swing). */
#include "a11y.h"
#include "dock.h"
#include "dsc_setup.h"
#include "help_view.h"
#include "mcp_client.h"
#include "splash.h"
#include "stock_tools.h"
#include "theme.h"

#include <adwaita.h>
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  GtkWidget *stack;
  GtkWidget *status;
  GtkWidget *mcp_chip;
  char *mcp_url;
} AppState;

static char *find_data_file(const char *name) {
  const char *env = g_getenv("GHIDRA_VIBE_UI_DATA");
  if (env) {
    char *p = g_build_filename(env, name, NULL);
    if (g_file_test(p, G_FILE_TEST_EXISTS))
      return p;
    g_free(p);
  }
  const char *candidates[] = {
      "native-ui",
      "../native-ui",
      "../../native-ui",
      "/usr/share/ghidra-vibe",
      NULL,
  };
  for (int i = 0; candidates[i]; i++) {
    char *p = g_build_filename(candidates[i], name, NULL);
    if (g_file_test(p, G_FILE_TEST_EXISTS))
      return p;
    g_free(p);
    if (strstr(name, "/")) {
      char *base = g_path_get_basename(name);
      p = g_build_filename(candidates[i], base, NULL);
      g_free(base);
      if (g_file_test(p, G_FILE_TEST_EXISTS))
        return p;
      g_free(p);
    }
  }
  return NULL;
}

static void set_status(AppState *st, const char *msg) {
  gtk_label_set_text(GTK_LABEL(st->status), msg);
}

static void on_mcp_health(GSimpleAction *action, GVariant *param, gpointer data) {
  (void)action;
  (void)param;
  AppState *st = data;
  char *r = vibe_mcp_check(st->mcp_url);
  gtk_label_set_text(GTK_LABEL(st->mcp_chip), r);
  set_status(st, r);
  g_free(r);
}

static void show_page(AppState *st, const char *name) {
  gtk_stack_set_visible_child_name(GTK_STACK(st->stack), name);
  set_status(st, name);
}

#define SHOW_FN(name, page)                                                                            \
  static void on_##name(GSimpleAction *a, GVariant *p, gpointer data) {                                \
    (void)a;                                                                                           \
    (void)p;                                                                                           \
    show_page(data, page);                                                                             \
  }

SHOW_FN(show_project, "project")
SHOW_FN(show_codebrowser, "codebrowser")
SHOW_FN(show_debugger, "debugger")
SHOW_FN(show_emulator, "emulator")
SHOW_FN(show_version_tracking, "version_tracking")
SHOW_FN(show_mcp, "mcp")
SHOW_FN(show_agent, "agent")
SHOW_FN(show_rag, "rag")
SHOW_FN(show_rules, "rules")
SHOW_FN(show_dsc, "dsc")
SHOW_FN(show_functions, "functions")
SHOW_FN(show_strings, "strings")
SHOW_FN(show_memory_map, "memory_map")
SHOW_FN(show_symbol_table, "symbol_table")
SHOW_FN(show_bytes, "bytes")
SHOW_FN(show_bookmarks, "bookmarks")
SHOW_FN(show_script_manager, "script_manager")
SHOW_FN(show_function_graph, "function_graph")
SHOW_FN(show_entropy, "entropy")
SHOW_FN(show_overview, "overview")
SHOW_FN(show_registers, "registers")
SHOW_FN(show_python, "python")
SHOW_FN(show_comments, "comments")
SHOW_FN(show_checksum, "checksum")
SHOW_FN(show_equates, "equates")
SHOW_FN(show_relocations, "relocations")
SHOW_FN(show_defined_data, "defined_data")
SHOW_FN(show_external_programs, "external_programs")
SHOW_FN(show_datatype_preview, "datatype_preview")
SHOW_FN(show_disassembled_view, "disassembled_view")
SHOW_FN(show_symbol_references, "symbol_references")
SHOW_FN(show_function_tags, "function_tags")
SHOW_FN(show_apple, "apple_bundle")
SHOW_FN(show_swift_classes, "swift_classes")
SHOW_FN(show_code_editor, "code_editor")

static void on_show_help(GSimpleAction *a, GVariant *p, gpointer data) {
  (void)a;
  (void)p;
  AppState *st = data;
  GtkWindow *win = NULL;
  if (st && st->stack) {
    GtkRoot *root = gtk_widget_get_root(st->stack);
    if (GTK_IS_WINDOW(root))
      win = GTK_WINDOW(root);
  }
  vibe_help_show(win);
}

static void on_show_theme_picker(GSimpleAction *a, GVariant *p, gpointer data) {
  (void)a;
  (void)p;
  AppState *st = data;
  GtkWindow *win = NULL;
  if (st && st->stack) {
    GtkRoot *root = gtk_widget_get_root(st->stack);
    if (GTK_IS_WINDOW(root))
      win = GTK_WINDOW(root);
  }
  vibe_theme_show_picker(win);
}

static void on_show_dsc_setup(GSimpleAction *a, GVariant *p, gpointer data) {
  (void)a;
  (void)p;
  AppState *st = data;
  GtkWindow *win = NULL;
  if (st && st->stack) {
    GtkRoot *root = gtk_widget_get_root(st->stack);
    if (GTK_IS_WINDOW(root))
      win = GTK_WINDOW(root);
  }
  vibe_dsc_show_setup_dialog(win);
}

static void add_menu(GtkApplication *app, AppState *st) {
  const GActionEntry entries[] = {
      {"show_project", on_show_project, NULL, NULL, NULL, {0}},
      {"show_codebrowser", on_show_codebrowser, NULL, NULL, NULL, {0}},
      {"show_debugger", on_show_debugger, NULL, NULL, NULL, {0}},
      {"show_emulator", on_show_emulator, NULL, NULL, NULL, {0}},
      {"show_version_tracking", on_show_version_tracking, NULL, NULL, NULL, {0}},
      {"show_mcp", on_show_mcp, NULL, NULL, NULL, {0}},
      {"show_agent", on_show_agent, NULL, NULL, NULL, {0}},
      {"show_rag", on_show_rag, NULL, NULL, NULL, {0}},
      {"show_rules", on_show_rules, NULL, NULL, NULL, {0}},
      {"show_dsc", on_show_dsc, NULL, NULL, NULL, {0}},
      {"show_functions", on_show_functions, NULL, NULL, NULL, {0}},
      {"show_strings", on_show_strings, NULL, NULL, NULL, {0}},
      {"show_memory_map", on_show_memory_map, NULL, NULL, NULL, {0}},
      {"show_symbol_table", on_show_symbol_table, NULL, NULL, NULL, {0}},
      {"show_bytes", on_show_bytes, NULL, NULL, NULL, {0}},
      {"show_bookmarks", on_show_bookmarks, NULL, NULL, NULL, {0}},
      {"show_script_manager", on_show_script_manager, NULL, NULL, NULL, {0}},
      {"show_function_graph", on_show_function_graph, NULL, NULL, NULL, {0}},
      {"show_entropy", on_show_entropy, NULL, NULL, NULL, {0}},
      {"show_overview", on_show_overview, NULL, NULL, NULL, {0}},
      {"show_registers", on_show_registers, NULL, NULL, NULL, {0}},
      {"show_python", on_show_python, NULL, NULL, NULL, {0}},
      {"show_comments", on_show_comments, NULL, NULL, NULL, {0}},
      {"show_checksum", on_show_checksum, NULL, NULL, NULL, {0}},
      {"show_equates", on_show_equates, NULL, NULL, NULL, {0}},
      {"show_relocations", on_show_relocations, NULL, NULL, NULL, {0}},
      {"show_defined_data", on_show_defined_data, NULL, NULL, NULL, {0}},
      {"show_external_programs", on_show_external_programs, NULL, NULL, NULL, {0}},
      {"show_datatype_preview", on_show_datatype_preview, NULL, NULL, NULL, {0}},
      {"show_disassembled_view", on_show_disassembled_view, NULL, NULL, NULL, {0}},
      {"show_symbol_references", on_show_symbol_references, NULL, NULL, NULL, {0}},
      {"show_function_tags", on_show_function_tags, NULL, NULL, NULL, {0}},
      {"show_apple", on_show_apple, NULL, NULL, NULL, {0}},
      {"show_swift_classes", on_show_swift_classes, NULL, NULL, NULL, {0}},
      {"show_code_editor", on_show_code_editor, NULL, NULL, NULL, {0}},
      {"mcp_health", on_mcp_health, NULL, NULL, NULL, {0}},
      {"show_help", on_show_help, NULL, NULL, NULL, {0}},
      {"show_theme_picker", on_show_theme_picker, NULL, NULL, NULL, {0}},
      {"show_dsc_setup", on_show_dsc_setup, NULL, NULL, NULL, {0}},
  };
  g_action_map_add_action_entries(G_ACTION_MAP(app), entries, G_N_ELEMENTS(entries), st);

  GMenu *menubar = g_menu_new();

  GMenu *file = g_menu_new();
  g_menu_append(file, "Open Project…", "app.show_project");
  g_menu_append(file, "Import File…", "app.show_project");
  g_menu_append(file, "Open Framework from Shared Cache…", "app.show_dsc");
  g_menu_append(file, "Open App Bundle…", "app.show_apple");
  g_menu_append(file, "Analyze App Bundle…", "app.show_apple");
  g_menu_append(file, "Browse Shared Cache…", "app.show_dsc");
  g_menu_append_submenu(menubar, "File", G_MENU_MODEL(file));

  GMenu *edit = g_menu_new();
  g_menu_append(edit, "Undo", "app.show_codebrowser");
  g_menu_append(edit, "Redo", "app.show_codebrowser");
  g_menu_append_submenu(menubar, "Edit", G_MENU_MODEL(edit));

  GMenu *analysis = g_menu_new();
  g_menu_append(analysis, "Auto Analyze…", "app.show_codebrowser");
  g_menu_append_submenu(menubar, "Analysis", G_MENU_MODEL(analysis));

  GMenu *bsim = g_menu_new();
  g_menu_append(bsim, "BSim Search…", "app.show_functions");
  g_menu_append(bsim, "BSim Overview", "app.show_functions");
  g_menu_append_submenu(menubar, "BSim", G_MENU_MODEL(bsim));

  GMenu *graph = g_menu_new();
  g_menu_append(graph, "Function Graph", "app.show_function_graph");
  g_menu_append_submenu(menubar, "Graph", G_MENU_MODEL(graph));

  GMenu *nav = g_menu_new();
  g_menu_append(nav, "Go To…", "app.show_codebrowser");
  g_menu_append(nav, "Previous Location", "app.show_codebrowser");
  g_menu_append(nav, "Next Location", "app.show_codebrowser");
  g_menu_append_submenu(menubar, "Navigation", G_MENU_MODEL(nav));

  GMenu *search = g_menu_new();
  g_menu_append(search, "For Strings…", "app.show_strings");
  g_menu_append(search, "For Functions…", "app.show_functions");
  g_menu_append(search, "Memory…", "app.show_codebrowser");
  g_menu_append_submenu(menubar, "Search", G_MENU_MODEL(search));

  GMenu *select = g_menu_new();
  g_menu_append(select, "Clear Selection", "app.show_codebrowser");
  g_menu_append_submenu(menubar, "Select", G_MENU_MODEL(select));

  GMenu *tools = g_menu_new();
  g_menu_append(tools, "Start Analysis MCP", "app.show_mcp");
  g_menu_append(tools, "MCP Health", "app.mcp_health");
  g_menu_append(tools, "CodeBrowser", "app.show_codebrowser");
  g_menu_append(tools, "Debugger", "app.show_debugger");
  g_menu_append(tools, "Emulator", "app.show_emulator");
  g_menu_append(tools, "Version Tracking", "app.show_version_tracking");
  g_menu_append(tools, "DSC/IPSW Setup…", "app.show_dsc_setup");
  g_menu_append(tools, "Theme Settings…", "app.show_theme_picker");
  g_menu_append_submenu(menubar, "Tools", G_MENU_MODEL(tools));

  GMenu *window = g_menu_new();
  g_menu_append(window, "Project Window", "app.show_project");
  g_menu_append(window, "CodeBrowser", "app.show_codebrowser");
  g_menu_append(window, "Entropy", "app.show_entropy");
  g_menu_append(window, "Overview", "app.show_overview");
  g_menu_append(window, "Bytes", "app.show_bytes");
  g_menu_append(window, "Defined Data", "app.show_defined_data");
  g_menu_append(window, "Defined Strings", "app.show_strings");
  g_menu_append(window, "Equates Table", "app.show_equates");
  g_menu_append(window, "External Programs", "app.show_external_programs");
  g_menu_append(window, "Functions", "app.show_functions");
  g_menu_append(window, "Relocation Table", "app.show_relocations");
  g_menu_append(window, "Data Type Preview", "app.show_datatype_preview");
  g_menu_append(window, "Disassembled View", "app.show_disassembled_view");
  g_menu_append(window, "Bookmarks", "app.show_bookmarks");
  g_menu_append(window, "Script Manager", "app.show_script_manager");
  g_menu_append(window, "Memory Map", "app.show_memory_map");
  g_menu_append(window, "Function Graph", "app.show_function_graph");
  g_menu_append(window, "Register Manager", "app.show_registers");
  g_menu_append(window, "Symbol Table", "app.show_symbol_table");
  g_menu_append(window, "Symbol References", "app.show_symbol_references");
  g_menu_append(window, "Checksum Generator", "app.show_checksum");
  g_menu_append(window, "Function Tags", "app.show_function_tags");
  g_menu_append(window, "Comments", "app.show_comments");
  g_menu_append(window, "Python", "app.show_python");
  g_menu_append(window, "MCP", "app.show_mcp");
  g_menu_append(window, "Agent", "app.show_agent");
  g_menu_append(window, "RAG / JSpace", "app.show_rag");
  g_menu_append(window, "Rules", "app.show_rules");
  g_menu_append(window, "Shared Cache", "app.show_dsc");
  g_menu_append(window, "App Bundle", "app.show_apple");
  g_menu_append(window, "Classes", "app.show_swift_classes");
  g_menu_append(window, "Code Editor", "app.show_code_editor");
  g_menu_append_submenu(menubar, "Window", G_MENU_MODEL(window));

  GMenu *help = g_menu_new();
  g_menu_append(help, "Ghidra Help…", "app.show_help");
  g_menu_append(help, "About GhidraVibe", "app.show_project");
  g_menu_append_submenu(menubar, "Help", G_MENU_MODEL(help));

  gtk_application_set_menubar(app, G_MENU_MODEL(menubar));
}

static GtkWidget *vibe_panel(const char *title, const char *id) {
  /* Map stack pages to the same MCP tools as macOS providers. */
  if (g_strcmp0(id, "ghidra.vibe.provider.functions") == 0)
    return vibe_provider_mcp(title, id, "list_functions", FALSE);
  if (g_strcmp0(id, "ghidra.vibe.provider.strings") == 0)
    return vibe_provider_mcp(title, id, "list_strings", FALSE);
  if (g_strcmp0(id, "ghidra.vibe.provider.memory_map") == 0)
    return vibe_provider_mcp(title, id, "list_segments", FALSE);
  if (g_strcmp0(id, "ghidra.vibe.provider.symbol_table") == 0)
    return vibe_provider_mcp(title, id, "list_exports", FALSE);
  if (g_strcmp0(id, "ghidra.vibe.provider.bookmarks") == 0)
    return vibe_provider_mcp(title, id, "list_bookmarks", FALSE);
  if (g_strcmp0(id, "ghidra.vibe.provider.rag") == 0)
    return vibe_provider_mcp(title, id, "rag_stats", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.rules") == 0)
    return vibe_provider_mcp(title, id, "rules_get", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.dsc") == 0)
    return vibe_provider_mcp(title, id, "dyld_find_cache", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.apple_bundle") == 0)
    return vibe_provider_mcp(title, id, "malimite_db_stats", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.entropy") == 0)
    return vibe_provider_mcp(title, id, "vibe_list_entropy", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.equates") == 0)
    return vibe_provider_mcp(title, id, "vibe_list_equates", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.relocations") == 0)
    return vibe_provider_mcp(title, id, "vibe_list_relocations", TRUE);
  if (g_strcmp0(id, "ghidra.vibe.provider.registers") == 0)
    return vibe_provider_mcp(title, id, "vibe_list_registers", TRUE);
  return vibe_provider_mcp(title, id, "check_connection", FALSE);
}

static void activate(GtkApplication *app, gpointer user_data) {
  (void)user_data;

  // Initialize theme system now that a display/GtkSettings is available
  // (gtk_settings_get_default() returns NULL if called before startup).
  vibe_theme_init();

  // Show splash screen
  GtkWidget *splash = vibe_splash_create();
  vibe_splash_set_progress(splash, "Initializing GhidraVibe...", 0.1);
  
  // Check user agreement
  if (!vibe_show_agreement_if_needed(NULL)) {
    // User declined agreement
    vibe_splash_destroy(splash);
    g_application_quit(G_APPLICATION(app));
    return;
  }
  
  vibe_splash_set_progress(splash, "Loading application...", 0.3);
  
  AppState *st = g_new0(AppState, 1);
  st->mcp_url = g_strdup(g_getenv("GHIDRA_MCP_URL") ? g_getenv("GHIDRA_MCP_URL")
                                                    : "http://127.0.0.1:8089");

  vibe_splash_set_progress(splash, "Loading accessibility catalog...", 0.4);
  char *catalog = find_data_file("a11y/catalog.json");
  if (!catalog)
    catalog = find_data_file("catalog.json");
  if (catalog) {
    vibe_a11y_load_catalog(catalog);
    g_free(catalog);
  }

  vibe_splash_set_progress(splash, "Checking DSC cache...", 0.5);
#ifdef __linux__
  if (!vibe_dsc_is_cache_available()) {
    // DSC cache not found, will show setup dialog later if needed
  }
#endif

  vibe_splash_set_progress(splash, "Creating main window...", 0.7);
  
  GtkWidget *win = adw_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(win), "GhidraVibe");
  gtk_window_set_default_size(GTK_WINDOW(win), 1280, 840);
  gtk_application_window_set_show_menubar(GTK_APPLICATION_WINDOW(win), TRUE);
  vibe_a11y_bind(win, "ghidra.vibe.root");

  GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  adw_application_window_set_content(ADW_APPLICATION_WINDOW(win), outer);

  st->stack = gtk_stack_new();
  gtk_stack_set_transition_type(GTK_STACK(st->stack), GTK_STACK_TRANSITION_TYPE_CROSSFADE);
  gtk_widget_set_vexpand(st->stack, TRUE);

  gtk_stack_add_titled(GTK_STACK(st->stack), vibe_build_project_window(), "project", "Project");
  gtk_stack_add_titled(GTK_STACK(st->stack), vibe_build_codebrowser_dock(), "codebrowser",
                       "CodeBrowser");
  gtk_stack_add_titled(GTK_STACK(st->stack), vibe_stock_debugger_page(), "debugger", "Debugger");
  gtk_stack_add_titled(GTK_STACK(st->stack), vibe_stock_emulator_page(), "emulator", "Emulator");
  gtk_stack_add_titled(GTK_STACK(st->stack), vibe_stock_vt_page(), "version_tracking",
                       "Version Tracking");

  struct {
    const char *page;
    const char *title;
    const char *id;
  } panels[] = {
      {"functions", "Functions", "ghidra.vibe.provider.functions"},
      {"strings", "Defined Strings", "ghidra.vibe.provider.strings"},
      {"memory_map", "Memory Map", "ghidra.vibe.provider.memory_map"},
      {"symbol_table", "Symbol Table", "ghidra.vibe.provider.symbol_table"},
      {"bytes", "Bytes", "ghidra.vibe.provider.bytes"},
      {"bookmarks", "Bookmarks", "ghidra.vibe.provider.bookmarks"},
      {"script_manager", "Script Manager", "ghidra.vibe.provider.script_manager"},
      {"function_graph", "Function Graph", "ghidra.vibe.provider.function_graph"},
      {"entropy", "Entropy", "ghidra.vibe.provider.entropy"},
      {"overview", "Overview", "ghidra.vibe.provider.overview"},
      {"registers", "Register Manager", "ghidra.vibe.provider.registers"},
      {"python", "Python", "ghidra.vibe.provider.python"},
      {"comments", "Comments", "ghidra.vibe.provider.comments"},
      {"checksum", "Checksum Generator", "ghidra.vibe.provider.checksum"},
      {"equates", "Equates Table", "ghidra.vibe.provider.equates"},
      {"relocations", "Relocation Table", "ghidra.vibe.provider.relocations"},
      {"defined_data", "Defined Data", "ghidra.vibe.provider.defined_data"},
      {"external_programs", "External Programs", "ghidra.vibe.provider.external_programs"},
      {"datatype_preview", "Data Type Preview", "ghidra.vibe.provider.datatype_preview"},
      {"disassembled_view", "Disassembled View", "ghidra.vibe.provider.disassembled_view"},
      {"symbol_references", "Symbol References", "ghidra.vibe.provider.symbol_references"},
      {"function_tags", "Function Tags", "ghidra.vibe.provider.function_tags"},
      {"mcp", "MCP", "ghidra.vibe.provider.mcp"},
      {"agent", "Agent", "ghidra.vibe.provider.agent"},
      {"rag", "RAG / JSpace", "ghidra.vibe.provider.rag"},
      {"rules", "Rules", "ghidra.vibe.provider.rules"},
      {"dsc", "Shared Cache", "ghidra.vibe.provider.dsc"},
      {"apple_bundle", "Apple Bundle / IPA", "ghidra.vibe.provider.apple_bundle"},
      {"swift_classes", "Swift Classes", "ghidra.vibe.provider.swift_classes"},
      {"code_editor", "Code Editor", "ghidra.vibe.provider.code_editor"},
      {NULL, NULL, NULL},
  };
  for (int i = 0; panels[i].page; i++) {
    gtk_stack_add_titled(GTK_STACK(st->stack), vibe_panel(panels[i].title, panels[i].id),
                         panels[i].page, panels[i].title);
  }
  gtk_box_append(GTK_BOX(outer), st->stack);

  GtkWidget *status_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  vibe_a11y_bind(status_bar, "ghidra.vibe.status.bar");
  st->status = gtk_label_new("Ready");
  gtk_widget_set_hexpand(st->status, TRUE);
  gtk_widget_set_halign(st->status, GTK_ALIGN_START);
  vibe_a11y_bind(st->status, "ghidra.vibe.status.message");
  st->mcp_chip = gtk_label_new("MCP idle");
  vibe_a11y_bind(st->mcp_chip, "ghidra.vibe.status.mcp");
  gtk_box_append(GTK_BOX(status_bar), st->status);
  gtk_box_append(GTK_BOX(status_bar), st->mcp_chip);
  gtk_box_append(GTK_BOX(outer), status_bar);

  add_menu(app, st);
  
  vibe_splash_set_progress(splash, "Ready!", 1.0);
  vibe_splash_destroy(splash);
  
  gtk_window_present(GTK_WINDOW(win));
  show_page(st, "project");
}

int main(int argc, char **argv) {
  AdwApplication *app =
      adw_application_new("dev.ghidravibe.app", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  int code = g_application_run(G_APPLICATION(app), argc, argv);
  vibe_a11y_free();
  return code;
}

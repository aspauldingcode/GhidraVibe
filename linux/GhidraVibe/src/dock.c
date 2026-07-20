#include "dock.h"
#include "a11y.h"
#include "graph_view.h"
#include "mcp_client.h"

#include <stdlib.h>

typedef struct {
  GtkTextBuffer *buf;
  char *url;
  char *path;
  gboolean vibe; /* use GHIDRA_VIBE_MCP_EXT_URL when set */
} McpPane;

static const char *analysis_url(void) {
  const char *u = g_getenv("GHIDRA_MCP_URL");
  return u && *u ? u : "http://127.0.0.1:8089";
}

static const char *vibe_url(void) {
  const char *u = g_getenv("GHIDRA_VIBE_MCP_EXT_URL");
  return u && *u ? u : "http://127.0.0.1:8092";
}

static void mcp_pane_refresh(GtkButton *btn, gpointer user_data) {
  (void)btn;
  McpPane *p = user_data;
  const char *base = p->vibe ? vibe_url() : analysis_url();
  char *body = vibe_mcp_get(base, p->path);
  gtk_text_buffer_set_text(p->buf, body ? body : "(empty)", -1);
  g_free(body);
}

static void mcp_pane_free(gpointer data, GClosure *closure) {
  (void)closure;
  McpPane *p = data;
  g_free(p->url);
  g_free(p->path);
  g_free(p);
}

GtkWidget *vibe_provider_label(const char *title, const char *a11y_id) {
  return vibe_provider_mcp(title, a11y_id, NULL, FALSE);
}

static void agent_probe_ollama(GtkButton *btn, gpointer user_data) {
  (void)btn;
  GtkTextBuffer *buf = GTK_TEXT_BUFFER(user_data);
  const char *base = g_getenv("GHIDRA_VIBE_AI_BASE_URL");
  if (!base || !*base)
    base = g_getenv("OLLAMA_HOST");
  if (!base || !*base)
    base = "http://127.0.0.1:11434";
  char *tags = vibe_mcp_get(base, "api/tags");
  char *vibe = vibe_mcp_post(g_getenv("GHIDRA_VIBE_MCP_EXT_URL")
                                 ? g_getenv("GHIDRA_VIBE_MCP_EXT_URL")
                                 : "http://127.0.0.1:8092",
                             "rag_discover", "{\"query\":\"agent sidebar\"}");
  GString *out = g_string_new("## Local AI (Ollama OpenAI-compat)\n");
  g_string_append_printf(out, "base=%s\n\n%s\n\n## vibe rag_discover\n%s\n", base,
                         tags ? tags : "(no tags)", vibe ? vibe : "(vibe unavailable)");
  g_string_append(out, "\nPlaybooks (rename/autonomous_re) live in vibe MCP handlers — same as macOS.\n");
  gtk_text_buffer_set_text(buf, out->str, -1);
  g_string_free(out, TRUE);
  g_free(tags);
  g_free(vibe);
}

static void agent_playbook(GtkButton *btn, gpointer user_data) {
  (void)btn;
  GtkTextBuffer *buf = GTK_TEXT_BUFFER(user_data);
  const char *vibe_url = g_getenv("GHIDRA_VIBE_MCP_EXT_URL");
  if (!vibe_url || !*vibe_url)
    vibe_url = "http://127.0.0.1:8092";
  char *out = vibe_mcp_post(vibe_url, "autonomous_re", "{\"budget\":4,\"apply\":false}");
  gtk_text_buffer_set_text(buf, out ? out : "autonomous_re failed", -1);
  g_free(out);
}

GtkWidget *vibe_provider_agent(void) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *hdr_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  GtkWidget *hdr = gtk_label_new("Agent");
  gtk_widget_add_css_class(hdr, "heading");
  gtk_widget_set_halign(hdr, GTK_ALIGN_START);
  gtk_widget_set_hexpand(hdr, TRUE);
  gtk_box_append(GTK_BOX(hdr_row), hdr);

  GtkWidget *view = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(view), FALSE);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(view), TRUE);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
  GtkTextBuffer *buf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
  gtk_text_buffer_set_text(
      buf,
      "Agent (GTK stub)\n"
      "Default LLM: Metal/local Ollama OpenAI-compat (:11434), same as macOS / dendritic chat.\n"
      "Click Probe Ollama or Autonomous RE (via vibe MCP).\n",
      -1);

  GtkWidget *probe = gtk_button_new_with_label("Probe Ollama");
  vibe_a11y_bind(probe, "ghidra.vibe.provider.agent.index");
  g_signal_connect(probe, "clicked", G_CALLBACK(agent_probe_ollama), buf);
  gtk_box_append(GTK_BOX(hdr_row), probe);

  GtkWidget *play = gtk_button_new_with_label("Autonomous RE");
  vibe_a11y_bind(play, "ghidra.vibe.provider.agent.autonomous_re");
  g_signal_connect(play, "clicked", G_CALLBACK(agent_playbook), buf);
  gtk_box_append(GTK_BOX(hdr_row), play);

  GtkWidget *scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), view);
  gtk_widget_set_vexpand(scroll, TRUE);
  gtk_box_append(GTK_BOX(box), hdr_row);
  gtk_box_append(GTK_BOX(box), scroll);
  vibe_a11y_bind(box, "ghidra.vibe.agent.sidebar");
  return box;
}

GtkWidget *vibe_provider_mcp(const char *title, const char *a11y_id, const char *mcp_path,
                             gboolean use_vibe) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *hdr_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  GtkWidget *hdr = gtk_label_new(title);
  gtk_widget_add_css_class(hdr, "heading");
  gtk_widget_set_halign(hdr, GTK_ALIGN_START);
  gtk_widget_set_margin_start(hdr, 6);
  gtk_widget_set_margin_top(hdr, 4);
  gtk_widget_set_hexpand(hdr, TRUE);
  gtk_box_append(GTK_BOX(hdr_row), hdr);

  GtkWidget *view = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(view), FALSE);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(view), TRUE);
  gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
  GtkTextBuffer *buf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
  if (mcp_path && *mcp_path) {
    McpPane *pane = g_new0(McpPane, 1);
    pane->buf = buf;
    pane->path = g_strdup(mcp_path);
    pane->vibe = use_vibe;
    GtkWidget *refresh = gtk_button_new_with_label("Refresh MCP");
    g_signal_connect_data(refresh, "clicked", G_CALLBACK(mcp_pane_refresh), pane, mcp_pane_free, 0);
    gtk_box_append(GTK_BOX(hdr_row), refresh);
    gtk_text_buffer_set_text(buf, "(click Refresh MCP — same tools as macOS / Cursor)", -1);
  } else {
    gtk_text_buffer_set_text(buf, "(provider — connect analysis MCP :8089 / vibe :8092)", -1);
  }
  GtkWidget *scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), view);
  gtk_widget_set_vexpand(scroll, TRUE);
  gtk_widget_set_hexpand(scroll, TRUE);
  gtk_box_append(GTK_BOX(box), hdr_row);
  gtk_box_append(GTK_BOX(box), scroll);
  vibe_a11y_bind(box, a11y_id);
  return box;
}

static GtkWidget *framed(GtkWidget *child) {
  GtkWidget *frame = gtk_frame_new(NULL);
  gtk_frame_set_child(GTK_FRAME(frame), child);
  return frame;
}

static GtkWidget *tb_btn(const char *label, const char *id, const char *action) {
  GtkWidget *b = gtk_button_new_with_label(label);
  vibe_a11y_bind(b, id);
  if (action)
    gtk_actionable_set_action_name(GTK_ACTIONABLE(b), action);
  return b;
}

GtkWidget *vibe_build_codebrowser_dock(void) {
  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

  GtkWidget *tb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_widget_set_margin_start(tb, 6);
  gtk_widget_set_margin_end(tb, 6);
  gtk_widget_set_margin_top(tb, 4);
  gtk_widget_set_margin_bottom(tb, 4);
  struct {
    const char *label;
    const char *id;
    const char *action;
  } tools[] = {
      {"◀", "ghidra.vibe.toolbar.nav_back", "app.show_codebrowser"},
      {"▶", "ghidra.vibe.toolbar.nav_fwd", "app.show_codebrowser"},
      {"Save Program", "ghidra.vibe.toolbar.save", "app.show_codebrowser"},
      {"Undo", "ghidra.vibe.toolbar.undo", "app.show_codebrowser"},
      {"Redo", "ghidra.vibe.toolbar.redo", "app.show_codebrowser"},
      {"I", "ghidra.vibe.toolbar.listing_i", "app.show_codebrowser"},
      {"D", "ghidra.vibe.toolbar.listing_d", "app.show_codebrowser"},
      {"U", "ghidra.vibe.toolbar.listing_u", "app.show_codebrowser"},
      {"L", "ghidra.vibe.toolbar.listing_l", "app.show_codebrowser"},
      {"F", "ghidra.vibe.toolbar.listing_f", "app.show_codebrowser"},
      {"V", "ghidra.vibe.toolbar.listing_v", NULL},
      {"B", "ghidra.vibe.toolbar.listing_b", "app.show_codebrowser"},
      {"Go To", "ghidra.vibe.toolbar.goto", "app.show_codebrowser"},
      {"Auto Analyze", "ghidra.vibe.toolbar.analyze", "app.show_codebrowser"},
      {"MCP Health", "ghidra.vibe.toolbar.mcp_health", "app.mcp_health"},
      {"Start MCP", "ghidra.vibe.toolbar.start_mcp", "app.show_mcp"},
      {"Framework…", "ghidra.vibe.toolbar.dsc", "app.show_dsc"},
      {"App Bundle…", "ghidra.vibe.toolbar.apple", "app.show_apple"},
      {"Agent", "ghidra.vibe.toolbar.agent_sidebar", "app.show_agent"},
      {NULL, NULL, NULL},
  };
  for (int i = 0; tools[i].label; i++)
    gtk_box_append(GTK_BOX(tb), tb_btn(tools[i].label, tools[i].id, tools[i].action));
  gtk_box_append(GTK_BOX(root), tb);

  GtkWidget *hdr = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_widget_set_margin_start(hdr, 6);
  gtk_box_append(GTK_BOX(hdr),
                 tb_btn("Entropy", "ghidra.vibe.codebrowser.header.entropy", "app.show_entropy"));
  gtk_box_append(GTK_BOX(hdr),
                 tb_btn("Overview", "ghidra.vibe.codebrowser.header.overview", "app.show_overview"));
  gtk_box_append(GTK_BOX(root), hdr);

  /* Stock CodeBrowser.tool: left dock full-height; console only under listing/right. */
  GtkWidget *main_row = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_set_vexpand(main_row, TRUE);

  GtkWidget *left = gtk_paned_new(GTK_ORIENTATION_VERTICAL);
  GtkWidget *left_top = gtk_paned_new(GTK_ORIENTATION_VERTICAL);

  gtk_paned_set_start_child(
      GTK_PANED(left_top),
      framed(vibe_provider_mcp("Program Trees", "ghidra.vibe.provider.program_tree", "list_project_files",
                              FALSE)));
  gtk_paned_set_end_child(
      GTK_PANED(left_top),
      framed(vibe_provider_mcp("Symbol Tree", "ghidra.vibe.provider.symbol_tree", "list_namespaces", FALSE)));

  gtk_paned_set_start_child(GTK_PANED(left), left_top);
  gtk_paned_set_end_child(
      GTK_PANED(left),
      framed(vibe_provider_mcp("Data Type Manager", "ghidra.vibe.provider.data_types", "list_data_types",
                              FALSE)));

  GtkWidget *center_col = gtk_paned_new(GTK_ORIENTATION_VERTICAL);
  GtkWidget *center = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_paned_set_start_child(
      GTK_PANED(center),
      framed(vibe_provider_mcp("Listing", "ghidra.vibe.provider.listing", "list_functions", FALSE)));

  GtkWidget *right_nb = gtk_notebook_new();
  vibe_a11y_bind(right_nb, "ghidra.vibe.codebrowser.right_tabs");
  struct {
    const char *title;
    const char *id;
    const char *path;
    gboolean vibe;
    gboolean function_graph;
    gboolean agent;
  } tabs[] = {
      {"Decompile", "ghidra.vibe.provider.decompiler", "list_methods", FALSE, FALSE, FALSE},
      {"Bytes", "ghidra.vibe.provider.bytes", "list_segments", FALSE, FALSE, FALSE},
      {"Defined Data", "ghidra.vibe.provider.defined_data", "list_data_items", FALSE, FALSE, FALSE},
      {"Defined Strings", "ghidra.vibe.provider.strings", "list_strings", FALSE, FALSE, FALSE},
      {"Equates Table", "ghidra.vibe.provider.equates", "vibe_list_equates", TRUE, FALSE, FALSE},
      {"External Programs", "ghidra.vibe.provider.external_programs", "list_external_locations", FALSE,
       FALSE, FALSE},
      {"Functions", "ghidra.vibe.provider.functions", "list_functions", FALSE, FALSE, FALSE},
      {"Relocation Table", "ghidra.vibe.provider.relocations", "vibe_list_relocations", TRUE, FALSE,
       FALSE},
      {"Memory Map", "ghidra.vibe.provider.memory_map", "list_segments", FALSE, FALSE, FALSE},
      {"Symbol Table", "ghidra.vibe.provider.symbol_table", "list_exports", FALSE, FALSE, FALSE},
      {"Bookmarks", "ghidra.vibe.provider.bookmarks", "list_bookmarks", FALSE, FALSE, FALSE},
      {"Script Manager", "ghidra.vibe.provider.script_manager", "list_ghidra_scripts", FALSE, FALSE,
       FALSE},
      {"Function Graph", "ghidra.vibe.provider.function_graph", NULL, FALSE, TRUE, FALSE},
      {"Register Manager", "ghidra.vibe.provider.registers", "vibe_list_registers", TRUE, FALSE, FALSE},
      {"MCP", "ghidra.vibe.provider.mcp", "check_connection", FALSE, FALSE, FALSE},
      {"Agent", "ghidra.vibe.provider.agent", NULL, FALSE, FALSE, TRUE},
      {"RAG / JSpace", "ghidra.vibe.provider.rag", "rag_stats", TRUE, FALSE, FALSE},
      {"Rules", "ghidra.vibe.provider.rules", "rules_get", TRUE, FALSE, FALSE},
      {"Shared Cache", "ghidra.vibe.provider.dsc", "dyld_find_cache", TRUE, FALSE, FALSE},
      {"App Bundle", "ghidra.vibe.provider.apple_bundle", "malimite_list_bundle_binaries", TRUE, FALSE,
       FALSE},
      {"Classes", "ghidra.vibe.provider.swift_classes", "swift_list_namespaces", TRUE, FALSE, FALSE},
      {"Entropy", "ghidra.vibe.provider.entropy", "vibe_list_entropy", TRUE, FALSE, FALSE},
      {NULL, NULL, NULL, FALSE, FALSE, FALSE},
  };
  for (int i = 0; tabs[i].title; i++) {
    GtkWidget *page;
    if (tabs[i].function_graph)
      page = vibe_provider_function_graph();
    else if (tabs[i].agent)
      page = vibe_provider_agent();
    else
      page = vibe_provider_mcp(tabs[i].title, tabs[i].id, tabs[i].path, tabs[i].vibe);
    gtk_notebook_append_page(GTK_NOTEBOOK(right_nb), page, gtk_label_new(tabs[i].title));
  }
  gtk_paned_set_end_child(GTK_PANED(center), framed(right_nb));

  GtkWidget *console_nb = gtk_notebook_new();
  vibe_a11y_bind(console_nb, "ghidra.vibe.codebrowser.console_tabs");
  gtk_notebook_append_page(
      GTK_NOTEBOOK(console_nb),
      vibe_provider_mcp("Console - Scripting", "ghidra.vibe.provider.console", "check_connection", FALSE),
      gtk_label_new("Console"));
  gtk_notebook_append_page(
      GTK_NOTEBOOK(console_nb),
      vibe_provider_mcp("Bookmarks", "ghidra.vibe.provider.bookmarks", "list_bookmarks", FALSE),
      gtk_label_new("Bookmarks"));

  gtk_paned_set_start_child(GTK_PANED(center_col), center);
  gtk_paned_set_end_child(GTK_PANED(center_col), framed(console_nb));
  gtk_paned_set_resize_end_child(GTK_PANED(center_col), FALSE);
  gtk_widget_set_size_request(gtk_paned_get_end_child(GTK_PANED(center_col)), -1, 100);

  gtk_paned_set_start_child(GTK_PANED(main_row), left);
  gtk_paned_set_end_child(GTK_PANED(main_row), center_col);
  gtk_paned_set_resize_start_child(GTK_PANED(main_row), FALSE);
  gtk_widget_set_size_request(left, 220, -1);

  gtk_box_append(GTK_BOX(root), main_row);
  vibe_a11y_bind(root, "ghidra.vibe.codebrowser");
  return root;
}

GtkWidget *vibe_build_project_window(void) {
  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_set_margin_start(root, 12);
  gtk_widget_set_margin_end(root, 12);
  gtk_widget_set_margin_top(root, 12);

  GtkWidget *tb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_box_append(GTK_BOX(tb),
                 tb_btn("CodeBrowser", "ghidra.vibe.project.open_tool", "app.show_codebrowser"));
  gtk_box_append(GTK_BOX(tb), tb_btn("MCP Health", "ghidra.vibe.project.mcp", "app.mcp_health"));
  gtk_box_append(GTK_BOX(tb), tb_btn("Shared Cache", "ghidra.vibe.project.dsc", "app.show_dsc"));
  gtk_box_append(GTK_BOX(tb),
                 tb_btn("Open App Bundle…", "ghidra.vibe.menu.file.open_app_bundle", "app.show_apple"));
  gtk_box_append(GTK_BOX(root), tb);

  gtk_box_append(GTK_BOX(root),
                 vibe_provider_mcp("Active Project", "ghidra.vibe.project.tree", "list_project_files",
                                  FALSE));
  gtk_box_append(GTK_BOX(root),
                 vibe_provider_mcp("Running Tools / Log", "ghidra.vibe.project.log", "check_connection",
                                  FALSE));
  vibe_a11y_bind(root, "ghidra.vibe.project");
  return root;
}

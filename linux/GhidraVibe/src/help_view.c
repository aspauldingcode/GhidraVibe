/* Native Help browser — TOC + WebKitGTK (optional) over packaged help/ corpus. */
#include "help_view.h"
#include "a11y.h"

#include <gtk/gtk.h>
#include <json-glib/json-glib.h>
#include <string.h>

#ifdef HAVE_WEBKIT
#include <webkit/webkit.h>
#endif

typedef struct {
  char *root;
  GtkWidget *list_box;
  GtkWidget *webview_or_label;
  GtkWidget *search;
} HelpState;

typedef struct {
  char *title;
  char *target;
  char *path;
} HelpItem;

static char *find_help_root(void) {
  const char *env = g_getenv("GHIDRA_VIBE_HELP");
  if (env && g_file_test(env, G_FILE_TEST_IS_DIR))
    return g_strdup(env);
  const char *ui = g_getenv("GHIDRA_VIBE_UI_DATA");
  if (ui) {
    char *p = g_build_filename(ui, "help", NULL);
    if (g_file_test(p, G_FILE_TEST_IS_DIR))
      return p;
    g_free(p);
  }
  const char *cands[] = {"native-ui/help", "../native-ui/help", "../../native-ui/help",
                         "/usr/share/ghidra-vibe/help", NULL};
  for (int i = 0; cands[i]; i++) {
    if (g_file_test(cands[i], G_FILE_TEST_IS_DIR))
      return g_strdup(cands[i]);
  }
  return NULL;
}

static char *map_lookup(const char *root, const char *target) {
  if (!root || !target || !*target)
    return NULL;
  char *map_path = g_build_filename(root, "map.json", NULL);
  JsonParser *parser = json_parser_new();
  char *out = NULL;
  if (json_parser_load_from_file(parser, map_path, NULL)) {
    JsonNode *n = json_parser_get_root(parser);
    if (n && JSON_NODE_HOLDS_OBJECT(n)) {
      JsonObject *obj = json_node_get_object(n);
      if (json_object_has_member(obj, target)) {
        const char *url = json_object_get_string_member(obj, target);
        if (url) {
          out = g_strdup(url);
          char *hash = strchr(out, '#');
          if (hash)
            *hash = '\0';
        }
      }
    }
  }
  g_object_unref(parser);
  g_free(map_path);
  return out;
}

static void load_article(HelpState *st, const char *rel_path) {
  if (!st->root || !rel_path || !*rel_path)
    return;
  char *bare = g_strdup(rel_path);
  char *hash = strchr(bare, '#');
  if (hash)
    *hash = '\0';
  char *file = g_build_filename(st->root, "articles", bare, NULL);
  g_free(bare);
  if (!g_file_test(file, G_FILE_TEST_EXISTS)) {
    g_free(file);
    return;
  }
#ifdef HAVE_WEBKIT
  if (WEBKIT_IS_WEB_VIEW(st->webview_or_label)) {
    char *uri = g_filename_to_uri(file, NULL, NULL);
    if (uri) {
      webkit_web_view_load_uri(WEBKIT_WEB_VIEW(st->webview_or_label), uri);
      g_free(uri);
    }
    g_free(file);
    return;
  }
#endif
  if (GTK_IS_LABEL(st->webview_or_label)) {
    gchar *contents = NULL;
    if (g_file_get_contents(file, &contents, NULL, NULL)) {
      gtk_label_set_text(GTK_LABEL(st->webview_or_label), contents);
      g_free(contents);
    }
  }
  g_free(file);
}

static void clear_list(GtkWidget *box) {
  GtkWidget *child = gtk_widget_get_first_child(box);
  while (child) {
    GtkWidget *next = gtk_widget_get_next_sibling(child);
    gtk_list_box_remove(GTK_LIST_BOX(box), child);
    child = next;
  }
}

static void free_help_item(gpointer data) {
  HelpItem *it = data;
  if (!it)
    return;
  g_free(it->title);
  g_free(it->target);
  g_free(it->path);
  g_free(it);
}

static void on_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer data) {
  (void)box;
  HelpState *st = data;
  if (!row)
    return;
  HelpItem *it = g_object_get_data(G_OBJECT(row), "help-item");
  if (!it)
    return;
  if (it->path && *it->path)
    load_article(st, it->path);
  else if (it->target && *it->target) {
    char *p = map_lookup(st->root, it->target);
    if (p) {
      load_article(st, p);
      g_free(p);
    }
  }
}

static void append_row(HelpState *st, const char *title, const char *target, const char *path) {
  HelpItem *it = g_new0(HelpItem, 1);
  it->title = g_strdup(title ? title : "Untitled");
  it->target = g_strdup(target ? target : "");
  it->path = g_strdup(path ? path : "");
  GtkWidget *lab = gtk_label_new(it->title);
  gtk_label_set_xalign(GTK_LABEL(lab), 0);
  gtk_label_set_ellipsize(GTK_LABEL(lab), PANGO_ELLIPSIZE_END);
  GtkWidget *row = gtk_list_box_row_new();
  gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), lab);
  g_object_set_data_full(G_OBJECT(row), "help-item", it, free_help_item);
  gtk_list_box_append(GTK_LIST_BOX(st->list_box), row);
}

static void toc_walk(JsonObject *node, int depth, HelpState *st) {
  const char *title =
      json_object_has_member(node, "title") ? json_object_get_string_member(node, "title") : "Untitled";
  const char *target =
      json_object_has_member(node, "target") ? json_object_get_string_member(node, "target") : "";
  char *indent = g_strnfill((gsize)(depth * 2), ' ');
  char *label = g_strdup_printf("%s%s", indent, title);
  char *path = map_lookup(st->root, target);
  append_row(st, label, target, path ? path : "");
  g_free(label);
  g_free(indent);
  g_free(path);

  if (!json_object_has_member(node, "children"))
    return;
  JsonArray *kids = json_object_get_array_member(node, "children");
  if (!kids)
    return;
  guint n = json_array_get_length(kids);
  for (guint i = 0; i < n; i++) {
    JsonObject *child = json_array_get_object_element(kids, i);
    if (child)
      toc_walk(child, depth + 1, st);
  }
}

static void load_toc(HelpState *st) {
  clear_list(st->list_box);
  if (!st->root)
    return;
  char *toc_path = g_build_filename(st->root, "toc.json", NULL);
  JsonParser *parser = json_parser_new();
  if (json_parser_load_from_file(parser, toc_path, NULL)) {
    JsonNode *n = json_parser_get_root(parser);
    if (n && JSON_NODE_HOLDS_OBJECT(n)) {
      JsonObject *root = json_node_get_object(n);
      if (json_object_has_member(root, "children")) {
        JsonArray *kids = json_object_get_array_member(root, "children");
        guint nch = kids ? json_array_get_length(kids) : 0;
        for (guint i = 0; i < nch; i++) {
          JsonObject *child = json_array_get_object_element(kids, i);
          if (child)
            toc_walk(child, 0, st);
        }
      } else {
        toc_walk(root, 0, st);
      }
    }
  }
  g_object_unref(parser);
  g_free(toc_path);

  char *welcome = map_lookup(st->root, "Misc_Help_Contents");
  if (welcome) {
    load_article(st, welcome);
    g_free(welcome);
  }
}

static void on_search_changed(GtkEditable *editable, gpointer data) {
  HelpState *st = data;
  const char *q = gtk_editable_get_text(editable);
  if (!q || !*q) {
    load_toc(st);
    return;
  }
  if (!st->root || strlen(q) < 2)
    return;
  char *search_path = g_build_filename(st->root, "search.json", NULL);
  JsonParser *parser = json_parser_new();
  if (!json_parser_load_from_file(parser, search_path, NULL)) {
    g_object_unref(parser);
    g_free(search_path);
    return;
  }
  JsonNode *root = json_parser_get_root(parser);
  if (!root || !JSON_NODE_HOLDS_ARRAY(root)) {
    g_object_unref(parser);
    g_free(search_path);
    return;
  }
  clear_list(st->list_box);
  JsonArray *arr = json_node_get_array(root);
  guint n = json_array_get_length(arr);
  char *ql = g_utf8_strdown(q, -1);
  guint added = 0;
  for (guint i = 0; i < n && added < 40; i++) {
    JsonObject *e = json_array_get_object_element(arr, i);
    if (!e)
      continue;
    const char *title =
        json_object_has_member(e, "title") ? json_object_get_string_member(e, "title") : "";
    const char *text =
        json_object_has_member(e, "text") ? json_object_get_string_member(e, "text") : "";
    const char *path =
        json_object_has_member(e, "path") ? json_object_get_string_member(e, "path") : "";
    char *tl = g_utf8_strdown(title, -1);
    char *xl = g_utf8_strdown(text, -1);
    if ((tl && strstr(tl, ql)) || (xl && strstr(xl, ql))) {
      append_row(st, title, "", path);
      added++;
    }
    g_free(tl);
    g_free(xl);
  }
  g_free(ql);
  g_object_unref(parser);
  g_free(search_path);
}

static void on_destroy(GtkWidget *w, gpointer data) {
  (void)w;
  HelpState *st = data;
  g_free(st->root);
  g_free(st);
}

void vibe_help_show(GtkWindow *parent) {
  HelpState *st = g_new0(HelpState, 1);
  st->root = find_help_root();

  GtkWidget *win = gtk_window_new();
  gtk_window_set_title(GTK_WINDOW(win), "Ghidra Help");
  gtk_window_set_default_size(GTK_WINDOW(win), 960, 640);
  if (parent)
    gtk_window_set_transient_for(GTK_WINDOW(win), parent);
  vibe_a11y_bind(win, "ghidra.vibe.help");

  GtkWidget *paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_window_set_child(GTK_WINDOW(win), paned);

  GtkWidget *left = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_widget_set_size_request(left, 260, -1);
  st->search = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(st->search), "Search Help");
  g_signal_connect(st->search, "changed", G_CALLBACK(on_search_changed), st);
  vibe_a11y_bind(st->search, "ghidra.vibe.help.search");
  gtk_box_append(GTK_BOX(left), st->search);

  st->list_box = gtk_list_box_new();
  g_signal_connect(st->list_box, "row-activated", G_CALLBACK(on_row_activated), st);
  vibe_a11y_bind(st->list_box, "ghidra.vibe.help.toc");
  GtkWidget *scroll = gtk_scrolled_window_new();
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), st->list_box);
  gtk_widget_set_vexpand(scroll, TRUE);
  gtk_box_append(GTK_BOX(left), scroll);
  gtk_paned_set_start_child(GTK_PANED(paned), left);

#ifdef HAVE_WEBKIT
  st->webview_or_label = webkit_web_view_new();
#else
  st->webview_or_label = gtk_label_new(
      st->root ? "WebKitGTK not available in this build. TOC lists articles; rebuild with "
                 "webkitgtk-6.0 for HTML rendering."
               : "Help corpus not found. Run scripts/extract-stock-help.py "
                 "(set GHIDRA_VIBE_HELP or GHIDRA_VIBE_UI_DATA).");
  gtk_label_set_wrap(GTK_LABEL(st->webview_or_label), TRUE);
  gtk_widget_set_margin_start(st->webview_or_label, 16);
  gtk_widget_set_margin_end(st->webview_or_label, 16);
#endif
  vibe_a11y_bind(st->webview_or_label, "ghidra.vibe.help.content");
  gtk_paned_set_end_child(GTK_PANED(paned), st->webview_or_label);

  if (st->root)
    load_toc(st);

  g_signal_connect(win, "destroy", G_CALLBACK(on_destroy), st);
  gtk_window_present(GTK_WINDOW(win));
}

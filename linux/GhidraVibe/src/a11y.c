#include "a11y.h"

#include <json-glib/json-glib.h>
#include <stdlib.h>
#include <string.h>

static GHashTable *catalog;

static void free_entry(gpointer p) {
  VibeA11yEntry *e = p;
  if (!e)
    return;
  g_free(e->id);
  g_free(e->label);
  g_free(e->hint);
  g_free(e);
}

void vibe_a11y_load_catalog(const char *path) {
  if (catalog)
    g_hash_table_destroy(catalog);
  catalog = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, free_entry);

  JsonParser *parser = json_parser_new();
  GError *err = NULL;
  if (!json_parser_load_from_file(parser, path, &err)) {
    g_warning("a11y catalog: %s", err ? err->message : "load failed");
    g_clear_error(&err);
    g_object_unref(parser);
    return;
  }
  JsonNode *root = json_parser_get_root(parser);
  JsonObject *obj = json_node_get_object(root);
  JsonArray *arr = json_object_get_array_member(obj, "entries");
  if (!arr) {
    g_object_unref(parser);
    return;
  }
  for (guint i = 0; i < json_array_get_length(arr); i++) {
    JsonObject *e = json_array_get_object_element(arr, i);
    const char *id = json_object_get_string_member(e, "id");
    const char *label = json_object_get_string_member(e, "label");
    const char *hint = json_object_get_string_member(e, "hint");
    if (!id)
      continue;
    VibeA11yEntry *ent = g_new0(VibeA11yEntry, 1);
    ent->id = g_strdup(id);
    ent->label = g_strdup(label ? label : id);
    ent->hint = g_strdup(hint ? hint : "");
    g_hash_table_insert(catalog, g_strdup(id), ent);
  }
  g_object_unref(parser);
}

const VibeA11yEntry *vibe_a11y_lookup(const char *id) {
  if (!catalog || !id)
    return NULL;
  return g_hash_table_lookup(catalog, id);
}

void vibe_a11y_bind(GtkWidget *widget, const char *id) {
  if (!widget || !id)
    return;
  gtk_widget_set_name(widget, id);
  const VibeA11yEntry *e = vibe_a11y_lookup(id);
  const char *label = e ? e->label : id;
  const char *hint = e ? e->hint : id;
  gtk_accessible_update_property(GTK_ACCESSIBLE(widget),
                                 GTK_ACCESSIBLE_PROPERTY_LABEL, label,
                                 GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, hint, -1);
  if (hint && *hint)
    gtk_widget_set_tooltip_text(widget, hint);
}

void vibe_a11y_free(void) {
  if (catalog) {
    g_hash_table_destroy(catalog);
    catalog = NULL;
  }
}

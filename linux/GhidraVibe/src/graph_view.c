#include "graph_view.h"
#include "a11y.h"
#include "mcp_client.h"

#include <cairo.h>
#include <json-glib/json-glib.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 512
#define MAX_EDGES 2048
#define MAX_INSNS 12
#define NODE_W 200.0
#define NODE_H_MIN 48.0
#define H_GAP 40.0
#define V_GAP 32.0
#define PAD 32.0

typedef struct {
  char id[64];
  char addr[64];
  char label[128];
  char kind[16];
  char insns[MAX_INSNS][160];
  int insn_count;
  double x, y, h;
  int level;
} GNode;

typedef struct {
  char from[64];
  char to[64];
  char type[24];
} GEdge;

typedef struct {
  GNode nodes[MAX_NODES];
  int n_nodes;
  GEdge edges[MAX_EDGES];
  int n_edges;
  char function[128];
  char entry[64];
  char status[256];
  double pan_x, pan_y;
  double zoom;
  double content_w, content_h;
  int selected;
  /* Node drag: selected index being moved; -1 = background pan. */
  int drag_node;
  double drag_grab_x, drag_grab_y;
  double drag_start_x, drag_start_y;
  double pan_at_drag_x, pan_at_drag_y;
  int drag_moved;
  GtkWidget *drawing;
  GtkWidget *status_lbl;
} GraphState;

static GraphState *state_from(GtkWidget *w) {
  return g_object_get_data(G_OBJECT(w), "graph-state");
}

static int find_node(GraphState *st, const char *id) {
  for (int i = 0; i < st->n_nodes; i++) {
    if (strcmp(st->nodes[i].id, id) == 0) {
      return i;
    }
  }
  return -1;
}

static void clear_graph(GraphState *st) {
  st->n_nodes = 0;
  st->n_edges = 0;
  st->function[0] = 0;
  st->entry[0] = 0;
  st->selected = -1;
}

static void layout_graph(GraphState *st) {
  if (st->n_nodes == 0) {
    st->content_w = st->content_h = 100;
    return;
  }
  int entry_i = find_node(st, st->entry);
  if (entry_i < 0) {
    entry_i = 0;
  }
  for (int i = 0; i < st->n_nodes; i++) {
    st->nodes[i].level = -1;
    st->nodes[i].h = NODE_H_MIN + st->nodes[i].insn_count * 12.0;
    if (st->nodes[i].h < NODE_H_MIN) {
      st->nodes[i].h = NODE_H_MIN;
    }
  }
  // BFS levels
  int queue[MAX_NODES];
  int qh = 0, qt = 0;
  st->nodes[entry_i].level = 0;
  queue[qt++] = entry_i;
  while (qh < qt) {
    int u = queue[qh++];
    for (int e = 0; e < st->n_edges; e++) {
      if (strcmp(st->edges[e].from, st->nodes[u].id) != 0) {
        continue;
      }
      int v = find_node(st, st->edges[e].to);
      if (v >= 0 && st->nodes[v].level < 0) {
        st->nodes[v].level = st->nodes[u].level + 1;
        queue[qt++] = v;
      }
    }
  }
  int max_lv = 0;
  for (int i = 0; i < st->n_nodes; i++) {
    if (st->nodes[i].level < 0) {
      st->nodes[i].level = max_lv + 1;
    }
    if (st->nodes[i].level > max_lv) {
      max_lv = st->nodes[i].level;
    }
  }

  double max_w = 0, y = PAD;
  for (int lv = 0; lv <= max_lv; lv++) {
    int row[MAX_NODES];
    int nr = 0;
    double row_h = NODE_H_MIN;
    for (int i = 0; i < st->n_nodes; i++) {
      if (st->nodes[i].level == lv) {
        row[nr++] = i;
        if (st->nodes[i].h > row_h) {
          row_h = st->nodes[i].h;
        }
      }
    }
    double row_w = nr * NODE_W + (nr > 0 ? (nr - 1) * H_GAP : 0);
    double x = PAD;
    for (int k = 0; k < nr; k++) {
      st->nodes[row[k]].x = x;
      st->nodes[row[k]].y = y;
      x += NODE_W + H_GAP;
    }
    if (PAD + row_w + PAD > max_w) {
      max_w = PAD + row_w + PAD;
    }
    y += row_h + V_GAP;
  }
  st->content_w = max_w;
  st->content_h = y + PAD;
}

static gboolean parse_cfg_json(GraphState *st, const char *json) {
  clear_graph(st);
  if (!json || !json[0]) {
    return FALSE;
  }
  JsonParser *parser = json_parser_new();
  GError *err = NULL;
  if (!json_parser_load_from_data(parser, json, -1, &err)) {
    g_clear_error(&err);
    g_object_unref(parser);
    return FALSE;
  }
  JsonNode *root = json_parser_get_root(parser);
  if (!JSON_NODE_HOLDS_OBJECT(root)) {
    g_object_unref(parser);
    return FALSE;
  }
  JsonObject *obj = json_node_get_object(root);
  if (json_object_has_member(obj, "ok") && !json_object_get_boolean_member(obj, "ok")) {
    g_object_unref(parser);
    return FALSE;
  }
  const char *fn = json_object_get_string_member_with_default(obj, "function", "");
  const char *entry = json_object_get_string_member_with_default(obj, "entry", "");
  g_strlcpy(st->function, fn, sizeof st->function);
  g_strlcpy(st->entry, entry, sizeof st->entry);

  JsonArray *nodes = json_object_get_array_member(obj, "nodes");
  if (!nodes) {
    g_object_unref(parser);
    return FALSE;
  }
  guint nn = json_array_get_length(nodes);
  for (guint i = 0; i < nn && st->n_nodes < MAX_NODES; i++) {
    JsonObject *n = json_array_get_object_element(nodes, i);
    if (!n) {
      continue;
    }
    GNode *gn = &st->nodes[st->n_nodes];
    memset(gn, 0, sizeof *gn);
    const char *id = json_object_get_string_member_with_default(n, "id", "");
    const char *addr = json_object_get_string_member_with_default(n, "addr", id);
    g_strlcpy(gn->id, id[0] ? id : addr, sizeof gn->id);
    g_strlcpy(gn->addr, addr, sizeof gn->addr);
    g_strlcpy(gn->label, json_object_get_string_member_with_default(n, "label", addr), sizeof gn->label);
    g_strlcpy(gn->kind, json_object_get_string_member_with_default(n, "kind", "body"), sizeof gn->kind);
    JsonArray *ins = json_object_get_array_member(n, "insns");
    if (ins) {
      guint ni = json_array_get_length(ins);
      for (guint j = 0; j < ni && gn->insn_count < MAX_INSNS; j++) {
        const char *line = json_array_get_string_element(ins, j);
        if (line) {
          g_strlcpy(gn->insns[gn->insn_count++], line, sizeof gn->insns[0]);
        }
      }
    }
    st->n_nodes++;
  }

  JsonArray *edges = json_object_get_array_member(obj, "edges");
  if (edges) {
    guint ne = json_array_get_length(edges);
    for (guint i = 0; i < ne && st->n_edges < MAX_EDGES; i++) {
      JsonObject *e = json_array_get_object_element(edges, i);
      if (!e) {
        continue;
      }
      GEdge *ge = &st->edges[st->n_edges];
      g_strlcpy(ge->from, json_object_get_string_member_with_default(e, "from", ""), sizeof ge->from);
      g_strlcpy(ge->to, json_object_get_string_member_with_default(e, "to", ""), sizeof ge->to);
      g_strlcpy(ge->type, json_object_get_string_member_with_default(e, "type", "flow"), sizeof ge->type);
      if (ge->from[0] && ge->to[0]) {
        st->n_edges++;
      }
    }
  }
  g_object_unref(parser);
  layout_graph(st);
  return st->n_nodes > 0;
}

/** Draw UTF-8 text truncated with an ellipsis so it fits within max_w. */
static void draw_truncated_text(cairo_t *cr, double x, double y, double max_w, const char *text) {
  if (!text || max_w <= 4) {
    return;
  }
  cairo_text_extents_t ext;
  cairo_text_extents(cr, text, &ext);
  if (ext.width <= max_w) {
    cairo_move_to(cr, x, y);
    cairo_show_text(cr, text);
    return;
  }
  char buf[256];
  g_strlcpy(buf, text, sizeof buf);
  size_t len = strlen(buf);
  while (len > 1) {
    len--;
    buf[len] = '\0';
    char trial[260];
    g_snprintf(trial, sizeof trial, "%s…", buf);
    cairo_text_extents(cr, trial, &ext);
    if (ext.width <= max_w) {
      cairo_move_to(cr, x, y);
      cairo_show_text(cr, trial);
      return;
    }
  }
  cairo_move_to(cr, x, y);
  cairo_show_text(cr, "…");
}

static void draw_graph(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer user_data) {
  (void)area;
  (void)width;
  (void)height;
  GraphState *st = user_data;
  cairo_set_source_rgb(cr, 0.12, 0.12, 0.14);
  cairo_paint(cr);

  if (st->n_nodes == 0) {
    cairo_set_source_rgb(cr, 0.7, 0.7, 0.7);
    cairo_select_font_face(cr, "monospace", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 12);
    cairo_move_to(cr, 16, 24);
    cairo_show_text(cr, st->status[0] ? st->status : "// Refresh Graph — needs CFG JSON (in-process / DumpFunctionGraphVibe)");
    return;
  }

  cairo_save(cr);
  cairo_translate(cr, st->pan_x, st->pan_y);
  cairo_scale(cr, st->zoom, st->zoom);

  // Edges — port-aware curves + oriented arrowheads (matches macOS canvas).
  for (int e = 0; e < st->n_edges; e++) {
    int a = find_node(st, st->edges[e].from);
    int b = find_node(st, st->edges[e].to);
    if (a < 0 || b < 0) {
      continue;
    }
    GNode *na = &st->nodes[a];
    GNode *nb = &st->nodes[b];
    double ax = na->x + NODE_W / 2, ay = na->y + na->h / 2;
    double bx = nb->x + NODE_W / 2, by = nb->y + nb->h / 2;
    double ddx = bx - ax, ddy = by - ay;
    double x1, y1, x2, y2, c1x, c1y, c2x, c2y;
    if (fabs(ddy) >= fabs(ddx) * 0.85) {
      if (ddy >= 0) {
        x1 = na->x + NODE_W / 2;
        y1 = na->y + na->h;
        x2 = nb->x + NODE_W / 2;
        y2 = nb->y;
      } else {
        x1 = na->x + NODE_W / 2;
        y1 = na->y;
        x2 = nb->x + NODE_W / 2;
        y2 = nb->y + nb->h;
      }
      c1x = x1;
      c1y = (y1 + y2) / 2;
      c2x = x2;
      c2y = (y1 + y2) / 2;
    } else {
      if (ddx >= 0) {
        x1 = na->x + NODE_W;
        y1 = na->y + na->h / 2;
        x2 = nb->x;
        y2 = nb->y + nb->h / 2;
      } else {
        x1 = na->x;
        y1 = na->y + na->h / 2;
        x2 = nb->x + NODE_W;
        y2 = nb->y + nb->h / 2;
      }
      c1x = (x1 + x2) / 2;
      c1y = y1;
      c2x = (x1 + x2) / 2;
      c2y = y2;
    }
    if (strcmp(st->edges[e].type, "conditional") == 0) {
      cairo_set_source_rgb(cr, 0.95, 0.55, 0.2);
    } else if (strcmp(st->edges[e].type, "fallthrough") == 0) {
      cairo_set_source_rgba(cr, 0.6, 0.6, 0.6, 0.8);
      double dashes[] = {4, 3};
      cairo_set_dash(cr, dashes, 2, 0);
    } else {
      cairo_set_source_rgb(cr, 0.35, 0.55, 0.95);
      cairo_set_dash(cr, NULL, 0, 0);
    }
    cairo_set_line_width(cr, 1.4);
    cairo_move_to(cr, x1, y1);
    cairo_curve_to(cr, c1x, c1y, c2x, c2y, x2, y2);
    cairo_stroke(cr);
    cairo_set_dash(cr, NULL, 0, 0);
    /* Arrowhead along final tangent. */
    double adx = x2 - c2x, ady = y2 - c2y;
    double alen = hypot(adx, ady);
    if (alen < 1e-3) {
      adx = 0;
      ady = 1;
      alen = 1;
    }
    adx /= alen;
    ady /= alen;
    double px = -ady, py = adx;
    double back_x = x2 - adx * 8, back_y = y2 - ady * 8;
    cairo_move_to(cr, x2, y2);
    cairo_line_to(cr, back_x + px * 4.5, back_y + py * 4.5);
    cairo_line_to(cr, back_x - px * 4.5, back_y - py * 4.5);
    cairo_close_path(cr);
    cairo_fill(cr);
  }

  // Nodes
  for (int i = 0; i < st->n_nodes; i++) {
    GNode *n = &st->nodes[i];
    if (strcmp(n->kind, "entry") == 0) {
      cairo_set_source_rgba(cr, 0.2, 0.4, 0.8, 0.25);
    } else {
      cairo_set_source_rgb(cr, 0.18, 0.18, 0.2);
    }
    cairo_rectangle(cr, n->x, n->y, NODE_W, n->h);
    cairo_fill_preserve(cr);
    if (i == st->selected) {
      cairo_set_source_rgb(cr, 0.3, 0.7, 1.0);
      cairo_set_line_width(cr, 2.0);
    } else {
      cairo_set_source_rgb(cr, 0.4, 0.4, 0.45);
      cairo_set_line_width(cr, 1.0);
    }
    cairo_stroke(cr);

    /* Clip text to the node box so long labels/insns don't spill past the right edge. */
    cairo_save(cr);
    cairo_rectangle(cr, n->x + 1, n->y + 1, NODE_W - 2, n->h - 2);
    cairo_clip(cr);

    cairo_set_source_rgb(cr, 0.95, 0.95, 0.95);
    cairo_select_font_face(cr, "monospace", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 11);
    char title[192];
    g_snprintf(title, sizeof title, "%s", strcmp(n->kind, "entry") == 0 ? n->label : n->addr);
    draw_truncated_text(cr, n->x + 6, n->y + 14, NODE_W - 12, title);

    cairo_select_font_face(cr, "monospace", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 10);
    cairo_set_source_rgb(cr, 0.75, 0.75, 0.78);
    for (int j = 0; j < n->insn_count; j++) {
      draw_truncated_text(cr, n->x + 6, n->y + 28 + j * 12, NODE_W - 12, n->insns[j]);
    }
    cairo_restore(cr);
  }
  cairo_restore(cr);
}

static void on_refresh(GtkButton *btn, gpointer user_data) {
  (void)btn;
  GraphState *st = user_data;
  const char *base = g_getenv("GHIDRA_MCP_URL");
  if (!base || !base[0]) {
    base = "http://127.0.0.1:8089";
  }
  /* Prefer CFG-shaped analyze_control_flow; DumpFunctionGraphVibe JSON also works if pasted via env. */
  const char *env_json = g_getenv("GHIDRA_VIBE_FUNCTION_GRAPH_JSON");
  char *body = NULL;
  if (env_json && env_json[0]) {
    body = g_strdup(env_json);
  } else {
    body = vibe_mcp_get_q(base, "analyze_control_flow", "address=");
  }
  if (body && parse_cfg_json(st, body)) {
    g_snprintf(st->status, sizeof st->status, "%s — %d blocks, %d edges", st->function, st->n_nodes,
               st->n_edges);
  } else {
    clear_graph(st);
    g_strlcpy(st->status, "No CFG JSON yet. Use in-process function_graph or DumpFunctionGraphVibe.",
              sizeof st->status);
  }
  gtk_label_set_text(GTK_LABEL(st->status_lbl), st->status);
  gtk_widget_queue_draw(st->drawing);
  g_free(body);
}

static void on_drag_begin(GtkGestureDrag *gesture, double x, double y, gpointer user_data) {
  (void)gesture;
  GraphState *st = user_data;
  double cx = (x - st->pan_x) / st->zoom;
  double cy = (y - st->pan_y) / st->zoom;
  st->drag_moved = 0;
  st->drag_start_x = x;
  st->drag_start_y = y;
  st->pan_at_drag_x = st->pan_x;
  st->pan_at_drag_y = st->pan_y;
  st->drag_node = -1;
  st->selected = -1;
  for (int i = st->n_nodes - 1; i >= 0; i--) {
    GNode *n = &st->nodes[i];
    if (cx >= n->x && cx <= n->x + NODE_W && cy >= n->y && cy <= n->y + n->h) {
      st->selected = i;
      st->drag_node = i;
      st->drag_grab_x = cx - n->x;
      st->drag_grab_y = cy - n->y;
      break;
    }
  }
  gtk_widget_queue_draw(st->drawing);
}

static void on_drag_update(GtkGestureDrag *gesture, double offset_x, double offset_y, gpointer user_data) {
  (void)gesture;
  GraphState *st = user_data;
  if (fabs(offset_x) > 2 || fabs(offset_y) > 2) {
    st->drag_moved = 1;
  }
  if (st->drag_node >= 0 && st->drag_node < st->n_nodes) {
    double x = st->drag_start_x + offset_x;
    double y = st->drag_start_y + offset_y;
    double cx = (x - st->pan_x) / st->zoom;
    double cy = (y - st->pan_y) / st->zoom;
    GNode *n = &st->nodes[st->drag_node];
    n->x = cx - st->drag_grab_x;
    n->y = cy - st->drag_grab_y;
    if (n->x < 4) {
      n->x = 4;
    }
    if (n->y < 4) {
      n->y = 4;
    }
    if (n->x + NODE_W + PAD > st->content_w) {
      st->content_w = n->x + NODE_W + PAD;
    }
    if (n->y + n->h + PAD > st->content_h) {
      st->content_h = n->y + n->h + PAD;
    }
  } else {
    st->pan_x = st->pan_at_drag_x + offset_x;
    st->pan_y = st->pan_at_drag_y + offset_y;
  }
  gtk_widget_queue_draw(st->drawing);
}

static void on_drag_end(GtkGestureDrag *gesture, double offset_x, double offset_y, gpointer user_data) {
  (void)gesture;
  (void)offset_x;
  (void)offset_y;
  GraphState *st = user_data;
  st->drag_node = -1;
  (void)st->drag_moved;
}

GtkWidget *vibe_provider_function_graph(void) {
  GraphState *st = g_new0(GraphState, 1);
  st->zoom = 1.0;
  st->selected = -1;
  st->drag_node = -1;
  g_strlcpy(st->status, "// Select a function context, then Refresh Graph", sizeof st->status);

  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  vibe_a11y_bind(root, "ghidra.vibe.provider.function_graph");

  GtkWidget *tb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_widget_set_margin_start(tb, 4);
  gtk_widget_set_margin_end(tb, 4);
  gtk_widget_set_margin_top(tb, 4);
  GtkWidget *btn = gtk_button_new_with_label("Refresh Graph");
  vibe_a11y_bind(btn, "ghidra.vibe.provider.function_graph.refresh");
  g_signal_connect(btn, "clicked", G_CALLBACK(on_refresh), st);
  gtk_box_append(GTK_BOX(tb), btn);
  st->status_lbl = gtk_label_new(st->status);
  gtk_label_set_xalign(GTK_LABEL(st->status_lbl), 0);
  gtk_widget_set_hexpand(st->status_lbl, TRUE);
  gtk_box_append(GTK_BOX(tb), st->status_lbl);
  gtk_box_append(GTK_BOX(root), tb);

  st->drawing = gtk_drawing_area_new();
  gtk_widget_set_hexpand(st->drawing, TRUE);
  gtk_widget_set_vexpand(st->drawing, TRUE);
  gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(st->drawing), draw_graph, st, NULL);
  vibe_a11y_bind(st->drawing, "ghidra.vibe.provider.function_graph.body");
  GtkGesture *drag = gtk_gesture_drag_new();
  g_signal_connect(drag, "drag-begin", G_CALLBACK(on_drag_begin), st);
  g_signal_connect(drag, "drag-update", G_CALLBACK(on_drag_update), st);
  g_signal_connect(drag, "drag-end", G_CALLBACK(on_drag_end), st);
  gtk_widget_add_controller(st->drawing, GTK_EVENT_CONTROLLER(drag));
  gtk_box_append(GTK_BOX(root), st->drawing);

  g_object_set_data_full(G_OBJECT(root), "graph-state", st, g_free);
  return root;
}

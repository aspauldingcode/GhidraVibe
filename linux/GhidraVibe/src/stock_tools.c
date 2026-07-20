/* Stock Tool Chest shells — Debugger / Emulator / Version Tracking (GTK). */
#include "a11y.h"
#include "dock.h"
#include "mcp_client.h"
#include "stock_tools.h"

#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

static void append_provider_row(GtkWidget *list, const char *a11y_id, const char *label) {
  GtkWidget *row = gtk_label_new(label);
  gtk_widget_set_halign(row, GTK_ALIGN_START);
  gtk_widget_set_margin_start(row, 4);
  gtk_widget_set_margin_end(row, 4);
  gtk_widget_set_margin_top(row, 2);
  gtk_widget_set_margin_bottom(row, 2);
  vibe_a11y_set(row, a11y_id);
  gtk_list_box_append(GTK_LIST_BOX(list), row);
}

static GtkWidget *make_tool_page(const char *title, const char *a11y_root, const char *blurb,
                                 const char *const *provider_ids, const char *const *provider_labels,
                                 size_t n_providers) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_set_margin_start(box, 12);
  gtk_widget_set_margin_end(box, 12);
  gtk_widget_set_margin_top(box, 12);
  gtk_widget_set_margin_bottom(box, 12);
  vibe_a11y_set(box, a11y_root);

  GtkWidget *hdr = gtk_label_new(title);
  gtk_widget_add_css_class(hdr, "title-2");
  gtk_widget_set_halign(hdr, GTK_ALIGN_START);
  gtk_box_append(GTK_BOX(box), hdr);

  GtkWidget *info = gtk_label_new(blurb);
  gtk_label_set_wrap(GTK_LABEL(info), TRUE);
  gtk_widget_set_halign(info, GTK_ALIGN_START);
  gtk_box_append(GTK_BOX(box), info);

  GtkWidget *paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  GtkWidget *scrolled_list = gtk_scrolled_window_new();
  GtkWidget *list = gtk_list_box_new();
  for (size_t i = 0; i < n_providers; i++) {
    append_provider_row(list, provider_ids[i], provider_labels[i]);
  }
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled_list), list);
  gtk_widget_set_size_request(scrolled_list, 200, -1);
  gtk_paned_set_start_child(GTK_PANED(paned), scrolled_list);

  GtkWidget *scrolled = gtk_scrolled_window_new();
  GtkWidget *tv = gtk_text_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(tv), FALSE);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(tv), TRUE);
  GtkTextBuffer *buf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(tv));
  gtk_text_buffer_set_text(
      buf,
      "// Stock tool shell — select a provider; toolbar actions call program engine when available\n",
      -1);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled), tv);
  gtk_widget_set_vexpand(scrolled, TRUE);
  gtk_paned_set_end_child(GTK_PANED(paned), scrolled);
  gtk_widget_set_vexpand(paned, TRUE);
  gtk_box_append(GTK_BOX(box), paned);
  return box;
}

GtkWidget *vibe_stock_debugger_page(void) {
  static const char *ids[] = {
      "ghidra.vibe.debugger.provider.listing",
      "ghidra.vibe.debugger.provider.decompiler",
      "ghidra.vibe.debugger.provider.bytes",
      "ghidra.vibe.debugger.provider.console",
      "ghidra.vibe.debugger.provider.breakpoints",
      "ghidra.vibe.debugger.provider.stack",
      "ghidra.vibe.debugger.provider.threads",
      "ghidra.vibe.debugger.provider.watches",
      "ghidra.vibe.debugger.provider.modules",
      "ghidra.vibe.debugger.provider.memory",
      "ghidra.vibe.debugger.provider.registers",
      "ghidra.vibe.debugger.provider.pcode_stepper",
      "ghidra.vibe.debugger.toolbar.tracermi_connect",
      "ghidra.vibe.debugger.toolbar.launch",
      "ghidra.vibe.debugger.toolbar.step_into",
      "ghidra.vibe.debugger.toolbar.save",
  };
  static const char *labels[] = {
      "Dynamic / Listing", "Decompile", "Bytes", "Console", "Breakpoints", "Stack",
      "Threads",           "Watches",   "Modules", "Memory", "Registers", "Pcode Stepper",
      "TraceRmi Connect",  "Launch",    "Step Into", "Save",
  };
  return make_tool_page(
      "Debugger", "ghidra.vibe.debugger",
      "Stock Debugger tool. Providers reuse CodeBrowser panes or debugger_list; "
      "TraceRmi Connect / Launch / Step via in-process engine.",
      ids, labels, sizeof(ids) / sizeof(ids[0]));
}

GtkWidget *vibe_stock_emulator_page(void) {
  static const char *ids[] = {
      "ghidra.vibe.emulator.provider.listing",
      "ghidra.vibe.emulator.provider.decompiler",
      "ghidra.vibe.emulator.provider.registers",
      "ghidra.vibe.emulator.provider.stack",
      "ghidra.vibe.emulator.provider.threads",
      "ghidra.vibe.emulator.provider.watches",
      "ghidra.vibe.emulator.provider.objects",
      "ghidra.vibe.emulator.provider.pcode_stepper",
      "ghidra.vibe.emulator.provider.memory",
      "ghidra.vibe.emulator.toolbar.emulate",
      "ghidra.vibe.emulator.toolbar.step",
      "ghidra.vibe.emulator.toolbar.skip",
      "ghidra.vibe.emulator.toolbar.finish",
      "ghidra.vibe.emulator.toolbar.save",
  };
  static const char *labels[] = {
      "Dynamic / Listing", "Decompile", "Registers", "Stack", "Threads", "Watches", "Objects",
      "Pcode Stepper",     "Memory",    "Emulate",   "Step",  "Skip",    "Finish",  "Save",
  };
  return make_tool_page(
      "Emulator", "ghidra.vibe.emulator",
      "Stock Emulator tool. Emulate / Step / Skip / Finish via in-process engine control surface.",
      ids, labels, sizeof(ids) / sizeof(ids[0]));
}

GtkWidget *vibe_stock_vt_page(void) {
  static const char *ids[] = {
      "ghidra.vibe.version_tracking.provider.version_tracking_matches",
      "ghidra.vibe.version_tracking.provider.version_tracking_markup_items",
      "ghidra.vibe.version_tracking.provider.version_tracking_implied_matches",
      "ghidra.vibe.version_tracking.toolbar.create_session",
      "ghidra.vibe.version_tracking.toolbar.run_correlators",
      "ghidra.vibe.version_tracking.toolbar.apply_markup",
      "ghidra.vibe.version_tracking.toolbar.save_session",
  };
  static const char *labels[] = {
      "VT Matches", "VT Markup Items", "VT Implied Matches", "Create Session",
      "Run Correlators", "Apply Markup", "Save Session",
  };
  return make_tool_page(
      "Version Tracking", "ghidra.vibe.version_tracking",
      "Stock Version Tracking tool. Create Session → Run Correlators → Apply Markup.", ids, labels,
      sizeof(ids) / sizeof(ids[0]));
}

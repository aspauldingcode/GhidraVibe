#pragma once
#include <gtk/gtk.h>

GtkWidget *vibe_build_codebrowser_dock(void);
GtkWidget *vibe_build_project_window(void);
GtkWidget *vibe_provider_label(const char *title, const char *a11y_id);
GtkWidget *vibe_provider_mcp(const char *title, const char *a11y_id, const char *mcp_path,
                             gboolean use_vibe);
/** Agent sidebar stub — Ollama probe + vibe MCP playbooks (parity with macOS). */
GtkWidget *vibe_provider_agent(void);

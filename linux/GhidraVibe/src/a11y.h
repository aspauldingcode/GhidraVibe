#pragma once
#include <gtk/gtk.h>

typedef struct {
  char *id;
  char *label;
  char *hint;
} VibeA11yEntry;

void vibe_a11y_load_catalog(const char *path);
const VibeA11yEntry *vibe_a11y_lookup(const char *id);
void vibe_a11y_bind(GtkWidget *widget, const char *id);
void vibe_a11y_free(void);

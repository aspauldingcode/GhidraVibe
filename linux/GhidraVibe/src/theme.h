/* GhidraVibe GTK — Theme picker and appearance settings */
#ifndef VIBE_THEME_H
#define VIBE_THEME_H

#include <gtk/gtk.h>

typedef enum {
  VIBE_THEME_LIGHT,
  VIBE_THEME_DARK,
  VIBE_THEME_SYSTEM,
} VibeThemeMode;

/* Initialize theme system */
void vibe_theme_init(void);

/* Get/set current theme mode */
VibeThemeMode vibe_theme_get_mode(void);
void vibe_theme_set_mode(VibeThemeMode mode);

/* Show theme picker dialog */
void vibe_theme_show_picker(GtkWindow *parent);

/* Apply theme to widget */
void vibe_theme_apply_to_widget(GtkWidget *widget);

#endif

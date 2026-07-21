/* GhidraVibe GTK — Splash screen and user agreement */
#ifndef VIBE_SPLASH_H
#define VIBE_SPLASH_H

#include <gtk/gtk.h>

/* Show splash screen with progress during startup */
GtkWidget *vibe_splash_create(void);
void vibe_splash_set_progress(GtkWidget *splash, const char *message, double fraction);
void vibe_splash_destroy(GtkWidget *splash);

/* Show user agreement dialog on first run */
gboolean vibe_show_agreement_if_needed(GtkWindow *parent);

#endif

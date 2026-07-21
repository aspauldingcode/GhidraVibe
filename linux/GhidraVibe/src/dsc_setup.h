/* GhidraVibe GTK — DSC/IPSW setup dialog for Linux */
#ifndef VIBE_DSC_SETUP_H
#define VIBE_DSC_SETUP_H

#include <gtk/gtk.h>

/* Show DSC/IPSW setup dialog (Linux-specific) */
void vibe_dsc_show_setup_dialog(GtkWindow *parent);

/* Check if DSC cache is available */
gboolean vibe_dsc_is_cache_available(void);

/* Get cache path (or NULL if not available) */
char *vibe_dsc_get_cache_path(void);

#endif

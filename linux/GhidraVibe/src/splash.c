/* GhidraVibe GTK — Splash screen and user agreement */
#include "splash.h"
#include <stdlib.h>
#include <string.h>

#define AGREEMENT_TEXT                                                                                     \
  "GhidraVibe — Ghidra with Native UI\n\n"                                                                 \
  "This software is built upon Ghidra, an open-source reverse engineering tool "                          \
  "developed by the National Security Agency (NSA). GhidraVibe is not affiliated with "                   \
  "or endorsed by the NSA or the Ghidra project.\n\n"                                                      \
  "GhidraVibe is licensed under the Apache License 2.0. By using this software, you "                     \
  "agree to comply with the terms of the Apache 2.0 license and understand that this "                    \
  "software is provided AS IS, WITHOUT WARRANTY OF ANY KIND.\n\n"                                         \
  "Key points:\n"                                                                                          \
  "• This software includes components from the Ghidra project\n"                                          \
  "• Use at your own risk for reverse engineering tasks\n"                                                \
  "• Comply with applicable laws and regulations\n"                                                        \
  "• See LICENSE file for full terms\n\n"                                                                  \
  "Do you accept these terms?"

static char *get_config_dir(void) {
  const char *xdg_config = g_getenv("XDG_CONFIG_HOME");
  if (xdg_config) {
    return g_build_filename(xdg_config, "ghidra-vibe", NULL);
  }
  const char *home = g_getenv("HOME");
  if (!home)
    home = "/tmp";
  return g_build_filename(home, ".config", "ghidra-vibe", NULL);
}

static char *get_agreement_file(void) {
  char *config_dir = get_config_dir();
  char *file = g_build_filename(config_dir, "agreement-accepted", NULL);
  g_free(config_dir);
  return file;
}

static gboolean has_accepted_agreement(void) {
  char *file = get_agreement_file();
  gboolean exists = g_file_test(file, G_FILE_TEST_EXISTS);
  g_free(file);
  return exists;
}

static void mark_agreement_accepted(void) {
  char *file = get_agreement_file();
  char *dir = g_path_get_dirname(file);
  g_mkdir_with_parents(dir, 0755);
  FILE *f = fopen(file, "w");
  if (f) {
    fprintf(f, "accepted\n");
    fclose(f);
  }
  g_free(dir);
  g_free(file);
}

gboolean vibe_show_agreement_if_needed(GtkWindow *parent) {
  if (has_accepted_agreement()) {
    return TRUE;
  }

  GtkWidget *dialog =
      gtk_message_dialog_new(parent, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_NONE, "%s",
                             AGREEMENT_TEXT);
  gtk_window_set_title(GTK_WINDOW(dialog), "GhidraVibe — User Agreement");
  gtk_dialog_add_button(GTK_DIALOG(dialog), "_Decline", GTK_RESPONSE_REJECT);
  gtk_dialog_add_button(GTK_DIALOG(dialog), "_Accept", GTK_RESPONSE_ACCEPT);

  int response = gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);

  if (response == GTK_RESPONSE_ACCEPT) {
    mark_agreement_accepted();
    return TRUE;
  }
  return FALSE;
}

GtkWidget *vibe_splash_create(void) {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), "GhidraVibe");
  gtk_window_set_default_size(GTK_WINDOW(window), 400, 200);
  gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
  gtk_window_set_decorated(GTK_WINDOW(window), FALSE);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_container_set_border_width(GTK_CONTAINER(box), 24);
  gtk_container_add(GTK_CONTAINER(window), box);

  GtkWidget *logo = gtk_label_new(NULL);
  gtk_label_set_markup(GTK_LABEL(logo),
                       "<span size='xx-large' weight='bold'>🐉 GhidraVibe</span>");
  gtk_box_pack_start(GTK_BOX(box), logo, FALSE, FALSE, 0);

  GtkWidget *subtitle = gtk_label_new("Native UI for Ghidra");
  gtk_box_pack_start(GTK_BOX(box), subtitle, FALSE, FALSE, 0);

  GtkWidget *progress = gtk_progress_bar_new();
  gtk_progress_bar_set_show_text(GTK_PROGRESS_BAR(progress), TRUE);
  gtk_box_pack_end(GTK_BOX(box), progress, FALSE, FALSE, 0);

  g_object_set_data(G_OBJECT(window), "progress", progress);

  gtk_widget_show_all(window);
  return window;
}

void vibe_splash_set_progress(GtkWidget *splash, const char *message, double fraction) {
  if (!splash)
    return;
  GtkWidget *progress = g_object_get_data(G_OBJECT(splash), "progress");
  if (progress) {
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(progress), fraction);
    gtk_progress_bar_set_text(GTK_PROGRESS_BAR(progress), message);
  }
  // Process events to update UI
  while (gtk_events_pending()) {
    gtk_main_iteration();
  }
}

void vibe_splash_destroy(GtkWidget *splash) {
  if (splash) {
    gtk_widget_destroy(splash);
  }
}

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

typedef struct {
  GMainLoop *loop;
  int response;
} DialogRunData;

static void on_dialog_response(GtkDialog *dialog, int response_id, gpointer user_data) {
  (void)dialog;
  DialogRunData *data = user_data;
  data->response = response_id;
  if (g_main_loop_is_running(data->loop))
    g_main_loop_quit(data->loop);
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

  /* GTK4 dropped gtk_dialog_run(); block on a nested main loop until "response". */
  DialogRunData run_data = {g_main_loop_new(NULL, FALSE), GTK_RESPONSE_REJECT};
  g_signal_connect(dialog, "response", G_CALLBACK(on_dialog_response), &run_data);
  gtk_window_present(GTK_WINDOW(dialog));
  g_main_loop_run(run_data.loop);
  g_main_loop_unref(run_data.loop);

  int response = run_data.response;
  gtk_window_destroy(GTK_WINDOW(dialog));

  if (response == GTK_RESPONSE_ACCEPT) {
    mark_agreement_accepted();
    return TRUE;
  }
  return FALSE;
}

GtkWidget *vibe_splash_create(void) {
  GtkWidget *window = gtk_window_new();
  gtk_window_set_title(GTK_WINDOW(window), "GhidraVibe");
  gtk_window_set_default_size(GTK_WINDOW(window), 400, 200);
  gtk_window_set_decorated(GTK_WINDOW(window), FALSE);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_margin_start(box, 24);
  gtk_widget_set_margin_end(box, 24);
  gtk_widget_set_margin_top(box, 24);
  gtk_widget_set_margin_bottom(box, 24);
  gtk_window_set_child(GTK_WINDOW(window), box);

  GtkWidget *logo = gtk_label_new(NULL);
  gtk_label_set_markup(GTK_LABEL(logo),
                       "<span size='xx-large' weight='bold'>🐉 GhidraVibe</span>");
  gtk_box_append(GTK_BOX(box), logo);

  GtkWidget *subtitle = gtk_label_new("Native UI for Ghidra");
  gtk_box_append(GTK_BOX(box), subtitle);

  GtkWidget *progress = gtk_progress_bar_new();
  gtk_progress_bar_set_show_text(GTK_PROGRESS_BAR(progress), TRUE);
  gtk_widget_set_vexpand(progress, FALSE);
  gtk_widget_set_valign(progress, GTK_ALIGN_END);
  gtk_box_append(GTK_BOX(box), progress);

  g_object_set_data(G_OBJECT(window), "progress", progress);

  gtk_widget_set_visible(window, TRUE);
  gtk_window_present(GTK_WINDOW(window));
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
  /* GTK4 dropped gtk_events_pending()/gtk_main_iteration(); drain via GLib directly. */
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
}

void vibe_splash_destroy(GtkWidget *splash) {
  if (splash) {
    gtk_window_destroy(GTK_WINDOW(splash));
  }
}

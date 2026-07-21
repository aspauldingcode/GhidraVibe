/* GhidraVibe GTK — DSC/IPSW setup dialog for Linux */
#include "dsc_setup.h"
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static char *check_cache_locations(void) {
  const char *env_cache = g_getenv("GHIDRA_VIBE_IPSW_CACHE");
  if (env_cache && g_file_test(env_cache, G_FILE_TEST_EXISTS)) {
    return g_strdup(env_cache);
  }

  const char *home = g_getenv("HOME");
  if (!home)
    home = "/tmp";
  const char *xdg_data = g_getenv("XDG_DATA_HOME");

  char *candidates[3];
  if (xdg_data) {
    candidates[0] = g_build_filename(xdg_data, "ghidra-vibe", "ipsw-cache",
                                     "dyld_shared_cache_arm64e", NULL);
  } else {
    candidates[0] = g_build_filename(home, ".local", "share", "ghidra-vibe", "ipsw-cache",
                                     "dyld_shared_cache_arm64e", NULL);
  }
  candidates[1] =
      g_build_filename(home, "Documents", "GhidraVibe", "ipsw-cache", "dyld_shared_cache_arm64e", NULL);
  candidates[2] = NULL;

  for (int i = 0; candidates[i]; i++) {
    if (g_file_test(candidates[i], G_FILE_TEST_EXISTS)) {
      char *result = g_strdup(candidates[i]);
      for (int j = 0; candidates[j]; j++)
        g_free(candidates[j]);
      return result;
    }
  }

  for (int i = 0; candidates[i]; i++)
    g_free(candidates[i]);
  return NULL;
}

gboolean vibe_dsc_is_cache_available(void) {
  char *path = check_cache_locations();
  gboolean available = (path != NULL);
  g_free(path);
  return available;
}

char *vibe_dsc_get_cache_path(void) { return check_cache_locations(); }

static void run_setup_script_async(GtkWidget *progress_bar, GtkWidget *status_label) {
  gtk_label_set_text(GTK_LABEL(status_label), "Running ghidra-vibe-dyld setup-ipsw...");
  gtk_progress_bar_pulse(GTK_PROGRESS_BAR(progress_bar));

  // Run in background
  if (!g_spawn_command_line_async("xterm -e 'ghidra-vibe-dyld setup-ipsw; echo Press Enter to close; read'",
                                  NULL)) {
    // Fallback: run without terminal
    g_spawn_command_line_async("ghidra-vibe-dyld setup-ipsw", NULL);
  }

  gtk_label_set_text(GTK_LABEL(status_label),
                     "Setup script launched in terminal. Please follow the instructions.");
}

typedef struct {
  GtkWidget *progress_bar;
  GtkWidget *status_label;
} AutoSetupCtx;

static void on_auto_setup_clicked(GtkButton *button, gpointer user_data) {
  (void)button;
  AutoSetupCtx *ctx = user_data;
  run_setup_script_async(ctx->progress_bar, ctx->status_label);
}

typedef struct {
  GMainLoop *loop;
} DialogRunData;

static void on_setup_dialog_response(GtkDialog *dialog, int response_id, gpointer user_data) {
  (void)dialog;
  (void)response_id;
  DialogRunData *data = user_data;
  if (g_main_loop_is_running(data->loop))
    g_main_loop_quit(data->loop);
}

void vibe_dsc_show_setup_dialog(GtkWindow *parent) {
  GtkWidget *dialog = gtk_dialog_new_with_buttons(
      "DSC/IPSW Setup", parent, GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT, "_Close",
      GTK_RESPONSE_CLOSE, NULL);
  gtk_window_set_default_size(GTK_WINDOW(dialog), 500, 350);

  /* In GTK4, GtkDialog's content area is itself a GtkBox — append to it directly. */
  GtkWidget *content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
  gtk_widget_set_margin_start(content, 16);
  gtk_widget_set_margin_end(content, 16);
  gtk_widget_set_margin_top(content, 16);
  gtk_widget_set_margin_bottom(content, 16);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_box_append(GTK_BOX(content), box);

  // Header
  GtkWidget *header = gtk_label_new(NULL);
  gtk_label_set_markup(
      GTK_LABEL(header),
      "<span size='large' weight='bold'>iOS Dyld Shared Cache Setup</span>");
  gtk_label_set_xalign(GTK_LABEL(header), 0.0);
  gtk_box_append(GTK_BOX(box), header);

  // Check current status
  char *cache_path = check_cache_locations();
  if (cache_path) {
    GtkWidget *status = gtk_label_new(NULL);
    char *markup = g_strdup_printf("<span color='green'>✓ Cache found:</span> %s", cache_path);
    gtk_label_set_markup(GTK_LABEL(status), markup);
    gtk_label_set_wrap(GTK_LABEL(status), TRUE);
    gtk_label_set_xalign(GTK_LABEL(status), 0.0);
    gtk_box_append(GTK_BOX(box), status);
    g_free(markup);
    g_free(cache_path);
  } else {
    GtkWidget *status = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(status), "<span color='red'>✗ No cache found</span>");
    gtk_label_set_xalign(GTK_LABEL(status), 0.0);
    gtk_box_append(GTK_BOX(box), status);
  }

  // Instructions
  GtkWidget *instructions = gtk_label_new(
      "On Linux, GhidraVibe requires an IPSW-extracted dyld shared cache.\n\n"
      "Setup options:\n"
      "1. Automatic: Click 'Auto Setup' below\n"
      "2. Manual: Download iOS IPSW from https://ipsw.me and extract\n\n"
      "Manual extraction:\n"
      "  nix shell nixpkgs#ipsw -c \\\n"
      "    ipsw dyld extract <ipsw-file> \\\n"
      "    --output ~/.local/share/ghidra-vibe/ipsw-cache\n\n"
      "Or set environment variable:\n"
      "  export GHIDRA_VIBE_IPSW_CACHE=<path-to-cache>");
  gtk_label_set_wrap(GTK_LABEL(instructions), TRUE);
  gtk_label_set_xalign(GTK_LABEL(instructions), 0.0);
  gtk_label_set_selectable(GTK_LABEL(instructions), TRUE);
  gtk_widget_set_vexpand(instructions, TRUE);
  gtk_box_append(GTK_BOX(box), instructions);

  // Progress area
  GtkWidget *progress_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  GtkWidget *progress_bar = gtk_progress_bar_new();
  GtkWidget *status_label = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(status_label), 0.0);
  gtk_box_append(GTK_BOX(progress_box), status_label);
  gtk_box_append(GTK_BOX(progress_box), progress_bar);
  gtk_box_append(GTK_BOX(box), progress_box);

  // Buttons — GtkButtonBox was removed in GTK4; use a plain start-aligned GtkBox.
  GtkWidget *button_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_widget_set_halign(button_box, GTK_ALIGN_START);

  GtkWidget *auto_btn = gtk_button_new_with_label("Auto Setup");
  GtkWidget *manual_btn = gtk_button_new_with_label("Manual Instructions");

  AutoSetupCtx *auto_ctx = g_new0(AutoSetupCtx, 1);
  auto_ctx->progress_bar = progress_bar;
  auto_ctx->status_label = status_label;
  g_signal_connect_data(auto_btn, "clicked", G_CALLBACK(on_auto_setup_clicked), auto_ctx,
                        (GClosureNotify)g_free, 0);

  gtk_box_append(GTK_BOX(button_box), auto_btn);
  gtk_box_append(GTK_BOX(button_box), manual_btn);
  gtk_box_append(GTK_BOX(box), button_box);

  /* GTK4 dropped gtk_dialog_run(); block on a nested main loop until "response". */
  DialogRunData run_data = {g_main_loop_new(NULL, FALSE)};
  g_signal_connect(dialog, "response", G_CALLBACK(on_setup_dialog_response), &run_data);
  gtk_window_present(GTK_WINDOW(dialog));
  g_main_loop_run(run_data.loop);
  g_main_loop_unref(run_data.loop);

  gtk_window_destroy(GTK_WINDOW(dialog));
}

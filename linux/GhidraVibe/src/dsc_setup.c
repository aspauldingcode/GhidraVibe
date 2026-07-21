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

static void run_setup_script_async(GtkWidget *dialog, GtkWidget *progress_bar, GtkWidget *status_label) {
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

void vibe_dsc_show_setup_dialog(GtkWindow *parent) {
  GtkWidget *dialog = gtk_dialog_new_with_buttons(
      "DSC/IPSW Setup", parent, GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT, "_Close",
      GTK_RESPONSE_CLOSE, NULL);
  gtk_window_set_default_size(GTK_WINDOW(dialog), 500, 350);

  GtkWidget *content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
  gtk_container_set_border_width(GTK_CONTAINER(content), 16);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_container_add(GTK_CONTAINER(content), box);

  // Header
  GtkWidget *header = gtk_label_new(NULL);
  gtk_label_set_markup(
      GTK_LABEL(header),
      "<span size='large' weight='bold'>iOS Dyld Shared Cache Setup</span>");
  gtk_label_set_xalign(GTK_LABEL(header), 0.0);
  gtk_box_pack_start(GTK_BOX(box), header, FALSE, FALSE, 0);

  // Check current status
  char *cache_path = check_cache_locations();
  if (cache_path) {
    GtkWidget *status = gtk_label_new(NULL);
    char *markup = g_strdup_printf("<span color='green'>✓ Cache found:</span> %s", cache_path);
    gtk_label_set_markup(GTK_LABEL(status), markup);
    gtk_label_set_line_wrap(GTK_LABEL(status), TRUE);
    gtk_label_set_xalign(GTK_LABEL(status), 0.0);
    gtk_box_pack_start(GTK_BOX(box), status, FALSE, FALSE, 0);
    g_free(markup);
    g_free(cache_path);
  } else {
    GtkWidget *status = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(status), "<span color='red'>✗ No cache found</span>");
    gtk_label_set_xalign(GTK_LABEL(status), 0.0);
    gtk_box_pack_start(GTK_BOX(box), status, FALSE, FALSE, 0);
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
  gtk_label_set_line_wrap(GTK_LABEL(instructions), TRUE);
  gtk_label_set_xalign(GTK_LABEL(instructions), 0.0);
  gtk_label_set_selectable(GTK_LABEL(instructions), TRUE);
  gtk_box_pack_start(GTK_BOX(box), instructions, TRUE, TRUE, 0);

  // Progress area
  GtkWidget *progress_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  GtkWidget *progress_bar = gtk_progress_bar_new();
  GtkWidget *status_label = gtk_label_new("");
  gtk_label_set_xalign(GTK_LABEL(status_label), 0.0);
  gtk_box_pack_start(GTK_BOX(progress_box), status_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(progress_box), progress_bar, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), progress_box, FALSE, FALSE, 0);

  // Buttons
  GtkWidget *button_box = gtk_button_box_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_button_box_set_layout(GTK_BUTTON_BOX(button_box), GTK_BUTTONBOX_START);
  gtk_box_set_spacing(GTK_BOX(button_box), 8);

  GtkWidget *auto_btn = gtk_button_new_with_label("Auto Setup");
  GtkWidget *manual_btn = gtk_button_new_with_label("Manual Instructions");

  g_signal_connect_swapped(auto_btn, "clicked", G_CALLBACK(run_setup_script_async),
                            g_object_new(G_TYPE_OBJECT, "dialog", dialog, "progress", progress_bar, "status",
                                         status_label, NULL));

  gtk_container_add(GTK_CONTAINER(button_box), auto_btn);
  gtk_container_add(GTK_CONTAINER(button_box), manual_btn);
  gtk_box_pack_start(GTK_BOX(box), button_box, FALSE, FALSE, 0);

  gtk_widget_show_all(dialog);
  gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
}

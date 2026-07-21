/* GhidraVibe GTK — Theme picker and appearance settings */
#include "theme.h"
#include <stdlib.h>
#include <string.h>

static VibeThemeMode current_mode = VIBE_THEME_SYSTEM;
static GtkSettings *gtk_settings = NULL;

static char *get_config_file(void) {
  const char *xdg_config = g_getenv("XDG_CONFIG_HOME");
  char *config_dir;
  if (xdg_config) {
    config_dir = g_build_filename(xdg_config, "ghidra-vibe", NULL);
  } else {
    const char *home = g_getenv("HOME");
    if (!home)
      home = "/tmp";
    config_dir = g_build_filename(home, ".config", "ghidra-vibe", NULL);
  }
  char *file = g_build_filename(config_dir, "theme.conf", NULL);
  g_free(config_dir);
  return file;
}

static void save_theme_config(void) {
  char *file = get_config_file();
  char *dir = g_path_get_dirname(file);
  g_mkdir_with_parents(dir, 0755);

  FILE *f = fopen(file, "w");
  if (f) {
    const char *mode_str = "system";
    if (current_mode == VIBE_THEME_LIGHT)
      mode_str = "light";
    else if (current_mode == VIBE_THEME_DARK)
      mode_str = "dark";
    fprintf(f, "mode=%s\n", mode_str);
    fclose(f);
  }

  g_free(dir);
  g_free(file);
}

static void load_theme_config(void) {
  char *file = get_config_file();
  FILE *f = fopen(file, "r");
  if (f) {
    char line[256];
    if (fgets(line, sizeof(line), f)) {
      if (strstr(line, "light"))
        current_mode = VIBE_THEME_LIGHT;
      else if (strstr(line, "dark"))
        current_mode = VIBE_THEME_DARK;
      else
        current_mode = VIBE_THEME_SYSTEM;
    }
    fclose(f);
  }
  g_free(file);
}

static void apply_theme_mode(void) {
  if (!gtk_settings) {
    gtk_settings = gtk_settings_get_default();
  }

  gboolean prefer_dark = FALSE;
  if (current_mode == VIBE_THEME_DARK) {
    prefer_dark = TRUE;
  } else if (current_mode == VIBE_THEME_LIGHT) {
    prefer_dark = FALSE;
  } else {
    // SYSTEM: check if system prefers dark theme
    g_object_get(gtk_settings, "gtk-application-prefer-dark-theme", &prefer_dark, NULL);
  }

  g_object_set(gtk_settings, "gtk-application-prefer-dark-theme", prefer_dark, NULL);
}

void vibe_theme_init(void) {
  load_theme_config();
  apply_theme_mode();
}

VibeThemeMode vibe_theme_get_mode(void) { return current_mode; }

void vibe_theme_set_mode(VibeThemeMode mode) {
  current_mode = mode;
  apply_theme_mode();
  save_theme_config();
}

static void on_theme_changed(GtkComboBox *combo, gpointer data) {
  (void)data;
  int active = gtk_combo_box_get_active(combo);
  VibeThemeMode mode = VIBE_THEME_SYSTEM;
  if (active == 0)
    mode = VIBE_THEME_LIGHT;
  else if (active == 1)
    mode = VIBE_THEME_DARK;
  else
    mode = VIBE_THEME_SYSTEM;

  vibe_theme_set_mode(mode);
}

void vibe_theme_show_picker(GtkWindow *parent) {
  GtkWidget *dialog =
      gtk_dialog_new_with_buttons("Theme Settings", parent, GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
                                   "_Cancel", GTK_RESPONSE_CANCEL, "_Apply", GTK_RESPONSE_ACCEPT, NULL);

  GtkWidget *content = gtk_dialog_get_content_area(GTK_DIALOG(dialog));
  gtk_container_set_border_width(GTK_CONTAINER(content), 12);

  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_container_add(GTK_CONTAINER(content), box);

  GtkWidget *label = gtk_label_new("Choose appearance:");
  gtk_label_set_xalign(GTK_LABEL(label), 0.0);
  gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);

  GtkWidget *combo = gtk_combo_box_text_new();
  gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(combo), "Light");
  gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(combo), "Dark");
  gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(combo), "System");

  int active_idx = 2; // System
  if (current_mode == VIBE_THEME_LIGHT)
    active_idx = 0;
  else if (current_mode == VIBE_THEME_DARK)
    active_idx = 1;
  gtk_combo_box_set_active(GTK_COMBO_BOX(combo), active_idx);

  g_signal_connect(combo, "changed", G_CALLBACK(on_theme_changed), NULL);

  gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 0);

  GtkWidget *info = gtk_label_new("Changes apply immediately to all GhidraVibe windows.");
  gtk_label_set_line_wrap(GTK_LABEL(info), TRUE);
  gtk_label_set_xalign(GTK_LABEL(info), 0.0);
  gtk_box_pack_start(GTK_BOX(box), info, FALSE, FALSE, 8);

  gtk_widget_show_all(dialog);

  gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
}

void vibe_theme_apply_to_widget(GtkWidget *widget) {
  // Theme is applied globally via GtkSettings, but we can add
  // widget-specific CSS if needed in the future
  (void)widget;
}

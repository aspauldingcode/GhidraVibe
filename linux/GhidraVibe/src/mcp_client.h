#pragma once
#include <glib.h>

char *vibe_mcp_check(const char *base_url);
/** GET path on base_url; returns newly allocated response body (or error string). */
char *vibe_mcp_get(const char *base_url, const char *path);
/** GET with optional query string (already encoded, may be NULL). */
char *vibe_mcp_get_q(const char *base_url, const char *path, const char *query);
/** POST JSON body; returns response body. */
char *vibe_mcp_post(const char *base_url, const char *path, const char *json_body);

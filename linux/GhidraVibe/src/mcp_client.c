#include "mcp_client.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *run_curl(const char *cmd) {
  FILE *fp = popen(cmd, "r");
  if (!fp)
    return g_strdup("MCP request failed");
  GString *buf = g_string_new(NULL);
  char tmp[4096];
  size_t n;
  while ((n = fread(tmp, 1, sizeof(tmp), fp)) > 0)
    g_string_append_len(buf, tmp, (gssize)n);
  pclose(fp);
  if (buf->len == 0) {
    g_string_free(buf, TRUE);
    return g_strdup("(empty MCP response)");
  }
  return g_string_free(buf, FALSE);
}

char *vibe_mcp_check(const char *base_url) {
  if (!base_url || !*base_url)
    return g_strdup("Invalid MCP URL");
  char *a = vibe_mcp_get(base_url, "check_connection");
  if (a && strstr(a, "not reachable") == NULL && strstr(a, "failed") == NULL)
    return a;
  g_free(a);
  return vibe_mcp_get(base_url, "check");
}

char *vibe_mcp_get(const char *base_url, const char *path) {
  return vibe_mcp_get_q(base_url, path, NULL);
}

char *vibe_mcp_get_q(const char *base_url, const char *path, const char *query) {
  if (!base_url || !*base_url || !path)
    return g_strdup("Invalid MCP URL");
  char cmd[2048];
  if (query && *query)
    snprintf(cmd, sizeof(cmd),
             "curl -fsS --max-time 30 '%s/%s?%s' 2>/dev/null || echo 'MCP not reachable'", base_url,
             path, query);
  else
    snprintf(cmd, sizeof(cmd),
             "curl -fsS --max-time 30 '%s/%s' 2>/dev/null || echo 'MCP not reachable'", base_url,
             path);
  return run_curl(cmd);
}

char *vibe_mcp_post(const char *base_url, const char *path, const char *json_body) {
  if (!base_url || !*base_url || !path)
    return g_strdup("Invalid MCP URL");
  const char *body = json_body ? json_body : "{}";
  char cmd[4096];
  snprintf(cmd, sizeof(cmd),
           "curl -fsS --max-time 120 -X POST -H 'Content-Type: application/json' "
           "-d '%s' '%s/%s' 2>/dev/null || echo 'MCP not reachable'",
           body, base_url, path);
  return run_curl(cmd);
}

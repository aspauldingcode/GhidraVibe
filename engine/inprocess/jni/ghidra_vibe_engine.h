#ifndef GHIDRA_VIBE_ENGINE_H
#define GHIDRA_VIBE_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Embed HotSpot in the GhidraVibe process and start InProcessEngine.
 * Caller frees *out_json with ghidra_vibe_engine_free.
 *
 * java_home: JDK root (JAVA_HOME)
 * classpath: colon-separated jars (engine jar + full Ghidra + GhidraMCP)
 * ghidra_install_dir: …/lib/ghidra
 * start_args_json: {"port":8089,"project":"…","program":"/Name"} or NULL
 * jvm_xmx: e.g. "16G" or NULL (default 4G)
 */
int ghidra_vibe_engine_start(const char *java_home, const char *classpath,
                             const char *ghidra_install_dir,
                             const char *start_args_json, const char *jvm_xmx,
                             char **out_json);

int ghidra_vibe_engine_call(const char *method, const char *args_json,
                            char **out_json);

void ghidra_vibe_engine_free(char *p);

int ghidra_vibe_engine_running(void);

#ifdef __cplusplus
}
#endif

#endif /* GHIDRA_VIBE_ENGINE_H */

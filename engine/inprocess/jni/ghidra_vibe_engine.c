/*
 * Embed HotSpot in the GhidraVibe process and call InProcessEngine.
 * GUI = Swift/GTK in this process; engine = Ghidra Application in the same process.
 */
#include "ghidra_vibe_engine.h"

#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __APPLE__
#include <dlfcn.h>
#endif

static JavaVM *g_jvm = NULL;
static JNIEnv *g_env = NULL;
static jclass g_engine_cls = NULL;
static jmethodID g_start_mid = NULL;
static jmethodID g_call_mid = NULL;

typedef jint(JNICALL *JNI_CreateJavaVM_t)(JavaVM **, void **, void *);

static char *dup_cstr(JNIEnv *env, jstring js) {
  if (!js) {
    return strdup("");
  }
  const char *utf = (*env)->GetStringUTFChars(env, js, NULL);
  char *out = strdup(utf ? utf : "");
  (*env)->ReleaseStringUTFChars(env, js, utf);
  return out;
}

int ghidra_vibe_engine_start(const char *java_home, const char *classpath,
                             const char *ghidra_install_dir,
                             const char *start_args_json, const char *jvm_xmx,
                             char **out_json) {
  if (out_json) {
    *out_json = NULL;
  }
  if (g_jvm) {
    if (out_json) {
      *out_json = strdup("{\"ok\":true,\"message\":\"already started\"}");
    }
    return 0;
  }
  if (!java_home || !classpath) {
    if (out_json) {
      *out_json =
          strdup("{\"ok\":false,\"error\":\"java_home and classpath required\"}");
    }
    return 1;
  }

  char libjvm[1024];
#ifdef __APPLE__
  snprintf(libjvm, sizeof(libjvm), "%s/lib/libjli.dylib", java_home);
  void *handle = dlopen(libjvm, RTLD_NOW | RTLD_GLOBAL);
  if (!handle) {
    snprintf(libjvm, sizeof(libjvm), "%s/lib/server/libjvm.dylib", java_home);
    handle = dlopen(libjvm, RTLD_NOW | RTLD_GLOBAL);
  }
  if (!handle) {
    if (out_json) {
      char buf[512];
      snprintf(buf, sizeof(buf),
               "{\"ok\":false,\"error\":\"dlopen jvm failed: %s\"}", dlerror());
      *out_json = strdup(buf);
    }
    return 2;
  }
  JNI_CreateJavaVM_t create =
      (JNI_CreateJavaVM_t)dlsym(handle, "JNI_CreateJavaVM");
  if (!create) {
    snprintf(libjvm, sizeof(libjvm), "%s/lib/server/libjvm.dylib", java_home);
    void *jh = dlopen(libjvm, RTLD_NOW | RTLD_GLOBAL);
    create = jh ? (JNI_CreateJavaVM_t)dlsym(jh, "JNI_CreateJavaVM") : NULL;
  }
#else
  snprintf(libjvm, sizeof(libjvm), "%s/lib/server/libjvm.so", java_home);
  void *handle = dlopen(libjvm, RTLD_NOW | RTLD_GLOBAL);
  JNI_CreateJavaVM_t create =
      handle ? (JNI_CreateJavaVM_t)dlsym(handle, "JNI_CreateJavaVM") : NULL;
#endif
  if (!create) {
    if (out_json) {
      *out_json = strdup("{\"ok\":false,\"error\":\"JNI_CreateJavaVM not found\"}");
    }
    return 3;
  }

  size_t cp_len = strlen(classpath) + 32;
  char *opt_cp = (char *)malloc(cp_len);
  if (!opt_cp) {
    if (out_json) {
      *out_json = strdup("{\"ok\":false,\"error\":\"oom classpath\"}");
    }
    return 3;
  }
  snprintf(opt_cp, cp_len, "-Djava.class.path=%s", classpath);

  char opt_xmx[64];
  snprintf(opt_xmx, sizeof(opt_xmx), "-Xmx%s",
           (jvm_xmx && jvm_xmx[0]) ? jvm_xmx : "4G");

  JavaVMOption options[6];
  int nopt = 0;
  options[nopt++].optionString = opt_cp;
  options[nopt++].optionString = opt_xmx;
  options[nopt++].optionString = "-Djava.awt.headless=true";
  options[nopt++].optionString = "-Dghidra.vibe.nativeUi=1";
  options[nopt++].optionString = "-XX:ParallelGCThreads=2";
  options[nopt++].optionString = "-Xrs";

  JavaVMInitArgs args;
  args.version = JNI_VERSION_21;
  args.nOptions = nopt;
  args.options = options;
  args.ignoreUnrecognized = JNI_TRUE;

  jint rc = create(&g_jvm, (void **)&g_env, &args);
  free(opt_cp);
  if (rc != JNI_OK || !g_env) {
    if (out_json) {
      char buf[128];
      snprintf(buf, sizeof(buf),
               "{\"ok\":false,\"error\":\"JNI_CreateJavaVM rc=%d\"}", (int)rc);
      *out_json = strdup(buf);
    }
    g_jvm = NULL;
    return 4;
  }

  g_engine_cls =
      (*g_env)->FindClass(g_env, "dev/ghidravibe/engine/InProcessEngine");
  if (!g_engine_cls) {
    (*g_env)->ExceptionClear(g_env);
    if (out_json) {
      *out_json = strdup(
          "{\"ok\":false,\"error\":\"InProcessEngine class not found on "
          "classpath\"}");
    }
    return 5;
  }
  g_engine_cls = (*g_env)->NewGlobalRef(g_env, g_engine_cls);
  g_start_mid = (*g_env)->GetStaticMethodID(
      g_env, g_engine_cls, "start",
      "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
  if (!g_start_mid) {
    (*g_env)->ExceptionClear(g_env);
    /* Fall back to single-arg start(String) */
    g_start_mid = (*g_env)->GetStaticMethodID(
        g_env, g_engine_cls, "start", "(Ljava/lang/String;)Ljava/lang/String;");
  }
  g_call_mid = (*g_env)->GetStaticMethodID(
      g_env, g_engine_cls, "call",
      "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
  if (!g_start_mid || !g_call_mid) {
    if (out_json) {
      *out_json =
          strdup("{\"ok\":false,\"error\":\"InProcessEngine methods missing\"}");
    }
    return 6;
  }

  jstring jdir =
      (*g_env)->NewStringUTF(g_env, ghidra_install_dir ? ghidra_install_dir : "");
  jstring jargs =
      (*g_env)->NewStringUTF(g_env, start_args_json ? start_args_json : "{}");
  jstring jres;
  /* Prefer two-arg start(install, argsJson) */
  jmethodID two = (*g_env)->GetStaticMethodID(
      g_env, g_engine_cls, "start",
      "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
  if (two) {
    jres = (jstring)(*g_env)->CallStaticObjectMethod(g_env, g_engine_cls, two,
                                                     jdir, jargs);
  } else {
    (*g_env)->ExceptionClear(g_env);
    jres = (jstring)(*g_env)->CallStaticObjectMethod(g_env, g_engine_cls,
                                                     g_start_mid, jdir);
  }
  if ((*g_env)->ExceptionCheck(g_env)) {
    (*g_env)->ExceptionDescribe(g_env);
    (*g_env)->ExceptionClear(g_env);
    if (out_json) {
      *out_json =
          strdup("{\"ok\":false,\"error\":\"InProcessEngine.start threw\"}");
    }
    return 7;
  }
  if (out_json) {
    *out_json = dup_cstr(g_env, jres);
  }
  return 0;
}

int ghidra_vibe_engine_call(const char *method, const char *args_json,
                            char **out_json) {
  if (out_json) {
    *out_json = NULL;
  }
  if (!g_jvm || !g_env || !g_call_mid) {
    if (out_json) {
      *out_json = strdup("{\"ok\":false,\"error\":\"engine not started\"}");
    }
    return 1;
  }
  JNIEnv *env = g_env;
  jint got = (*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_21);
  if (got == JNI_EDETACHED) {
    (*g_jvm)->AttachCurrentThread(g_jvm, (void **)&env, NULL);
  }
  jstring jm = (*env)->NewStringUTF(env, method ? method : "");
  jstring ja = (*env)->NewStringUTF(env, args_json ? args_json : "{}");
  jstring jres =
      (jstring)(*env)->CallStaticObjectMethod(env, g_engine_cls, g_call_mid, jm,
                                              ja);
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
    if (out_json) {
      *out_json =
          strdup("{\"ok\":false,\"error\":\"InProcessEngine.call threw\"}");
    }
    return 2;
  }
  if (out_json) {
    *out_json = dup_cstr(env, jres);
  }
  return 0;
}

void ghidra_vibe_engine_free(char *p) { free(p); }

int ghidra_vibe_engine_running(void) { return g_jvm != NULL; }

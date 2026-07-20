# In-process Ghidra engine bridge for the native GUI.
# Builds InProcessEngine.jar + libghidravibe_engine.dylib|so.
# True headless CLI remains scripts/ghidra-vibe-mcp-headless (separate JVM).
{
  lib,
  stdenv,
  openjdk21,
  ghidraVibe,
}:

let
  java = openjdk21;
  ghidraHome = "${ghidraVibe}/lib/ghidra";
in
stdenv.mkDerivation {
  pname = "ghidra-vibe-engine";
  version = "0.1.0";

  src = ../../engine/inprocess;

  nativeBuildInputs = [ java ];
  buildInputs = [ java ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    mkdir -p build/classes

    MCP_JAR="$(echo ${ghidraHome}/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-*.jar | awk '{print $1}')"
    test -f "$MCP_JAR"

    # Compile against MCP + a thin slice of Framework jars (runtime uses full CP).
    COMPILE_CP="$MCP_JAR"
    for j in \
      "${ghidraHome}/Ghidra/Framework/Utility/lib/Utility.jar" \
      "${ghidraHome}/Ghidra/Framework/Generic/lib/Generic.jar" \
      "${ghidraHome}/Ghidra/Framework/Project/lib/Project.jar" \
      "${ghidraHome}/Ghidra/Framework/SoftwareModeling/lib/SoftwareModeling.jar" \
      "${ghidraHome}/Ghidra/Features/Base/lib/Base.jar"
    do
      COMPILE_CP+=":$j"
    done

    javac --release 21 -cp "$COMPILE_CP" -d build/classes \
      src/dev/ghidravibe/engine/InProcessEngine.java
    jar --create --file build/ghidra-vibe-inprocess.jar -C build/classes .

    JNI_INC="${java}/include"
    if [[ "$(uname)" == "Darwin" ]]; then
      clang -shared -fPIC -o build/libghidravibe_engine.dylib \
        jni/ghidra_vibe_engine.c \
        -I"$JNI_INC" -I"$JNI_INC/darwin" \
        -install_name @rpath/libghidravibe_engine.dylib
    else
      gcc -shared -fPIC -o build/libghidravibe_engine.so \
        jni/ghidra_vibe_engine.c \
        -I"$JNI_INC" -I"$JNI_INC/linux"
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/include" "$out/share/ghidra-vibe/engine"
    cp build/ghidra-vibe-inprocess.jar "$out/share/ghidra-vibe/engine/"
    # Rewrite classpath to installed jar path.
    {
      echo -n "$out/share/ghidra-vibe/engine/ghidra-vibe-inprocess.jar"
      find "${ghidraHome}" -name '*.jar' -print | while read -r j; do
        printf ':%s' "$j"
      done
      echo
    } > "$out/share/ghidra-vibe/engine/classpath.txt"
    cp jni/ghidra_vibe_engine.h "$out/include/"
    if [[ -f build/libghidravibe_engine.dylib ]]; then
      cp build/libghidravibe_engine.dylib "$out/lib/"
    else
      cp build/libghidravibe_engine.so "$out/lib/"
    fi
    runHook postInstall
  '';

  meta = with lib; {
    description = "In-process Ghidra engine JNI bridge for GhidraVibe GUI";
    platforms = platforms.unix;
  };
}

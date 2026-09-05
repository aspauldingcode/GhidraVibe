#!/usr/bin/env bash
# Pick a JVM that can actually start Ghidra 12.
# Darwin HotSpot 17/21/25 SIGBUS (BUS_ADRALN) in CodeHeap::allocate — including
# `java -version`. IBM Semeru / OpenJ9 21 is the known-good Darwin analysis JDK.
# Never inherit a broken JAVA_HOME (Zulu/Temurin/openjdk HotSpot) on Darwin.

_ghidra_java_looks_openj9() {
  local home="$1"
  [[ -n "$home" ]] || return 1
  case "$home" in
    *[Ss]emeru* | *[Oo]penj9* | *[Ee]clipse-temurin-j9*) return 0 ;;
  esac
  [[ -e "${home}/lib/libj9vm.dylib" || -e "${home}/lib/j9vm/libj9vm.dylib" \
    || -e "${home}/lib/server/libj9vm.dylib" || -d "${home}/lib/j9vm" ]]
}

_ghidra_java_looks_hotspot() {
  local home="$1"
  [[ -n "$home" ]] || return 1
  _ghidra_java_looks_openj9 "$home" && return 1
  case "$home" in
    *zulu* | *Zulu* | *temurin* | *Temurin* | *graalvm* | *GraalVM* | *-openjdk* | *openjdk*)
      return 0
      ;;
  esac
  return 1
}

_ghidra_java_works() {
  local home="$1"
  [[ -n "$home" && -x "${home}/bin/java" ]] || return 1
  # Darwin HotSpot SIGBUS on -version — do not exec it.
  if [[ "$(uname -s)" == "Darwin" ]] && _ghidra_java_looks_hotspot "$home"; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 "${home}/bin/java" -version >/dev/null 2>&1
  else
    "${home}/bin/java" -version >/dev/null 2>&1
  fi
}

_ghidra_java_candidates() {
  local d
  if [[ -n "${GHIDRA_VIBE_JAVA_HOME:-}" ]]; then
    printf '%s\n' "${GHIDRA_VIBE_JAVA_HOME}"
  fi
  # Prefer OpenJ9 / Semeru on Darwin before any leftover HotSpot.
  for d in /nix/store/*-semeru-bin-21*/Library/Java/JavaVirtualMachines/*/Contents/Home; do
    [[ -x "${d}/bin/java" ]] && printf '%s\n' "$d"
  done
  for d in \
    /Library/Java/JavaVirtualMachines/semeru-*/Contents/Home \
    /Library/Java/JavaVirtualMachines/*semeru*/Contents/Home \
    /Library/Java/JavaVirtualMachines/*openj9*/Contents/Home
  do
    [[ -x "${d}/bin/java" ]] && printf '%s\n' "$d"
  done
  # Linux / last-resort JDKs (Darwin HotSpot entries are skipped by _ghidra_java_works).
  for d in \
    /nix/store/*-openjdk21*/lib/openjdk \
    /nix/store/*-zulu21*/lib/openjdk \
    /nix/store/*-temurin-bin-21* \
    /Library/Java/JavaVirtualMachines/*/Contents/Home
  do
    [[ -x "${d}/bin/java" ]] && printf '%s\n' "$d"
  done
}

detect_ghidra_java_home() {
  # Darwin: never trust an inherited HotSpot JAVA_HOME (SIGBUS, even -version).
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ -n "${GHIDRA_VIBE_JAVA_HOME:-}" ]] && _ghidra_java_works "${GHIDRA_VIBE_JAVA_HOME}"; then
      printf '%s\n' "${GHIDRA_VIBE_JAVA_HOME}"
      return 0
    fi
    if [[ -n "${JAVA_HOME:-}" ]] && _ghidra_java_looks_openj9 "${JAVA_HOME}" \
      && _ghidra_java_works "${JAVA_HOME}"; then
      printf '%s\n' "${JAVA_HOME}"
      return 0
    fi
  elif [[ -n "${JAVA_HOME:-}" ]] && _ghidra_java_works "${JAVA_HOME}"; then
    printf '%s\n' "${JAVA_HOME}"
    return 0
  fi
  local cand
  while IFS= read -r cand; do
    [[ -z "$cand" ]] && continue
    if _ghidra_java_works "$cand"; then
      printf '%s\n' "$cand"
      return 0
    fi
  done < <(_ghidra_java_candidates)
  local bin home
  bin="$(command -v java 2>/dev/null || true)"
  if [[ -n "$bin" ]]; then
    home="$(cd "$(dirname "$bin")/.." && pwd)"
    if _ghidra_java_works "$home"; then
      printf '%s\n' "$home"
      return 0
    fi
  fi
  echo "No working JDK 21 found (Darwin HotSpot SIGBUS — use IBM Semeru 21)" >&2
  return 1
}

ensure_ghidra_java_home() {
  local home
  home="$(detect_ghidra_java_home)" || return 1
  export JAVA_HOME="$home"
  export PATH="${JAVA_HOME}/bin:${PATH}"
  printf '%s\n' "${JAVA_HOME}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detect_ghidra_java_home
fi

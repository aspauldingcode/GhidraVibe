#!/usr/bin/env bash
# Thin a fat Mach-O to the host arch before Ghidra import.
# Universal binaries default to the x86_64 slice in Ghidra 12 unless thinned.

macho_is_fat() {
  local f="$1" magic
  [[ -f "$f" ]] || return 1
  magic="$(xxd -p -l 4 "$f" 2>/dev/null || true)"
  case "$magic" in
    cafebabe|bebafeca|cafed00d|0dd0feca) return 0 ;;
    *) return 1 ;;
  esac
}

macho_preferred_arches() {
  case "$(uname -m)" in
    arm64|aarch64)
      printf '%s\n' arm64e arm64 x86_64
      ;;
    *)
      printf '%s\n' x86_64 arm64e arm64
      ;;
  esac
}

macho_native_slice() {
  local src="$1"
  local dest="${2:-}"
  if [[ ! -f "$src" ]]; then
    echo "$src"
    return 0
  fi
  if ! macho_is_fat "$src"; then
    echo "$src"
    return 0
  fi
  if ! command -v lipo >/dev/null 2>&1; then
    echo "macho-native-slice: fat binary but lipo missing; Ghidra may pick x86_64: $src" >&2
    echo "$src"
    return 0
  fi
  local avail a
  avail="$(lipo -archs "$src" 2>/dev/null || true)"
  while IFS= read -r a; do
    [[ -z "$a" ]] && continue
    if [[ " ${avail} " == *" ${a} "* ]]; then
      if [[ -z "$dest" ]]; then
        dest="${GHIDRA_VIBE_SLICE_DIR:-${TMPDIR:-/tmp}/ghidra-vibe-slices}/$(basename "$src")"
      fi
      mkdir -p "$(dirname "$dest")"
      if ! lipo -thin "$a" "$src" -output "$dest" 2>/dev/null; then
        continue
      fi
      echo "macho-native-slice: ${src} → ${dest} (${a})" >&2
      echo "$dest"
      return 0
    fi
  done < <(macho_preferred_arches)
  echo "macho-native-slice: no preferred arch in [${avail}]: $src" >&2
  echo "$src"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "usage: macho-native-slice.sh <mach-o> [dest]" >&2
    exit 2
  fi
  macho_native_slice "$@"
fi

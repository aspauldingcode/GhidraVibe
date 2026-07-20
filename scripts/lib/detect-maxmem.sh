#!/usr/bin/env bash
# Pick Ghidra -Xmx from physical RAM (leave headroom for OS + native UI + MCP).
# Override anytime with GHIDRA_VIBE_MAXMEM / MAXMEM.
detect_ghidra_maxmem() {
  if [[ -n "${GHIDRA_VIBE_MAXMEM:-}" ]]; then
    echo "${GHIDRA_VIBE_MAXMEM}"
    return
  fi
  if [[ -n "${MAXMEM:-}" ]]; then
    echo "${MAXMEM}"
    return
  fi

  local bytes=0
  case "$(uname -s)" in
    Darwin)
      bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
      ;;
    Linux)
      if [[ -r /proc/meminfo ]]; then
        bytes="$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024))"
      fi
      ;;
  esac

  if [[ "$bytes" -le 0 ]]; then
    echo "4G"
    return
  fi

  # ~45% of RAM, clamped [2G, 48G]. Keep headroom for OS + native UI + MCP.
  # Multiply before divide to avoid truncating small hosts to 0.
  local g=$((bytes * 45 / 100 / 1024 / 1024 / 1024))
  if [[ "$g" -lt 2 ]]; then g=2; fi
  if [[ "$g" -gt 48 ]]; then g=48; fi
  echo "${g}G"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detect_ghidra_maxmem
fi

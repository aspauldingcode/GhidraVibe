#!/usr/bin/env bash
# GUI Parity Test Suite - Compare macOS SwiftUI vs Linux GTK implementations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test results
PASS=0
FAIL=0
SKIP=0

log_test() {
  echo "TEST: $1"
}

log_pass() {
  echo "  ✓ PASS: $1"
  PASS=$((PASS + 1))
}

log_fail() {
  echo "  ✗ FAIL: $1"
  FAIL=$((FAIL + 1))
}

log_skip() {
  echo "  ⊘ SKIP: $1"
  SKIP=$((SKIP + 1))
}

# Check if a file exists
check_file() {
  local desc="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    log_pass "$desc exists: $path"
    return 0
  else
    log_fail "$desc missing: $path"
    return 1
  fi
}

# Check if source file contains pattern
check_source_contains() {
  local desc="$1"
  local file="$2"
  local pattern="$3"
  if [[ ! -f "$file" ]]; then
    log_fail "$desc - file not found: $file"
    return 1
  fi
  if grep -q "$pattern" "$file"; then
    log_pass "$desc - found pattern in $file"
    return 0
  else
    log_fail "$desc - pattern not found in $file: $pattern"
    return 1
  fi
}

# Test 1: Check source file structure
log_test "Source file structure"
check_file "macOS SwiftUI main app" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/GhidraVibeApp.swift"
check_file "Linux GTK main" "$ROOT/linux/GhidraVibe/src/main.c"
check_file "Linux GTK dock" "$ROOT/linux/GhidraVibe/src/dock.c"

# Test 2: Check splash screen implementation
log_test "Splash screen implementation"
check_source_contains "macOS has SplashView" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/SplashView.swift" "SplashView"
check_source_contains "Linux has splash" "$ROOT/linux/GhidraVibe/src/splash.c" "vibe_splash_create"

# Test 3: Check user agreement
log_test "User agreement implementation"
check_source_contains "macOS has UserAgreement" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/UserAgreement.swift" "UserAgreement"
check_source_contains "Linux has agreement" "$ROOT/linux/GhidraVibe/src/splash.c" "vibe_show_agreement_if_needed"

# Test 4: Check theme support
log_test "Theme/appearance support"
check_source_contains "macOS has ThemeStore" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/ThemeStore.swift" "ThemeStore"
check_source_contains "Linux has theme" "$ROOT/linux/GhidraVibe/src/theme.c" "vibe_theme_"

# Test 5: Check DSC/dyld support
log_test "DSC/dyld shared cache support"
check_source_contains "macOS DSC in AppModel" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/AppModel.swift" "dyldCachePaths"
check_source_contains "Linux DSC setup" "$ROOT/linux/GhidraVibe/src/dsc_setup.c" "vibe_dsc_"
check_file "dyld script with platform support" "$ROOT/scripts/ghidra-vibe-dyld"
check_source_contains "dyld script has Linux support" "$ROOT/scripts/ghidra-vibe-dyld" "IS_LINUX"

# Test 6: Check help system
log_test "Help system implementation"
check_source_contains "macOS has HelpWebView" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/HelpWebView.swift" "HelpWebView"
check_source_contains "Linux has help_view" "$ROOT/linux/GhidraVibe/src/help_view.c" "vibe_help_"

# Test 7: Check MCP client
log_test "MCP client implementation"
check_source_contains "macOS has MCPClient" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/MCPClient.swift" "MCPClient"
check_source_contains "Linux has mcp_client" "$ROOT/linux/GhidraVibe/src/mcp_client.c" "vibe_mcp_"

# Test 8: Check agent chat (expected missing on Linux)
log_test "Agent chat implementation (optional)"
if check_source_contains "macOS has AgentChatView" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/AgentChatView.swift" "AgentChatView"; then
  if check_source_contains "Linux has agent UI" "$ROOT/linux/GhidraVibe/src/dock.c" "agent"; then
    log_pass "Linux has basic agent UI"
  else
    log_skip "Linux agent UI limited (expected for now)"
  fi
fi

# Test 9: Check function graph
log_test "Function graph canvas"
check_source_contains "macOS has FunctionGraphCanvas" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/FunctionGraphCanvas.swift" "FunctionGraphCanvas"
check_source_contains "Linux has graph_view" "$ROOT/linux/GhidraVibe/src/graph_view.c" "draw_graph"

# Test 10: Check accessibility support
log_test "Accessibility implementation"
check_source_contains "macOS has A11yCatalog" "$ROOT/macos/GhidraVibe/Sources/GhidraVibe/A11yCatalog.swift" "A11yCatalog"
check_source_contains "Linux has a11y" "$ROOT/linux/GhidraVibe/src/a11y.c" "vibe_a11y_"
check_file "Shared a11y catalog" "$ROOT/native-ui/a11y/catalog.json"

# Test 11: Check build system
log_test "Build system configuration"
check_file "macOS Package.swift" "$ROOT/macos/GhidraVibe/Package.swift"
check_file "Linux meson.build" "$ROOT/linux/GhidraVibe/meson.build"
check_file "Nix flake" "$ROOT/flake.nix"

# Test 12: Check documentation
log_test "Documentation"
check_file "README" "$ROOT/README.md"
check_file "DYLD docs" "$ROOT/docs/DYLD.md"
check_source_contains "DYLD docs mention Linux" "$ROOT/docs/DYLD.md" "Linux"

# Test 13: Verify new Linux features (from this PR)
log_test "New Linux features (this PR)"
check_source_contains "dyld script has setup-ipsw" "$ROOT/scripts/ghidra-vibe-dyld" "setup-ipsw"
check_source_contains "Rust DSC index has Linux" "$ROOT/rust/ghidra-vibe-tools/src/bin/dsc_index.rs" "target_os = \"linux\""
check_source_contains "Python DSC index has Linux" "$ROOT/scripts/lib/dsc_index.py" "platform.system"
check_file "Linux splash implementation" "$ROOT/linux/GhidraVibe/src/splash.c"
check_file "Linux theme implementation" "$ROOT/linux/GhidraVibe/src/theme.c"
check_file "Linux DSC setup implementation" "$ROOT/linux/GhidraVibe/src/dsc_setup.c"

# Summary
echo ""
echo "===================="
echo "GUI PARITY TEST RESULTS"
echo "===================="
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo "SKIPPED: $SKIP"
echo "===================="

if [[ $FAIL -gt 0 ]]; then
  echo "❌ Some tests failed"
  exit 1
else
  echo "✅ All tests passed"
  exit 0
fi

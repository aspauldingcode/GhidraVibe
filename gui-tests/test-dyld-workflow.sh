#!/usr/bin/env bash
# Comprehensive dyld shared cache workflow test
# Tests: cache discovery, framework listing, import, and decompilation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================="
echo "Dyld Shared Cache Workflow Test"
echo "========================================="
echo ""

# Detect platform
PLATFORM="$(uname -s)"
echo "Platform: $PLATFORM"

# Test 1: Find dyld cache
echo ""
echo "TEST 1: Find dyld shared cache"
echo "------------------------------"
CACHE_PATH=""
if CACHE_PATH="$("$ROOT/scripts/ghidra-vibe-dyld" find-cache 2>&1)"; then
  echo "✓ PASS: Cache found at: $CACHE_PATH"
  if [[ ! -f "$CACHE_PATH" ]]; then
    echo "✗ FAIL: Cache path exists in output but file not accessible"
    exit 1
  fi
else
  echo "✗ FAIL: Could not find dyld shared cache"
  if [[ "$PLATFORM" == "Linux" ]]; then
    echo ""
    echo "On Linux, you need to setup IPSW cache first:"
    echo "  ./scripts/ghidra-vibe-dyld setup-ipsw"
    echo "Or set GHIDRA_VIBE_IPSW_CACHE to your extracted cache path"
  fi
  exit 1
fi

# Test 2: List all frameworks
echo ""
echo "TEST 2: List all frameworks in cache"
echo "-------------------------------------"
FRAMEWORKS_COUNT=0
if FRAMEWORKS=$("$ROOT/scripts/ghidra-vibe-dyld" list --cache "$CACHE_PATH" 2>&1); then
  FRAMEWORKS_COUNT=$(echo "$FRAMEWORKS" | wc -l | tr -d ' ')
  echo "✓ PASS: Found $FRAMEWORKS_COUNT frameworks/libraries"
  if [[ $FRAMEWORKS_COUNT -lt 100 ]]; then
    echo "⚠ WARNING: Expected >100 frameworks, got $FRAMEWORKS_COUNT"
  fi
else
  echo "✗ FAIL: Could not list frameworks"
  exit 1
fi

# Test 3: Query specific frameworks
echo ""
echo "TEST 3: Query specific frameworks"
echo "----------------------------------"
TEST_QUERIES=("AppKit" "Foundation" "UIKit" "CoreFoundation")
for QUERY in "${TEST_QUERIES[@]}"; do
  if RESULT=$("$ROOT/scripts/ghidra-vibe-dyld" list --cache "$CACHE_PATH" --query "$QUERY" 2>&1); then
    COUNT=$(echo "$RESULT" | wc -l | tr -d ' ')
    if [[ $COUNT -gt 0 ]]; then
      echo "✓ PASS: Found $COUNT result(s) for '$QUERY'"
      echo "  First match: $(echo "$RESULT" | head -1)"
    else
      echo "⊘ SKIP: No results for '$QUERY' (may not exist in this cache)"
    fi
  else
    echo "✗ FAIL: Query failed for '$QUERY'"
    exit 1
  fi
done

# Test 4: Resolve framework paths
echo ""
echo "TEST 4: Resolve framework install paths"
echo "----------------------------------------"
TEST_FRAMEWORKS=("AppKit" "SkyLight")
RESOLVED_PATHS=()
for FW in "${TEST_FRAMEWORKS[@]}"; do
  if RESOLVED=$("$ROOT/scripts/ghidra-vibe-dyld" resolve --cache "$CACHE_PATH" --image "$FW" 2>&1); then
    echo "✓ PASS: Resolved '$FW' to: $RESOLVED"
    RESOLVED_PATHS+=("$RESOLVED")
  else
    echo "⊘ SKIP: Could not resolve '$FW' (may not exist in this cache)"
  fi
done

if [[ ${#RESOLVED_PATHS[@]} -eq 0 ]]; then
  echo "✗ FAIL: Could not resolve any test frameworks"
  exit 1
fi

# Test 5: Test AppKit framework import (if available)
echo ""
echo "TEST 5: Import and analyze framework (AppKit)"
echo "----------------------------------------------"
APPKIT_PATH=""
if APPKIT_PATH=$("$ROOT/scripts/ghidra-vibe-dyld" resolve --cache "$CACHE_PATH" --image "AppKit" 2>&1); then
  echo "AppKit path: $APPKIT_PATH"
  
  # Create test project
  TEST_PROJECT_DIR="${TMPDIR:-/tmp}/ghidra-vibe-test-dsc-$$"
  mkdir -p "$TEST_PROJECT_DIR"
  echo "Test project: $TEST_PROJECT_DIR"
  
  # Import AppKit (no auto-analyze for speed)
  echo "Importing AppKit (this may take a few minutes)..."
  if IMPORT_RESULT=$("$ROOT/scripts/ghidra-vibe-dyld" import \
    --cache "$CACHE_PATH" \
    --image "AppKit" \
    --project "$TEST_PROJECT_DIR" \
    --project-name "DSCTest" \
    --program "AppKit" \
    --no-analyze 2>&1); then
    
    echo "✓ PASS: AppKit imported successfully"
    echo "$IMPORT_RESULT" | grep "OK:"
    
    # Extract project path from output
    PROJECT_GPR=$(echo "$IMPORT_RESULT" | grep -o "project_gpr=[^ ]*" | cut -d= -f2)
    if [[ -f "$PROJECT_GPR" ]]; then
      echo "✓ PASS: Project file created: $PROJECT_GPR"
    else
      echo "⚠ WARNING: Project file not found at expected location"
    fi
    
    # Check for program file
    PROGRAM_NAME=$(echo "$IMPORT_RESULT" | grep -o "program=[^ ]*" | cut -d= -f2)
    echo "Program name: $PROGRAM_NAME"
    
  else
    echo "✗ FAIL: AppKit import failed"
    echo "$IMPORT_RESULT"
    rm -rf "$TEST_PROJECT_DIR"
    exit 1
  fi
  
  # Cleanup
  echo "Cleaning up test project..."
  rm -rf "$TEST_PROJECT_DIR"
  
else
  echo "⊘ SKIP: AppKit not available in this cache"
fi

# Test 6: Verify NSWindow decompilation capability (requires analysis engine)
echo ""
echo "TEST 6: Verify decompilation capability setup"
echo "----------------------------------------------"
echo "Note: Full decompilation testing requires running analysis engine"
echo "To test NSWindow decompilation manually:"
echo "  1. Import AppKit: ghidra-vibe-dyld import --image AppKit"
echo "  2. Open in GhidraVibe GUI"
echo "  3. Search for NSWindow functions"
echo "  4. Select function and view decompilation"
echo ""
echo "Required components check:"

# Check for analysis engine
if command -v ghidra-analyzeHeadless >/dev/null 2>&1 || \
   [[ -n "${GHIDRA_VIBE_HEADLESS:-}" ]]; then
  echo "✓ PASS: Ghidra headless analyzer available"
else
  echo "⚠ WARNING: Ghidra headless analyzer not in PATH"
fi

# Check for ImportDyldCacheImage.java
if [[ -f "$ROOT/ghidra_scripts/ImportDyldCacheImage.java" ]]; then
  echo "✓ PASS: ImportDyldCacheImage.java script found"
else
  echo "✗ FAIL: ImportDyldCacheImage.java script not found"
  exit 1
fi

# Test 7: Platform-specific validation
echo ""
echo "TEST 7: Platform-specific validation"
echo "-------------------------------------"
if [[ "$PLATFORM" == "Darwin" ]]; then
  echo "macOS platform:"
  echo "✓ Checking on-device cache locations..."
  ON_DEVICE_CANDIDATES=(
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"
    "/System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"
    "/System/Library/dyld/dyld_shared_cache_arm64e"
  )
  FOUND_ON_DEVICE=false
  for CANDIDATE in "${ON_DEVICE_CANDIDATES[@]}"; do
    if [[ -f "$CANDIDATE" ]]; then
      echo "  ✓ Found: $CANDIDATE"
      FOUND_ON_DEVICE=true
      break
    fi
  done
  if [[ "$FOUND_ON_DEVICE" == "false" ]]; then
    echo "  ✗ No on-device cache found at standard locations"
    exit 1
  fi
  
elif [[ "$PLATFORM" == "Linux" ]]; then
  echo "Linux platform:"
  echo "✓ Checking IPSW cache setup..."
  if [[ -n "${GHIDRA_VIBE_IPSW_CACHE:-}" ]]; then
    echo "  ✓ GHIDRA_VIBE_IPSW_CACHE is set: $GHIDRA_VIBE_IPSW_CACHE"
  else
    echo "  ℹ GHIDRA_VIBE_IPSW_CACHE not set (using default locations)"
  fi
  
  # Check default locations
  LINUX_CANDIDATES=(
    "$HOME/.local/share/ghidra-vibe/ipsw-cache/dyld_shared_cache_arm64e"
    "$HOME/Documents/GhidraVibe/ipsw-cache/dyld_shared_cache_arm64e"
  )
  FOUND_IPSW=false
  for CANDIDATE in "${LINUX_CANDIDATES[@]}"; do
    if [[ -f "$CANDIDATE" ]]; then
      echo "  ✓ Found: $CANDIDATE"
      FOUND_IPSW=true
      break
    fi
  done
  if [[ "$FOUND_IPSW" == "false" && -z "${GHIDRA_VIBE_IPSW_CACHE:-}" ]]; then
    echo "  ⚠ WARNING: No IPSW cache found at default locations"
    echo "  Run: ghidra-vibe-dyld setup-ipsw"
  fi
fi

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "✓ Cache discovery working"
echo "✓ Framework listing working ($FRAMEWORKS_COUNT frameworks)"
echo "✓ Framework resolution working"
echo "✓ Import infrastructure validated"
echo ""
echo "✅ All dyld shared cache workflow tests PASSED"
echo ""
echo "Next steps for full decompilation testing:"
echo "1. Start GhidraVibe GUI: nix run .#ghidraVibe"
echo "2. File → Open Framework from Shared Cache"
echo "3. Search and select 'AppKit'"
echo "4. Wait for import to complete"
echo "5. Search for 'NSWindow' in Functions"
echo "6. Select any NSWindow method"
echo "7. View decompilation in right panel"

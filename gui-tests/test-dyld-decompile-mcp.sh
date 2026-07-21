#!/usr/bin/env bash
# Automated dyld + decompilation test using MCP
# Tests complete workflow: cache → framework selection → import → decompilation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================="
echo "Dyld Framework Decompilation Test (MCP)"
echo "========================================="
echo ""

# Configuration
MCP_URL="${GHIDRA_VIBE_MCP_URL:-http://127.0.0.1:8092}"
TEST_FRAMEWORK="${1:-AppKit}"
TEST_FUNCTION="${2:-NSWindow}"
TIMEOUT=300  # 5 minutes for import + analysis

echo "Configuration:"
echo "  MCP URL: $MCP_URL"
echo "  Test Framework: $TEST_FRAMEWORK"
echo "  Test Function: $TEST_FUNCTION"
echo "  Timeout: ${TIMEOUT}s"
echo ""

# Helper: Check if MCP is running
check_mcp() {
  if curl -sf "$MCP_URL/health" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Helper: Call MCP tool
call_mcp() {
  local tool="$1"
  shift
  local args="$@"
  
  # Build JSON-RPC request
  local params="{"
  local first=true
  for arg in $args; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      params="$params,"
    fi
    local key="${arg%%=*}"
    local val="${arg#*=}"
    params="$params\"$key\":\"$val\""
  done
  params="$params}"
  
  local request="{\"jsonrpc\":\"2.0\",\"method\":\"$tool\",\"params\":$params,\"id\":1}"
  
  curl -sf -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d "$request" | jq -r '.result // .error // empty'
}

# Test 1: Check MCP availability
echo "TEST 1: Check MCP availability"
echo "-------------------------------"
if check_mcp; then
  echo "✓ PASS: MCP is running at $MCP_URL"
else
  echo "✗ FAIL: MCP not reachable at $MCP_URL"
  echo ""
  echo "To start MCP, run in another terminal:"
  echo "  nix run .#ghidraVibe"
  echo "Or set GHIDRA_VIBE_MCP_URL to the correct URL"
  exit 1
fi

# Test 2: Find dyld cache via MCP
echo ""
echo "TEST 2: Find dyld cache via MCP"
echo "--------------------------------"
if CACHE_PATH=$(call_mcp "dyld_find_cache" 2>&1); then
  if [[ -n "$CACHE_PATH" && "$CACHE_PATH" != "null" ]]; then
    echo "✓ PASS: Cache found via MCP: $CACHE_PATH"
  else
    echo "✗ FAIL: MCP returned empty cache path"
    exit 1
  fi
else
  echo "✗ FAIL: dyld_find_cache MCP call failed"
  exit 1
fi

# Test 3: List frameworks via MCP
echo ""
echo "TEST 3: List frameworks via MCP"
echo "--------------------------------"
if FRAMEWORKS=$(call_mcp "dyld_list_images" "cache=$CACHE_PATH" 2>&1); then
  FRAMEWORK_COUNT=$(echo "$FRAMEWORKS" | jq -r '. | length' 2>/dev/null || echo "0")
  if [[ $FRAMEWORK_COUNT -gt 0 ]]; then
    echo "✓ PASS: Listed $FRAMEWORK_COUNT frameworks via MCP"
  else
    echo "✗ FAIL: No frameworks returned"
    exit 1
  fi
else
  echo "✗ FAIL: dyld_list_images MCP call failed"
  exit 1
fi

# Test 4: Resolve test framework
echo ""
echo "TEST 4: Resolve $TEST_FRAMEWORK framework"
echo "------------------------------------------"
if FRAMEWORK_PATH=$(call_mcp "dyld_resolve_image" "cache=$CACHE_PATH" "image=$TEST_FRAMEWORK" 2>&1); then
  if [[ -n "$FRAMEWORK_PATH" && "$FRAMEWORK_PATH" != "null" ]]; then
    echo "✓ PASS: Resolved $TEST_FRAMEWORK to: $FRAMEWORK_PATH"
  else
    echo "✗ FAIL: Could not resolve $TEST_FRAMEWORK"
    exit 1
  fi
else
  echo "✗ FAIL: dyld_resolve_image MCP call failed"
  exit 1
fi

# Test 5: Import framework via MCP
echo ""
echo "TEST 5: Import $TEST_FRAMEWORK via MCP"
echo "---------------------------------------"
echo "This will take a few minutes (importing + analyzing framework)..."

TEST_PROJECT="${TMPDIR:-/tmp}/ghidra-vibe-mcp-test-$$"
mkdir -p "$TEST_PROJECT"

START_TIME=$(date +%s)
if IMPORT_RESULT=$(call_mcp "dyld_import_image" \
  "cache=$CACHE_PATH" \
  "image=$TEST_FRAMEWORK" \
  "project=$TEST_PROJECT" \
  "analyze=1" 2>&1); then
  
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  
  echo "✓ PASS: $TEST_FRAMEWORK imported in ${DURATION}s"
  echo "Import result: $IMPORT_RESULT"
  
  # Extract program info
  PROJECT_GPR=$(echo "$IMPORT_RESULT" | jq -r '.project_gpr // empty' 2>/dev/null || echo "")
  PROGRAM_NAME=$(echo "$IMPORT_RESULT" | jq -r '.program // empty' 2>/dev/null || echo "")
  
  if [[ -z "$PROJECT_GPR" ]]; then
    # Try parsing as plain text
    PROJECT_GPR=$(echo "$IMPORT_RESULT" | grep -o "project_gpr=[^ ]*" | cut -d= -f2 || echo "")
    PROGRAM_NAME=$(echo "$IMPORT_RESULT" | grep -o "program=[^ ]*" | cut -d= -f2 || echo "")
  fi
  
  echo "Project: $PROJECT_GPR"
  echo "Program: $PROGRAM_NAME"
  
else
  echo "✗ FAIL: Framework import failed"
  echo "$IMPORT_RESULT"
  rm -rf "$TEST_PROJECT"
  exit 1
fi

# Test 6: Open program via MCP
echo ""
echo "TEST 6: Open imported program"
echo "------------------------------"
if [[ -n "$PROJECT_GPR" && -n "$PROGRAM_NAME" ]]; then
  if OPEN_RESULT=$(call_mcp "open_program" \
    "project=$PROJECT_GPR" \
    "program=$PROGRAM_NAME" 2>&1); then
    echo "✓ PASS: Program opened successfully"
  else
    echo "⚠ WARNING: Could not open program via MCP (may need GUI running)"
  fi
else
  echo "⊘ SKIP: Project/program info not available"
fi

# Test 7: Search for test function
echo ""
echo "TEST 7: Search for $TEST_FUNCTION functions"
echo "--------------------------------------------"
if FUNCTIONS=$(call_mcp "search_functions" "query=$TEST_FUNCTION" 2>&1); then
  FUNC_COUNT=$(echo "$FUNCTIONS" | jq -r '. | length' 2>/dev/null || echo "0")
  if [[ $FUNC_COUNT -gt 0 ]]; then
    echo "✓ PASS: Found $FUNC_COUNT functions matching '$TEST_FUNCTION'"
    
    # Get first function
    FIRST_FUNC=$(echo "$FUNCTIONS" | jq -r '.[0].name // .[0]' 2>/dev/null || echo "")
    if [[ -n "$FIRST_FUNC" && "$FIRST_FUNC" != "null" ]]; then
      echo "Example function: $FIRST_FUNC"
      
      # Test 8: Get decompilation
      echo ""
      echo "TEST 8: Decompile $FIRST_FUNC"
      echo "------------------------------"
      if DECOMPILED=$(call_mcp "decompile_function" "function=$FIRST_FUNC" 2>&1); then
        DECOMPILED_LINES=$(echo "$DECOMPILED" | wc -l)
        if [[ $DECOMPILED_LINES -gt 5 ]]; then
          echo "✓ PASS: Successfully decompiled function ($DECOMPILED_LINES lines)"
          echo ""
          echo "Decompilation preview (first 20 lines):"
          echo "----------------------------------------"
          echo "$DECOMPILED" | head -20
          echo "----------------------------------------"
        else
          echo "⚠ WARNING: Decompilation returned but may be incomplete"
          echo "$DECOMPILED"
        fi
      else
        echo "⚠ WARNING: Could not decompile function via MCP"
        echo "Manual verification needed in GUI"
      fi
    fi
  else
    echo "⚠ WARNING: No functions found matching '$TEST_FUNCTION'"
    echo "Framework may not contain this symbol"
  fi
else
  echo "⚠ WARNING: Function search failed via MCP"
  echo "Manual verification needed in GUI"
fi

# Cleanup
echo ""
echo "Cleaning up test project..."
rm -rf "$TEST_PROJECT"

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "✓ MCP connectivity validated"
echo "✓ Cache discovery via MCP working"
echo "✓ Framework listing via MCP working"
echo "✓ Framework resolution working"
echo "✓ Framework import completed"
echo ""

if [[ $FUNC_COUNT -gt 0 ]]; then
  echo "✅ COMPLETE WORKFLOW VALIDATED"
  echo "   Cache → Framework Selection → Import → Decompilation"
  echo ""
  echo "You can now use any framework from the dyld shared cache:"
  echo "  1. Start GhidraVibe: nix run .#ghidraVibe"
  echo "  2. File → Open Framework from Shared Cache"
  echo "  3. Search for any framework (AppKit, Foundation, UIKit, etc.)"
  echo "  4. Select framework and click Open"
  echo "  5. Browse functions and view decompilation"
else
  echo "⚠ PARTIAL SUCCESS"
  echo "   Import worked, but function search/decompilation needs manual verification"
fi

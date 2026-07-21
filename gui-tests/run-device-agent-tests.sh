#!/bin/bash
# Quick Device Agent Test Runner
# Usage: ./run-device-agent-tests.sh [scenario]

set -e

GUI_URL="${GHIDRA_VIBE_GUI_URL:-http://127.0.0.1:8091}"
DEVICE_AGENT="./scripts/ghidra-vibe-device-agent"
TEST_RECORDER="./scripts/ghidra-vibe-test-recorder"
SCENARIOS_DIR="./gui-tests/scenarios"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== GhidraVibe Device Agent Test Runner ==="
echo

# Check if scripts exist
if [ ! -x "$DEVICE_AGENT" ]; then
    echo -e "${RED}ERROR: Device agent not found or not executable: $DEVICE_AGENT${NC}"
    exit 1
fi

if [ ! -x "$TEST_RECORDER" ]; then
    echo -e "${RED}ERROR: Test recorder not found or not executable: $TEST_RECORDER${NC}"
    exit 1
fi

# Check GUI server health
echo "Checking GUI server at $GUI_URL..."
if $DEVICE_AGENT health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ GUI server is healthy${NC}"
else
    echo -e "${RED}✗ GUI server not responding${NC}"
    echo "  Make sure GhidraVibe is running:"
    echo "    nix run .#ghidraVibe"
    exit 1
fi

echo

# Determine what to run
SCENARIO="${1:-all}"

run_scenario() {
    local scenario_file="$1"
    local scenario_name=$(basename "$scenario_file" .json)
    
    echo -e "${YELLOW}Running: $scenario_name${NC}"
    if $TEST_RECORDER play "$scenario_file"; then
        echo -e "${GREEN}✓ $scenario_name PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ $scenario_name FAILED${NC}"
        return 1
    fi
}

case "$SCENARIO" in
    smoke)
        run_scenario "$SCENARIOS_DIR/smoke-test.json"
        ;;
    dyld)
        run_scenario "$SCENARIOS_DIR/dyld-workflow.json"
        ;;
    navigation)
        run_scenario "$SCENARIOS_DIR/navigation-test.json"
        ;;
    agent)
        run_scenario "$SCENARIOS_DIR/agent-test.json"
        ;;
    all)
        echo "Running all scenarios..."
        echo
        
        PASSED=0
        FAILED=0
        
        for scenario in "$SCENARIOS_DIR"/*.json; do
            if run_scenario "$scenario"; then
                ((PASSED++))
            else
                ((FAILED++))
            fi
            echo
        done
        
        echo "=== Summary ==="
        echo -e "Passed: ${GREEN}$PASSED${NC}"
        echo -e "Failed: ${RED}$FAILED${NC}"
        
        if [ $FAILED -eq 0 ]; then
            echo -e "${GREEN}All tests passed!${NC}"
            exit 0
        else
            echo -e "${RED}Some tests failed${NC}"
            exit 1
        fi
        ;;
    list)
        echo "Available scenarios:"
        for scenario in "$SCENARIOS_DIR"/*.json; do
            name=$(basename "$scenario" .json)
            echo "  - $name"
        done
        ;;
    *)
        # Try to run as custom scenario file
        if [ -f "$SCENARIO" ]; then
            run_scenario "$SCENARIO"
        else
            echo -e "${RED}Unknown scenario: $SCENARIO${NC}"
            echo "Usage: $0 [smoke|dyld|navigation|agent|all|list|path/to/scenario.json]"
            exit 1
        fi
        ;;
esac

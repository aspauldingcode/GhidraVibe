# GhidraVibe Device Agent - GUI Testing Guide

The GhidraVibe Device Agent provides reproducible GUI testing through MCP (Model Context Protocol) integration. This enables automated testing of the GUI in CI/CD pipelines and local development.

## Overview

The device agent consists of three main components:

1. **Device Agent CLI** (`ghidra-vibe-device-agent`) - Direct GUI control and automation
2. **Test Recorder** (`ghidra-vibe-test-recorder`) - Record and replay test scenarios
3. **Test Scenarios** (`gui-tests/scenarios/`) - Pre-defined test cases

## Prerequisites

- GhidraVibe GUI server running (default: `http://127.0.0.1:8091`)
- Python 3.8 or later
- MCP server connectivity (for full integration tests)

## Device Agent CLI

### Basic Usage

```bash
# Check GUI server health
./scripts/ghidra-vibe-device-agent health

# Get current GUI state
./scripts/ghidra-vibe-device-agent state

# Navigate to a pane
./scripts/ghidra-vibe-device-agent navigate functions

# Search for functions
./scripts/ghidra-vibe-device-agent search "NSWindow"

# Run an action
./scripts/ghidra-vibe-device-agent action mcp_health
```

### dyld Shared Cache Operations

```bash
# List available caches
./scripts/ghidra-vibe-device-agent dyld-list

# List images in cache
./scripts/ghidra-vibe-device-agent dyld-list --images

# Search for specific images
./scripts/ghidra-vibe-device-agent dyld-list --images --query AppKit

# Open an image for analysis
./scripts/ghidra-vibe-device-agent dyld-open AppKit
```

### Running Test Scenarios

```bash
# Run smoke test (basic health checks)
./scripts/ghidra-vibe-device-agent test smoke

# Run dyld workflow test
./scripts/ghidra-vibe-device-agent test dyld

# Run navigation test (all panes)
./scripts/ghidra-vibe-device-agent test navigation

# Run all tests
./scripts/ghidra-vibe-device-agent test all
```

### Verbose Mode

```bash
# Enable verbose logging
./scripts/ghidra-vibe-device-agent -v test smoke

# Use custom URL
./scripts/ghidra-vibe-device-agent --url http://localhost:9091 health
```

## Test Recorder

The test recorder allows you to create replayable test scenarios.

### Recording a Test

```bash
./scripts/ghidra-vibe-test-recorder record
```

**Interactive commands:**
```
> health                          # Check server health
> state                           # Get GUI state
> navigate functions              # Navigate to pane
> search NSWindow                 # Search for functions
> action mcp_health               # Run action
> wait 2                          # Wait 2 seconds
> save my-test.json               # Save recording
> quit                            # Exit recorder
```

### Playing Back a Test

```bash
# Play a recorded test
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/smoke-test.json

# Play in strict mode (stop on first failure)
./scripts/ghidra-vibe-test-recorder play --strict my-test.json

# Save results to file
./scripts/ghidra-vibe-test-recorder play --output results.json my-test.json
```

### Creating Tests from Templates

```bash
# Create smoke test
./scripts/ghidra-vibe-test-recorder create smoke smoke-test.json

# Create dyld workflow test
./scripts/ghidra-vibe-test-recorder create dyld dyld-test.json

# Create navigation test
./scripts/ghidra-vibe-test-recorder create navigation nav-test.json
```

## Pre-defined Test Scenarios

### Smoke Test (`gui-tests/scenarios/smoke-test.json`)

Tests basic GUI functionality:
- Server health check
- State retrieval
- MCP connectivity
- Function fetching

**Usage:**
```bash
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/smoke-test.json
```

### dyld Workflow Test (`gui-tests/scenarios/dyld-workflow.json`)

Tests dyld shared cache operations:
- Cache discovery
- Image listing
- Framework search (AppKit, Foundation)
- Function search (NSWindow)
- Cache dialog opening

**Usage:**
```bash
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/dyld-workflow.json
```

### Navigation Test (`gui-tests/scenarios/navigation-test.json`)

Tests UI navigation between panes:
- Functions pane
- Decompiler pane
- Listing pane
- Symbol tree pane
- Memory map pane
- Data types pane

**Usage:**
```bash
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/navigation-test.json
```

### Agent Test (`gui-tests/scenarios/agent-test.json`)

Tests Agent sidebar functionality:
- Agent status check
- Agent pane navigation
- Message sending
- Response handling

**Usage:**
```bash
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/agent-test.json
```

## CI/CD Integration

The device agent is integrated into the CI pipeline (`.github/workflows/multiplatform-ci.yml`):

```yaml
device-agent-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Test device agent CLI
      run: ./scripts/ghidra-vibe-device-agent --help
    - name: Test recorder CLI
      run: ./scripts/ghidra-vibe-test-recorder --help
    - name: Validate test scenarios
      run: |
        for scenario in gui-tests/scenarios/*.json; do
          python3 -m json.tool "$scenario" > /dev/null
        done
```

## Test Scenario Format

Test scenarios are JSON files with the following structure:

```json
{
  "version": "1.0",
  "name": "Test Name",
  "description": "Test description",
  "created": 1721545200,
  "actions": [
    {
      "type": "action_type",
      "params": {
        "param1": "value1"
      },
      "timestamp": 0.0,
      "expected_ok": true,
      "description": "Action description"
    }
  ]
}
```

### Supported Action Types

| Action Type | Parameters | Description |
|-------------|------------|-------------|
| `health` | - | Check GUI server health |
| `state` | - | Get current GUI state |
| `navigate` | `pane` | Navigate to sidebar pane |
| `search` | `query` | Set function search query |
| `select_function` | `name`, `address`, `id` | Select a function |
| `action` | `action_id` | Run toolbar/action |
| `dyld_list_caches` | - | List dyld caches |
| `dyld_list_images` | `query` | List/filter cache images |
| `dyld_open_image` | `image` | Open image for analysis |
| `agent_send` | `text` | Send message to Agent |
| `agent_status` | - | Get Agent status |
| `wait` | `seconds` | Wait for specified time |

## Writing Custom Tests

### Example: Custom dyld Test

```json
{
  "version": "1.0",
  "name": "Custom dyld Test",
  "description": "Test specific framework",
  "created": 1721545200,
  "actions": [
    {
      "type": "dyld_list_caches",
      "params": {},
      "timestamp": 0,
      "expected_ok": true
    },
    {
      "type": "dyld_list_images",
      "params": {"query": "CoreGraphics"},
      "timestamp": 1.0,
      "expected_ok": true
    },
    {
      "type": "dyld_open_image",
      "params": {"image": "CoreGraphics"},
      "timestamp": 2.0,
      "expected_ok": true
    },
    {
      "type": "search",
      "params": {"query": "CGContext"},
      "timestamp": 3.0,
      "expected_ok": true
    }
  ]
}
```

### Example: Custom Navigation Test

```json
{
  "version": "1.0",
  "name": "Quick Navigation",
  "actions": [
    {
      "type": "navigate",
      "params": {"pane": "functions"},
      "timestamp": 0,
      "expected_ok": true
    },
    {
      "type": "search",
      "params": {"query": "main"},
      "timestamp": 1.0,
      "expected_ok": true
    },
    {
      "type": "navigate",
      "params": {"pane": "decompiler"},
      "timestamp": 2.0,
      "expected_ok": true
    }
  ]
}
```

## Troubleshooting

### GUI Server Not Running

```bash
# Check if server is running
./scripts/ghidra-vibe-device-agent health

# Expected error if not running:
# ❌ GUI server not healthy
```

**Solution:** Start GhidraVibe with GUI server enabled.

### Connection Refused

```bash
# Check URL
export GHIDRA_VIBE_GUI_URL=http://127.0.0.1:8091
./scripts/ghidra-vibe-device-agent health
```

### Test Failures

```bash
# Run with verbose mode
./scripts/ghidra-vibe-device-agent -v test smoke

# Check detailed results
./scripts/ghidra-vibe-test-recorder play --output results.json test.json
cat results.json
```

### Timeout Issues

Add wait actions between operations:

```json
{
  "type": "wait",
  "params": {"seconds": 2.0},
  "timestamp": 1.0,
  "expected_ok": true
}
```

## Advanced Usage

### Programmatic API

```python
from ghidra_vibe_device_agent import DeviceAgent

# Create agent
agent = DeviceAgent(verbose=True)

# Wait for server
if not agent.wait_for_ready(timeout=30):
    print("Server not ready")
    exit(1)

# Run operations
agent.navigate("functions")
agent.search("NSWindow")
agent.action("decompile")

# Get results
summary = agent.get_summary()
print(f"Success rate: {summary['success_rate']:.1f}%")
```

### Custom Test Runner

```python
from ghidra_vibe_test_recorder import TestPlayer, DeviceAgent

agent = DeviceAgent()
player = TestPlayer(agent, strict=False)

# Load and play test
test_data = player.load("my-test.json")
summary = player.play(test_data)

# Check results
if summary["failed"] > 0:
    print(f"Test failed: {summary['failed']} failures")
    for result in summary["results"]:
        if not result["passed"]:
            print(f"  - {result['action']}: {result['result']}")
```

## Best Practices

1. **Always check health first**: Start tests with health check
2. **Use waits appropriately**: Add delays between operations
3. **Record realistic scenarios**: Record actual usage patterns
4. **Use descriptive names**: Name tests clearly
5. **Version scenarios**: Track changes to test files
6. **Validate before running**: Check JSON syntax before playback
7. **Use strict mode carefully**: Only for critical tests
8. **Save results**: Use `--output` to track test history
9. **Test incrementally**: Build complex tests from simple ones
10. **Document expectations**: Add descriptions to actions

## Examples

### Complete Workflow Test

```bash
# 1. Start GhidraVibe
nix run .#ghidraVibe &

# 2. Wait for startup
sleep 5

# 3. Run health check
./scripts/ghidra-vibe-device-agent health

# 4. Run smoke test
./scripts/ghidra-vibe-device-agent test smoke

# 5. Run dyld test
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/dyld-workflow.json

# 6. Run custom test
./scripts/ghidra-vibe-test-recorder play my-custom-test.json --output results.json

# 7. Check results
python3 -c "import json; r=json.load(open('results.json')); print(f\"Pass: {r['passed']}/{r['total']}\")"
```

### CI Pipeline Integration

```yaml
test-gui:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Start GhidraVibe
      run: nix run .#ghidraVibe &
    - name: Wait for startup
      run: sleep 10
    - name: Run device agent tests
      run: |
        ./scripts/ghidra-vibe-device-agent test all
    - name: Run scenario tests
      run: |
        for scenario in gui-tests/scenarios/*.json; do
          ./scripts/ghidra-vibe-test-recorder play --strict "$scenario"
        done
```

## Future Enhancements

- [ ] Screenshot capture during test execution
- [ ] Video recording of test runs
- [ ] Performance metrics collection
- [ ] Parallel test execution
- [ ] Test result visualization
- [ ] Integration with test frameworks (pytest, unittest)
- [ ] Remote test execution
- [ ] Test coverage analysis
- [ ] Automatic test generation from usage logs
- [ ] Fuzzing support for GUI operations

## See Also

- [TESTING_DYLD.md](TESTING_DYLD.md) - dyld shared cache testing
- [MCP Tool Map](../native-ui/mcp/tool-map.json) - Available MCP tools
- [CI Workflow](../.github/workflows/multiplatform-ci.yml) - CI integration

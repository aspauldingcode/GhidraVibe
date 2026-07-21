# Testing GhidraVibe MCP Functionality with Cursor IDE

This guide explains how to test and use GhidraVibe's MCP (Model Context Protocol) integration with Cursor IDE.

## Overview

GhidraVibe exposes 4 MCP servers for programmatic control:

| Server | Port | Purpose | Key Features |
|--------|------|---------|--------------|
| **Analysis** | 8089 | Ghidra engine | Decompilation, disassembly, functions, symbols |
| **Vibe** | 8092 | Extended features | dyld cache, RAG, scripts, Apple bundles |
| **GUI** | 8091 | UI control | Navigation, search, state management |
| **Debugger** | 8099 | Debugging | Breakpoints, stepping, registers |

## Quick Start

### 1. Start GhidraVibe

```bash
# Start GhidraVibe (this starts all MCP servers)
nix run .#ghidraVibe

# Or use the macOS app
open result/Applications/GhidraVibe.app
```

### 2. Test MCP Connectivity

```bash
# Run the MCP functionality tester
./scripts/test-mcp-functionality

# Expected output when servers are running:
# ✓ analysis server is healthy
# ✓ vibe server is healthy
# ✓ gui server is healthy
# ✓ debugger server is healthy
```

### 3. Use Device Agent for Testing

```bash
# Test GUI server
./scripts/ghidra-vibe-device-agent health

# Run smoke tests
./scripts/ghidra-vibe-device-agent test smoke

# Test dyld workflow
./scripts/ghidra-vibe-device-agent test dyld
```

## MCP Server Configuration for Cursor IDE

To use GhidraVibe's MCP servers with Cursor IDE, add them to your MCP configuration:

### Method 1: Using MCP Bridge Scripts (Recommended)

The bridge scripts convert HTTP-based MCP servers to stdio-based MCP for Cursor.

**Add to your Cursor MCP settings:**

```json
{
  "mcpServers": {
    "ghidra-vibe-gui": {
      "command": "python3",
      "args": ["/path/to/GhidraVibe/nix/share/bridge_mcp_gui.py"],
      "env": {
        "GHIDRA_VIBE_GUI_URL": "http://127.0.0.1:8091"
      }
    },
    "ghidra-vibe-analysis": {
      "command": "python3",
      "args": ["/path/to/GhidraVibe/scripts/bridge_mcp_analysis.py"],
      "env": {
        "GHIDRA_MCP_URL": "http://127.0.0.1:8089"
      }
    },
    "ghidra-vibe-extended": {
      "command": "python3",
      "args": ["/path/to/GhidraVibe/nix/share/bridge_mcp_vibe.py"],
      "env": {
        "GHIDRA_VIBE_MCP_EXT_URL": "http://127.0.0.1:8092"
      }
    }
  }
}
```

### Method 2: Direct HTTP Access (Alternative)

If Cursor supports HTTP-based MCP servers directly:

```json
{
  "mcpServers": {
    "ghidra-analysis": {
      "url": "http://127.0.0.1:8089"
    },
    "ghidra-vibe": {
      "url": "http://127.0.0.1:8092"
    },
    "ghidra-gui": {
      "url": "http://127.0.0.1:8091"
    }
  }
}
```

## Available MCP Tools

### GUI Server Tools (Port 8091)

```typescript
// Health check
gui_health()

// Get current UI state
gui_state()

// Navigate to sidebar pane
gui_navigate({ pane: "functions" | "decompiler" | "listing" | ... })

// Search for functions
gui_search({ query: "NSWindow" })

// Select a function
gui_select_function({ name: "main", address: "0x100000000", id: "func_id" })

// Run an action
gui_action({ id: "mcp_health" | "decompile" | "fetch_functions" | ... })

// dyld shared cache operations
dyld_list_caches()
dyld_list_images({ query: "AppKit" })
dyld_open_image({ image: "AppKit" })

// Agent operations
agent_send({ text: "Analyze this function" })
agent_status()
agent_playbook({ budget: 8, apply: true })
agent_rename({ address: "0x100000000", new_name: "my_function" })
agent_comment({ address: "0x100000000", comment: "This is important", kind: "plate" })
```

### Analysis Server Tools (Port 8089)

```typescript
// Connection
check_connection()

// Functions
list_functions()
disassemble_function({ address: "0x100000000" })
decompile_function({ address: "0x100000000" })
get_function_call_graph({ address: "0x100000000" })
analyze_control_flow({ address: "0x100000000" })

// Symbols
list_namespaces()
list_exports()
list_imports()
list_globals()
get_xrefs_to({ address: "0x100000000" })
get_xrefs_from({ address: "0x100000000" })

// Memory
list_segments()
read_memory({ address: "0x100000000", size: 256 })
inspect_memory_content({ address: "0x100000000" })

// Data types
list_data_types()
get_struct_layout({ name: "MyStruct" })
list_data_items()

// Strings
list_strings()

// Bookmarks
list_bookmarks()
```

### Vibe Server Tools (Port 8092)

```typescript
// dyld Shared Cache
dyld_find_cache()
dyld_list_images({ query: "Foundation" })
dyld_import_image({ image: "AppKit", analyze: true })

// Apple Bundles
malimite_open_bundle({ path: "/path/to/MyApp.app" })
malimite_list_bundle_binaries()
malimite_analyze({ binary: "MyApp" })
malimite_list_classes()

// RAG (Retrieval-Augmented Generation)
rag_discover()
rag_index({ path: "/path/to/docs" })
rag_search({ query: "How to use this API?" })
rag_stats()

// Scripts
vibe_list_scripts()
list_ghidra_scripts()
run_ghidra_script({ script: "script_name.py", args: [] })

// Navigation
vibe_undo()
vibe_redo()
vibe_nav_back()
vibe_nav_forward()
vibe_clear_selection()

// Listing operations
listing_disassemble({ address: "0x100000000" })
listing_define_data({ address: "0x100000000", dataType: "int" })
listing_clear_code({ start: "0x100000000", end: "0x100001000" })
listing_create_label({ address: "0x100000000", name: "my_label" })
listing_create_function({ address: "0x100000000" })
listing_add_bookmark({ address: "0x100000000", comment: "Important" })

// Editing
edit_copy()
search_memory({ pattern: "41424344" })

// Swift
swift_list_namespaces()
swift_demangle({ mangled: "_TtC4Test8MyClass" })
```

## Testing MCP Functionality

### Automated Testing

```bash
# 1. Test MCP server connectivity
./scripts/test-mcp-functionality

# 2. Run device agent tests
./scripts/ghidra-vibe-device-agent test all

# 3. Run test scenarios
./gui-tests/run-device-agent-tests.sh all

# 4. Run specific scenario
./scripts/ghidra-vibe-test-recorder play gui-tests/scenarios/dyld-workflow.json
```

### Manual Testing with Cursor IDE

#### Test 1: GUI Navigation

```python
# In Cursor, with MCP enabled:
# 1. Navigate to functions pane
result = gui_navigate(pane="functions")

# 2. Search for a function
result = gui_search(query="main")

# 3. Get current state
state = gui_state()
print(state)
```

#### Test 2: dyld Shared Cache Workflow

```python
# 1. Find cache
cache = dyld_list_caches()

# 2. List images
images = dyld_list_images(query="AppKit")

# 3. Open an image
result = dyld_open_image(image="AppKit")

# 4. Search for NSWindow
search = gui_search(query="NSWindow")
```

#### Test 3: Decompilation

```python
# 1. List functions
functions = list_functions()

# 2. Select a function
gui_select_function(name="main")

# 3. Decompile
decompiled = decompile_function(address="0x100000000")
print(decompiled)
```

#### Test 4: Agent Integration

```python
# 1. Check agent status
status = agent_status()

# 2. Send a command
result = agent_send(text="Analyze this binary and find the main function")

# 3. Wait for response
import time
time.sleep(5)

# 4. Check status again
status = agent_status()
```

## Test Results

After running `./scripts/test-mcp-functionality`, check the results:

```bash
# View results
cat mcp-test-results.json

# Example output:
# {
#   "summary": {
#     "total": 15,
#     "passed": 15,
#     "failed": 0,
#     "success_rate": 100.0
#   },
#   ...
# }
```

## Common Use Cases

### Use Case 1: Automated Function Analysis

```python
# 1. Connect to analysis server
health = check_connection()

# 2. List all functions
functions = list_functions()

# 3. Analyze each function
for func in functions[:10]:  # First 10
    address = func["address"]
    
    # Decompile
    decompiled = decompile_function(address=address)
    
    # Get call graph
    graph = get_function_call_graph(address=address)
    
    # Add analysis comment
    agent_comment(
        address=address,
        comment=f"Analyzed: {len(graph['callers'])} callers, {len(graph['callees'])} callees",
        kind="plate"
    )
```

### Use Case 2: dyld Framework Analysis

```python
# 1. Find dyld cache
cache = dyld_find_cache()

# 2. Search for frameworks
frameworks = dyld_list_images(query="")

# 3. Filter for interesting frameworks
interesting = ["AppKit", "Foundation", "CoreGraphics", "Metal"]

# 4. Import and analyze each
for framework in interesting:
    print(f"Analyzing {framework}...")
    
    # Import with analysis
    result = dyld_import_image(image=framework)
    
    # Wait for import
    time.sleep(5)
    
    # List functions from this framework
    functions = list_functions()
    
    print(f"  Found {len(functions)} functions in {framework}")
```

### Use Case 3: Bulk Rename Functions

```python
# 1. Get list of functions
functions = list_functions()

# 2. Filter unnamed functions
unnamed = [f for f in functions if f["name"].startswith("FUN_")]

# 3. Use agent to rename
for func in unnamed[:5]:  # First 5
    address = func["address"]
    
    # Get decompilation for context
    decompiled = decompile_function(address=address)
    
    # Ask agent to suggest name
    agent_send(text=f"Suggest a better name for function at {address}")
    
    time.sleep(2)
    
    # (Agent would suggest via UI, then you can apply)
```

## Troubleshooting

### Issue: MCP Servers Not Responding

```bash
# Check if GhidraVibe is running
ps aux | grep ghidra

# Check server connectivity
./scripts/test-mcp-functionality

# Check specific server
curl http://127.0.0.1:8091/health
```

**Solution:** Start GhidraVibe:
```bash
nix run .#ghidraVibe
```

### Issue: Cursor Can't Connect to MCP

**Check:**
1. MCP bridge scripts exist:
   ```bash
   ls -la nix/share/bridge_mcp_*.py
   ```

2. Scripts are executable:
   ```bash
   chmod +x nix/share/bridge_mcp_*.py
   ```

3. Python dependencies available:
   ```bash
   python3 -c "import json, urllib.request"
   ```

### Issue: Tool Not Found

**Verify tool availability:**
```bash
# Check tool map
cat native-ui/mcp/tool-map.json | jq '.actions | keys'

# Test specific tool
./scripts/ghidra-vibe-device-agent action mcp_health
```

## Advanced Testing

### Load Testing

```python
import concurrent.futures
import time

def test_decompile(address):
    return decompile_function(address=address)

# Get function addresses
functions = list_functions()
addresses = [f["address"] for f in functions[:100]]

# Parallel decompilation
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
    start = time.time()
    results = list(executor.map(test_decompile, addresses))
    duration = time.time() - start
    
print(f"Decompiled {len(results)} functions in {duration:.2f}s")
print(f"Average: {duration/len(results):.3f}s per function")
```

### Integration Testing

```bash
# Run full integration test suite
./gui-tests/run-device-agent-tests.sh all

# Record a custom test
./scripts/ghidra-vibe-test-recorder record
# > gui_health
# > dyld_list_caches
# > dyld_list_images --query AppKit
# > save integration-test.json
# > quit

# Play it back
./scripts/ghidra-vibe-test-recorder play integration-test.json
```

## Performance Metrics

Expected response times (approximate):

| Operation | Response Time | Notes |
|-----------|--------------|-------|
| Health check | <100ms | Should be nearly instant |
| List functions | 100-500ms | Depends on binary size |
| Decompile function | 200-2000ms | Complex functions take longer |
| dyld list images | 100-300ms | Cache must be loaded |
| dyld import image | 5-30s | Includes analysis |
| Agent command | 1-10s | Depends on LLM response |

## See Also

- [DEVICE_AGENT.md](DEVICE_AGENT.md) - Device agent documentation
- [TESTING_DYLD.md](TESTING_DYLD.md) - dyld testing guide
- [MCP Tool Map](../native-ui/mcp/tool-map.json) - Complete tool mapping
- [Bridge Scripts](../nix/share/) - MCP bridge implementations

## CI Integration

The MCP functionality tests are integrated into CI:

```yaml
# .github/workflows/multiplatform-ci.yml
mcp-functionality-test:
  runs-on: ubuntu-latest
  steps:
    - name: Test MCP bridge scripts
      run: |
        for script in nix/share/bridge_mcp_*.py; do
          python3 "$script" --help || echo "Script found: $script"
        done
    
    - name: Validate tool map
      run: |
        python3 -m json.tool native-ui/mcp/tool-map.json
```

## Contributing

When adding new MCP tools:

1. Update `native-ui/mcp/tool-map.json`
2. Add bridge implementation to `nix/share/bridge_mcp_*.py`
3. Update this documentation
4. Add test case to `scripts/test-mcp-functionality`
5. Create test scenario in `gui-tests/scenarios/`

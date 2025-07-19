# GhidraMCP Vibe RSE

Cross-platform Ghidra MCP setup with dyld cache support for reverse engineering workflows.

## Features

- **Cross-platform support**: Linux and macOS (x86_64 and ARM64)
- **Reproducible environment**: Nix flakes ensure consistent setups
- **Ghidra integration**: Automated Ghidra 11.0.1 installation and configuration
- **MCP bridge**: Ready-to-use Model Context Protocol integration
- **dyld cache extraction**: macOS framework extraction capabilities
- **Apple Silicon support**: Native binary building for M1/M2 Macs

## Quick Start

```bash
# Enter the development environment
nix develop

# Run complete setup
setup-ghidra-mcp-vibe

# Or run individual components
setup-ghidra           # Install Ghidra
setup-mcp-bridge       # Setup MCP bridge
extract-dyld-cache     # Extract dyld cache (macOS only)
```

## Available Commands

- `setup-ghidra-mcp-vibe` - Complete setup workflow
- `setup-ghidra` - Download and configure Ghidra 11.0.1
- `setup-mcp-bridge` - Clone and build GhidraMCP plugin
- `extract-dyld-cache` - Extract macOS dyld shared cache

## Platform Support

- **Linux**: x86_64, aarch64
- **macOS**: x86_64, aarch64 (Apple Silicon)

## Dependencies

The Nix flake automatically provides:
- Python 3 with lief, construct, tqdm, click, requests, pyyaml
- Java 21 for Ghidra
- Build tools (gradle, maven, git, curl, wget, unzip)
- Platform-specific frameworks and libraries

## Directory Structure
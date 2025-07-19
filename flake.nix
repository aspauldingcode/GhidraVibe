{
  description = "GhidraMCP Vibe RSE - Cross-platform Ghidra MCP setup with dyld cache support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Python environment with required packages
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          requests
          click
          pyyaml
          lief
          construct
          tqdm
          typing-extensions
        ]);

        # Java environment for Ghidra
        javaEnv = pkgs.openjdk21;

        # Build tools
        buildTools = with pkgs; [
          gradle
          maven
          git
          curl
          wget
          unzip
          which
        ] ++ lib.optionals stdenv.isDarwin [
          darwin.xcode
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.Security
        ] ++ lib.optionals stdenv.isLinux [
          gcc
          glibc
          binutils
        ];

        # DyldExtractor - Python tool for extracting dyld shared cache
        dyldExtractor = pkgs.python3Packages.buildPythonApplication rec {
          pname = "dyldextractor";
          version = "1.0.0";
          
          src = pkgs.fetchFromGitHub {
            owner = "arandomdev";
            repo = "DyldExtractor";
            rev = "main";
            sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Replace with actual hash
          };

          propagatedBuildInputs = with pkgs.python3Packages; [
            lief
            construct
            tqdm
            click
          ];

          doCheck = false;
        };

        # Ghidra installation script
        ghidraSetup = pkgs.writeShellScriptBin "setup-ghidra" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          GHIDRA_VERSION="11.0.1"
          GHIDRA_DATE="20240130"
          GHIDRA_DIR="$HOME/.local/share/ghidra"
          
          echo "Setting up Ghidra ${GHIDRA_VERSION}..."
          
          # Create Ghidra directory
          mkdir -p "$GHIDRA_DIR"
          cd "$GHIDRA_DIR"
          
          # Download Ghidra if not present
          if [ ! -d "ghidra_${GHIDRA_VERSION}_PUBLIC" ]; then
            echo "Downloading Ghidra..."
            curl -L "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip" -o ghidra.zip
            unzip ghidra.zip
            rm ghidra.zip
          fi
          
          # Build native binaries for Apple Silicon if on macOS ARM64
          if [[ "$(uname)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
            echo "Building native binaries for Apple Silicon..."
            cd "ghidra_${GHIDRA_VERSION}_PUBLIC/support"
            ./buildNatives
          fi
          
          echo "Ghidra setup complete!"
          echo "Ghidra location: $GHIDRA_DIR/ghidra_${GHIDRA_VERSION}_PUBLIC"
        '';

        # MCP bridge setup script
        mcpBridgeSetup = pkgs.writeShellScriptBin "setup-mcp-bridge" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          echo "Setting up MCP bridge for Ghidra..."
          
          # Clone GhidraMCP if not present
          if [ ! -d "GhidraMCP" ]; then
            git clone https://github.com/LaurieWired/GhidraMCP.git
          fi
          
          cd GhidraMCP
          
          # Build the plugin
          if [ -f "pom.xml" ]; then
            mvn clean package assembly:single
          elif [ -f "build.gradle" ]; then
            gradle buildExtension
          fi
          
          echo "MCP bridge setup complete!"
        '';

        # Dyld cache extraction workflow
        dyldCacheWorkflow = pkgs.writeShellScriptBin "extract-dyld-cache" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          CACHE_DIR="$HOME/.local/share/dyld-cache"
          OUTPUT_DIR="$HOME/.local/share/extracted-frameworks"
          
          echo "Setting up dyld cache extraction workflow..."
          
          mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"
          
          # Detect platform and locate dyld cache
          if [[ "$(uname)" == "Darwin" ]]; then
            # macOS dyld cache locations
            if [[ -d "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld" ]]; then
              DYLD_PATH="/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld"
            elif [[ -d "/System/Library/dyld" ]]; then
              DYLD_PATH="/System/Library/dyld"
            else
              echo "Could not locate dyld cache on this macOS system"
              exit 1
            fi
            
            echo "Found dyld cache at: $DYLD_PATH"
            echo "Copying dyld cache files..."
            cp -r "$DYLD_PATH"/* "$CACHE_DIR/"
            
            echo "Extracting frameworks using DyldExtractor..."
            ${dyldExtractor}/bin/dyldextractor "$CACHE_DIR/dyld_shared_cache_arm64e" "$OUTPUT_DIR"
          else
            echo "This script is designed for macOS dyld cache extraction"
            echo "For iOS dyld cache, please provide IPSW file manually"
          fi
          
          echo "Extraction complete! Frameworks available in: $OUTPUT_DIR"
        '';

        # Complete setup script
        setupScript = pkgs.writeShellScriptBin "setup-ghidra-mcp-vibe" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          echo "🚀 Setting up GhidraMCP Vibe RSE environment..."
          
          # Setup Ghidra
          ${ghidraSetup}/bin/setup-ghidra
          
          # Setup MCP bridge
          ${mcpBridgeSetup}/bin/setup-mcp-bridge
          
          # Extract dyld cache (macOS only)
          if [[ "$(uname)" == "Darwin" ]]; then
            ${dyldCacheWorkflow}/bin/extract-dyld-cache
          fi
          
          echo "✅ Setup complete!"
          echo ""
          echo "Next steps:"
          echo "1. Start Ghidra: ~/.local/share/ghidra/ghidra_*/ghidraRun"
          echo "2. Install the MCP plugin from GhidraMCP/dist/"
          echo "3. Configure your MCP client to connect to Ghidra"
          echo "4. Import extracted frameworks for analysis"
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pythonEnv
            javaEnv
            dyldExtractor
            setupScript
            ghidraSetup
            mcpBridgeSetup
            dyldCacheWorkflow
          ] ++ buildTools;

          shellHook = ''
            echo "🎯 GhidraMCP Vibe RSE Development Environment"
            echo "Platform: ${system}"
            echo ""
            echo "Available commands:"
            echo "  setup-ghidra-mcp-vibe  - Complete setup"
            echo "  setup-ghidra           - Install Ghidra"
            echo "  setup-mcp-bridge       - Setup MCP bridge"
            echo "  extract-dyld-cache     - Extract dyld cache (macOS)"
            echo ""
            echo "Python packages available:"
            echo "  - lief, construct, tqdm, click, requests, pyyaml"
            echo ""
            echo "Java: ${javaEnv.version}"
            echo "Python: $(python --version)"
          '';

          # Environment variables
          JAVA_HOME = "${javaEnv}";
          GHIDRA_INSTALL_DIR = "$HOME/.local/share/ghidra";
          MCP_SERVER_PORT = "8080";
          
          # Platform-specific environment
          NIX_CFLAGS_COMPILE = pkgs.lib.optionalString pkgs.stdenv.isDarwin "-I${pkgs.darwin.apple_sdk.frameworks.Foundation}/include";
        };

        packages = {
          inherit dyldExtractor setupScript ghidraSetup mcpBridgeSetup dyldCacheWorkflow;
          default = setupScript;
        };

        apps = {
          default = flake-utils.lib
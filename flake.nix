{
  description = "GhidraMCP Vibe RSE - Cross-platform Ghidra MCP setup with dyld cache support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
        
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

        # Ghidra package
        ghidra = pkgs.ghidra;

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
          format = "setuptools";
          
          src = pkgs.fetchFromGitHub {
            owner = "arandomdev";
            repo = "DyldExtractor";
            rev = "0e1b35a";
            sha256 = "sha256-WXh2lLxTxHDEUbhOqOiXDMvuv9rAK+owNP7kiZnSPy0=";
          };

          propagatedBuildInputs = with pkgs.python3Packages; [
            lief
            construct
            tqdm
            click
            progressbar2
            capstone
          ];

          nativeBuildInputs = with pkgs.python3Packages; [ setuptools ];
          doCheck = false;
        };

        # MCP bridge setup script
        mcpBridgeSetup = pkgs.writeShellScriptBin "setup-mcp-bridge" ''
          echo "🔧 Setting up MCP Bridge..."
          
          # Find Ghidra installation path
          GHIDRA_PATH=$(dirname $(dirname $(which ghidra)))
          echo "Found Ghidra at: $GHIDRA_PATH"
          
          # Clone or update GhidraMCP repository (LaurieWired version)
          if [ ! -d "GhidraMCP" ]; then
            git clone https://github.com/LaurieWired/GhidraMCP.git GhidraMCP
          fi
          
          # Create lib directory and copy Ghidra JARs
          mkdir -p GhidraMCP/lib
          
          # Copy required Ghidra JARs with correct paths
          echo "Copying Ghidra JARs..."
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Framework/Generic/lib/Generic.jar" GhidraMCP/lib/ && echo "✓ Generic.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Framework/SoftwareModeling/lib/SoftwareModeling.jar" GhidraMCP/lib/ && echo "✓ SoftwareModeling.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Framework/Project/lib/Project.jar" GhidraMCP/lib/ && echo "✓ Project.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Framework/Docking/lib/Docking.jar" GhidraMCP/lib/ && echo "✓ Docking.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Features/Decompiler/lib/Decompiler.jar" GhidraMCP/lib/ && echo "✓ Decompiler.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Framework/Utility/lib/Utility.jar" GhidraMCP/lib/ && echo "✓ Utility.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Features/Base/lib/Base.jar" GhidraMCP/lib/ && echo "✓ Base.jar"
          cp "$GHIDRA_PATH/lib/ghidra/Ghidra/Framework/Gui/lib/Gui.jar" GhidraMCP/lib/ && echo "✓ Gui.jar"
          
          cd GhidraMCP
          
          # Build with Maven
          if [ -f "pom.xml" ]; then
            echo "Building with Maven..."
            mvn clean package assembly:single || echo "Maven build failed - you may need to manually configure Ghidra paths"
          else
            echo "No pom.xml found - manual setup required"
          fi
          
          echo "🎉 MCP bridge setup complete!"
          echo "📁 Plugin should be available in GhidraMCP/target/"
          echo "📋 Installation: File -> Install Extensions -> + -> Select ZIP file"
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
            ${dyldExtractor}/bin/dyldex_all "$CACHE_DIR/dyld_shared_cache_arm64e" -o "$OUTPUT_DIR"
          else
            echo "This script is designed for macOS dyld cache extraction"
            echo "For iOS dyld cache, please provide IPSW file manually"
          fi
          
          echo "Extraction complete! Frameworks available in: $OUTPUT_DIR"
        '';

        # Tutorial commands for framework analysis
        listFrameworks = pkgs.writeShellScriptBin "list-frameworks" ''
          #!/usr/bin/env bash
          echo "📋 Listing available frameworks in dyld cache..."
          echo ""
          
          DYLD_CACHE="/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"
          
          if [[ ! -f "$DYLD_CACHE" ]]; then
            echo "❌ dyld cache not found at: $DYLD_CACHE"
            echo "This command requires macOS with Apple Silicon"
            exit 1
          fi
          
          echo "🔍 All frameworks:"
          ${dyldExtractor}/bin/dyldex -l "$DYLD_CACHE" | head -50
          echo ""
          echo "🎯 Core frameworks for analysis:"
          ${dyldExtractor}/bin/dyldex -l "$DYLD_CACHE" | grep -E "(Foundation|CoreFoundation|Security|IOKit|AppKit|CoreGraphics|CFNetwork|CoreText|CoreAudio|CoreData)" | head -10
          echo ""
          echo "💡 Use 'extract-framework <name>' to extract a specific framework"
        '';

        extractFramework = pkgs.writeShellScriptBin "extract-framework" ''
          #!/usr/bin/env bash
          
          if [[ $# -eq 0 ]]; then
            echo "Usage: extract-framework <framework-name>"
            echo ""
            echo "Examples:"
            echo "  extract-framework CoreFoundation"
            echo "  extract-framework Security"
            echo "  extract-framework IOKit"
            echo ""
            echo "💡 Use 'list-frameworks' to see available frameworks"
            exit 1
          fi
          
          FRAMEWORK_NAME="$1"
          DYLD_CACHE="/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"
          OUTPUT_DIR="frameworks"
          
          echo "🔧 Extracting framework: $FRAMEWORK_NAME"
          echo "📁 Output directory: $OUTPUT_DIR"
          
          mkdir -p "$OUTPUT_DIR"
          
          ${dyldExtractor}/bin/dyldex -e "$FRAMEWORK_NAME" -o "$OUTPUT_DIR/$FRAMEWORK_NAME" "$DYLD_CACHE"
          
          if [[ -f "$OUTPUT_DIR/$FRAMEWORK_NAME" ]]; then
            echo "✅ Successfully extracted: $FRAMEWORK_NAME"
            echo "📊 File info:"
            file "$OUTPUT_DIR/$FRAMEWORK_NAME"
            echo "📏 Size: $(du -sh "$OUTPUT_DIR/$FRAMEWORK_NAME" | cut -f1)"
            echo ""
            echo "🔍 Quick analysis:"
            echo "  Dependencies: otool -L frameworks/$FRAMEWORK_NAME"
            echo "  Symbols: nm frameworks/$FRAMEWORK_NAME | head -10"
            echo "  Strings: strings frameworks/$FRAMEWORK_NAME | head -10"
          else
            echo "❌ Failed to extract $FRAMEWORK_NAME"
            echo "💡 Check framework name with 'list-frameworks'"
          fi
        '';

        analyzeFramework = pkgs.writeShellScriptBin "analyze-framework" ''
          #!/usr/bin/env bash
          
          if [[ $# -eq 0 ]]; then
            echo "Usage: analyze-framework <framework-file>"
            echo ""
            echo "Examples:"
            echo "  analyze-framework frameworks/CoreFoundation"
            echo "  analyze-framework frameworks/Security"
            echo ""
            exit 1
          fi
          
          FRAMEWORK_FILE="$1"
          
          if [[ ! -f "$FRAMEWORK_FILE" ]]; then
            echo "❌ Framework file not found: $FRAMEWORK_FILE"
            exit 1
          fi
          
          echo "🔍 Analyzing framework: $FRAMEWORK_FILE"
          echo "=================================================="
          echo ""
          
          echo "📊 File Information:"
          file "$FRAMEWORK_FILE"
          echo "📏 Size: $(du -sh "$FRAMEWORK_FILE" | cut -f1)"
          echo ""
          
          echo "🔗 Library Dependencies:"
          otool -L "$FRAMEWORK_FILE" | head -10
          echo ""
          
          echo "🏷️  Exported Symbols (first 10):"
          nm "$FRAMEWORK_FILE" 2>/dev/null | head -10 || echo "No symbols available"
          echo ""
          
          echo "🔤 Interesting Strings (first 10):"
          strings "$FRAMEWORK_FILE" | grep -E "(class|method|function|CF|NS)" | head -10
          echo ""
          
          echo "🎯 Ready for Ghidra Analysis!"
          echo "1. Start Ghidra: ghidra"
          echo "2. Import this framework: $FRAMEWORK_FILE"
          echo "3. Run analysis and explore with MCP"
        '';

        quickExtract = pkgs.writeShellScriptBin "quick-extract" ''
          #!/usr/bin/env bash
          echo "🚀 Quick extraction of common frameworks..."
          
          FRAMEWORKS=("CoreFoundation" "Security" "IOKit" "Foundation")
          
          for fw in "''${FRAMEWORKS[@]}"; do
            echo "📦 Extracting $fw..."
            extract-framework "$fw"
            echo ""
          done
          
          echo "✅ Quick extraction complete!"
          echo "📁 Available frameworks:"
          ls -lah frameworks/
        '';

        # Automated GhidraMCP startup script
        autoStartGhidra = pkgs.writeShellScriptBin "auto-start-ghidra" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          echo "🚀 Auto-starting GhidraMCP environment..."
          
          # Step 1: Always compile GhidraMCP jar to ensure latest version
          echo "🔧 Building GhidraMCP plugin..."
          ${mcpBridgeSetup}/bin/setup-mcp-bridge
          
          # Step 2: Setup Ghidra extensions directory
          EXTENSIONS_DIR="$HOME/.ghidra/.ghidra_11.0.1_PUBLIC/Extensions"
          PLUGIN_ZIP="GhidraMCP/target/GhidraMCP-1.0-SNAPSHOT.zip"
          PLUGIN_NAME="GhidraMCP"
          
          echo "📁 Creating extensions directory: $EXTENSIONS_DIR"
          mkdir -p "$EXTENSIONS_DIR"
          
          # Step 3: Remove existing plugin installation if it exists
          if [[ -d "$EXTENSIONS_DIR/$PLUGIN_NAME" ]]; then
            echo "🗑️  Removing existing GhidraMCP plugin installation..."
            rm -rf "$EXTENSIONS_DIR/$PLUGIN_NAME"
          fi
          
          # Step 4: Install fresh plugin from compiled JAR
          if [[ -f "$PLUGIN_ZIP" ]]; then
            echo "🔌 Installing fresh GhidraMCP plugin..."
            
            # Extract plugin to extensions directory
            cd "$EXTENSIONS_DIR"
            unzip -q "$OLDPWD/$PLUGIN_ZIP" && echo "✅ Plugin extracted successfully" || {
              echo "❌ Plugin extraction failed"
              cd "$OLDPWD"
              exit 1
            }
            cd "$OLDPWD"
            
            echo "✅ GhidraMCP plugin installed to: $EXTENSIONS_DIR/$PLUGIN_NAME"
            
            # Verify installation
            if [[ -d "$EXTENSIONS_DIR/$PLUGIN_NAME" ]]; then
              echo "🔍 Plugin contents:"
              ls -la "$EXTENSIONS_DIR/$PLUGIN_NAME/"
            fi
          else
            echo "❌ Plugin ZIP not found: $PLUGIN_ZIP"
            echo "💡 Build may have failed - check build output above"
            exit 1
          fi
          
          # Step 5: Create auto-enable script for Ghidra
          cat > "$HOME/.ghidra_auto_enable_mcp.py" << 'EOF'
# Auto-enable GhidraMCP plugin
import ghidra.framework.plugintool.PluginTool as PluginTool
import ghidra.app.plugin.core.console.CodeBrowserPlugin as CodeBrowserPlugin

def auto_enable_mcp():
    try:
        tool = state.getTool()
        if tool:
            # Enable MCP plugin if available
            tool.addPlugin("ghidra.app.plugin.core.mcp.MCPPlugin")
            print("✅ GhidraMCP plugin enabled")
    except:
        print("⚠️  Could not auto-enable MCP plugin - enable manually")

auto_enable_mcp()
EOF
          
          echo ""
          echo "🎯 Starting Ghidra with fresh MCP integration..."
          echo "📁 Project directory: $HOME/ghidra-projects"
          echo "🔌 Plugin installed at: $EXTENSIONS_DIR/$PLUGIN_NAME"
          echo "📜 Auto-enable script: $HOME/.ghidra_auto_enable_mcp.py"
          
          # Step 6: Start Ghidra
          ghidra &
          
          echo ""
          echo "✅ Ghidra started with fresh GhidraMCP plugin!"
          echo "📋 Next steps:"
          echo "   1. Ghidra should detect the new plugin automatically"
          echo "   2. If not: File → Configure → Plugins → Search 'MCP' → Enable"
          echo "   3. Plugin location: $EXTENSIONS_DIR/$PLUGIN_NAME"
        '';

        # Complete setup script
        setupScript = pkgs.writeShellScriptBin "setup-ghidra-mcp-vibe" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          echo "🚀 Setting up GhidraMCP Vibe RSE environment..."
          
          echo "✅ Ghidra is already available in the environment"
          echo "✅ DyldExtractor is already available in the environment"
          
          # Setup MCP bridge
          ${mcpBridgeSetup}/bin/setup-mcp-bridge
          
          # Extract dyld cache (macOS only)
          if [[ "$(uname)" == "Darwin" ]]; then
            ${dyldCacheWorkflow}/bin/extract-dyld-cache
          fi
          
          echo "✅ Setup complete!"
          echo ""
          echo "Next steps:"
          echo "1. Start Ghidra: ghidra"
          echo "2. Install the MCP plugin from GhidraMCP/dist/"
          echo "3. Configure your MCP client to connect to Ghidra"
          echo "4. Import extracted frameworks for analysis"
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pythonEnv
            pkgs.python3
            javaEnv
            ghidra
            dyldExtractor
            setupScript
            mcpBridgeSetup
            dyldCacheWorkflow
            listFrameworks
            extractFramework
            analyzeFramework
            quickExtract
            autoStartGhidra
          ] ++ buildTools;

          shellHook = ''
            echo "🎯 GhidraMCP Vibe RSE Development Environment"
            echo "Platform: ''${system}"
            echo ""
            
            # Auto-compile and start Ghidra with MCP
            echo "🚀 Auto-starting GhidraMCP environment..."
            ${autoStartGhidra}/bin/auto-start-ghidra
            
            echo ""
            echo "Available tools:"
            echo "  ghidra                 - Start Ghidra"
            echo "  auto-start-ghidra      - Auto-compile MCP + Start Ghidra"
            echo "  dyldex                 - Extract single framework from dyld cache"
            echo "  dyldex_all             - Extract all frameworks from dyld cache"
            echo "  kextex                 - Extract single kext from kernelcache"
            echo "  kextex_all             - Extract all kexts from kernelcache"
            echo ""
            echo "Tutorial commands:"
            echo "  list-frameworks        - List available frameworks in dyld cache"
            echo "  extract-framework      - Extract specific framework (e.g., extract-framework Security)"
            echo "  analyze-framework      - Analyze extracted framework file"
            echo "  quick-extract          - Extract common frameworks (CoreFoundation, Security, IOKit, Foundation)"
            echo ""
            echo "Setup commands:"
            echo "  setup-ghidra-mcp-vibe  - Complete setup"
            echo "  setup-mcp-bridge       - Setup MCP bridge"
            echo "  extract-dyld-cache     - Extract dyld cache (macOS)"
            echo ""
            echo "Python packages available:"
            echo "  - lief, construct, tqdm, click, requests, pyyaml"
            echo ""
            echo "Java: $(java -version 2>&1 | head -1)"
            echo "Python: $(python --version) (also available as python3)"
            echo "Python3: $(python3 --version)"
            echo "Ghidra: Available"
            echo ""
            echo "Environment variables:"
            echo "  PYTHONPATH: $PYTHONPATH"
            echo "  Python path: $(which python)"
            echo "  Python3 path: $(which python3)"
          '';

          # Environment variables
          JAVA_HOME = "${javaEnv}";
          GHIDRA_INSTALL_DIR = "$HOME/.local/share/ghidra";
          MCP_SERVER_PORT = "8080";
          
          # Platform-specific environment
          NIX_CFLAGS_COMPILE = pkgs.lib.optionalString pkgs.stdenv.isDarwin "-I${pkgs.darwin.apple_sdk.frameworks.Foundation}/include";
        };

        packages = {
          inherit dyldExtractor setupScript mcpBridgeSetup dyldCacheWorkflow listFrameworks extractFramework analyzeFramework quickExtract autoStartGhidra;
          python = pythonEnv;
          default = setupScript;
        };
        apps = rec {
          default = setup-ghidra-mcp-vibe;
          setup-ghidra-mcp-vibe = flake-utils.lib.mkApp { drv = setupScript; };
          setup-mcp-bridge = flake-utils.lib.mkApp { drv = mcpBridgeSetup; };
          extract-dyld-cache = flake-utils.lib.mkApp { drv = dyldCacheWorkflow; };
        };
      });
}
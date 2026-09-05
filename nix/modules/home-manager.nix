# Home-manager: install GhidraVibe + local stdio MCP binaries.
# Cursor uses mcpServers; Zed uses context_servers — same command/args payload
# as mcp-nixos / wwn-mcp. No public URL. No manual :8092 for vibe tools.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ghidra-vibe;
  system = pkgs.stdenv.hostPlatform.system;
  defaultPackage = self.packages.${system}.ghidra-vibe;
  defaultMcpPackage = self.packages.${system}.ghidra-vibe-mcp;
in
{
  imports = [ ./options.nix ];

  config = lib.mkMerge [
    {
      programs.ghidra-vibe.package = lib.mkDefault defaultPackage;
      programs.ghidra-vibe.mcpPackage = lib.mkDefault defaultMcpPackage;
      programs.ghidra-vibe.analysisPackage = lib.mkDefault self.packages.${system}.ghidra-vibe-analysis;
    }
    (lib.mkIf cfg.enable {
      home.packages =
        lib.optional cfg.installEngine cfg.package
        ++ lib.optional cfg.mcp.enable cfg.mcpPackage
        ++ lib.optional cfg.mcp.keepAnalysisAlive cfg.analysisPackage;

      home.sessionVariables = lib.mkMerge [
        (lib.mkIf (cfg.mcp.enable || cfg.mcp.keepAnalysisAlive) {
          GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
          GHIDRA_VIBE_ANALYSIS_ENSURE = "${cfg.analysisPackage}/bin/ghidra-vibe-analysis-ensure";
        })
        (lib.mkIf cfg.installEngine ({
        GHIDRA_INSTALL_DIR = "${cfg.package}/lib/ghidra";
        GHIDRA_VIBE_MCP_BRIDGE = "${cfg.package}/share/ghidra-mcp/bridge_mcp_ghidra.py";
        # Optional engine/GUI URLs when those daemons are already up. MCP hosts
        # do not need them: ghidra-mcp discovers via UDS; ghidra-vibe-mcp
        # auto-starts mcp-ext on an ephemeral localhost port.
        GHIDRA_VIBE_GUI_URL = cfg.mcp.guiControl;
        GHIDRA_VIBE_AI = if cfg.agent.enable then "1" else "0";
        GHIDRA_VIBE_AI_PROVIDER = cfg.agent.provider;
        GHIDRA_VIBE_AI_BASE_URL = cfg.agent.baseUrl;
        GHIDRA_VIBE_AI_MODEL = cfg.agent.model;
        GHIDRA_VIBE_AI_CLOUD_PROVIDER = cfg.agent.cloudProvider;
        GHIDRA_VIBE_AI_MOE = if cfg.agent.moe.enable then "1" else "0";
        GHIDRA_VIBE_AI_MOE_CLOUD = if cfg.agent.moe.allowCloudEscalation then "1" else "0";
      }
      // lib.optionalAttrs (cfg.agent.apiKeyFile != null) {
        GHIDRA_VIBE_API_KEY_FILE = toString cfg.agent.apiKeyFile;
      }
      // lib.optionalAttrs (cfg.agent.modelsDir != null) {
        GHIDRA_VIBE_AI_MODELS_DIR = cfg.agent.modelsDir;
      }
      // lib.optionalAttrs (cfg.agent.moe.codeModel != null) {
        GHIDRA_VIBE_AI_MODEL_CODE = cfg.agent.moe.codeModel;
      }
      // lib.optionalAttrs (cfg.agent.moe.decompileModel != null) {
        GHIDRA_VIBE_AI_MODEL_DECOMPILE = cfg.agent.moe.decompileModel;
      }
      // lib.optionalAttrs (cfg.agent.moe.appleModel != null) {
        GHIDRA_VIBE_AI_MODEL_APPLE = cfg.agent.moe.appleModel;
      }
      // lib.optionalAttrs (cfg.agent.moe.planModel != null) {
        GHIDRA_VIBE_AI_MODEL_PLAN = cfg.agent.moe.planModel;
      }))
      ];

      # Snippet for manual merge. Prefer IDE mcp.json via home-manager /
      # .dotfiles `_ide-mcp.nix` (lib.getExe of these bins).
      xdg.configFile."ghidra-vibe/cursor-mcp.json" = lib.mkIf cfg.mcp.enable {
        text = builtins.toJSON {
          mcpServers = {
            ghidra = {
              command = "${cfg.mcpPackage}/bin/ghidra-mcp";
              args = [ ];
              env = {
                GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
                GHIDRA_VIBE_ANALYSIS_ENSURE = "${cfg.analysisPackage}/bin/ghidra-vibe-analysis-ensure";
              };
            };
            ghidra-vibe = {
              command = "${cfg.mcpPackage}/bin/ghidra-vibe-mcp";
              args = [ ];
              env = {
                GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
                GHIDRA_INSTALL_DIR = "${cfg.package}/lib/ghidra";
                GHIDRA_VIBE_ANALYSIS_ENSURE = "${cfg.analysisPackage}/bin/ghidra-vibe-analysis-ensure";
              };
            };
            ghidra-vibe-rag = {
              command = "${cfg.mcpPackage}/bin/ghidra-vibe-rag-mcp";
              args = [ ];
            };
          };
        };
      };

      home.file."Library/Logs/GhidraVibe/.keep" = lib.mkIf (cfg.mcp.keepAnalysisAlive && pkgs.stdenv.isDarwin) {
        text = "";
      };

      launchd.agents.ghidra-vibe-analysis = lib.mkIf (cfg.mcp.keepAnalysisAlive && pkgs.stdenv.isDarwin) {
        enable = true;
        config = {
          Label = "dev.ghidravibe.analysis";
          ProgramArguments = [
            "${cfg.analysisPackage}/bin/ghidra-vibe-analysis-ensure"
            "--supervise"
          ];
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/GhidraVibe/analysis.launchd.out.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/GhidraVibe/analysis.launchd.err.log";
          EnvironmentVariables = {
            GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
            GHIDRA_INSTALL_DIR = "${cfg.package}/lib/ghidra";
          };
        };
      };
    })
  ];
}

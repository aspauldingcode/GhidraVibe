{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.ghidra-vibe;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.sessionVariables = {
      GHIDRA_INSTALL_DIR = "${cfg.package}/lib/ghidra";
      GHIDRA_VIBE_MCP_BRIDGE = "${cfg.package}/share/ghidra-mcp/bridge_mcp_ghidra.py";
      GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
      GHIDRA_VIBE_GUI_URL = cfg.mcp.guiControl;
      GHIDRA_VIBE_AI = if cfg.agent.enable then "1" else "0";
      GHIDRA_VIBE_AI_BASE_URL = cfg.agent.baseUrl;
      GHIDRA_VIBE_AI_MODEL = cfg.agent.model;
      GHIDRA_VIBE_AI_MOE = if cfg.agent.moe.enable then "1" else "0";
      GHIDRA_VIBE_AI_MOE_CLOUD = if cfg.agent.moe.allowCloudEscalation then "1" else "0";
    }
    // lib.optionalAttrs (cfg.agent.apiKeyFile != null) {
      GHIDRA_VIBE_API_KEY_FILE = toString cfg.agent.apiKeyFile;
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
    };

    xdg.configFile."ghidra-vibe/cursor-mcp.json".text = builtins.toJSON {
      mcpServers = {
        ghidra = {
          command = "python3";
          args = [ "${cfg.package}/share/ghidra-mcp/bridge_mcp_ghidra.py" ];
          env.GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
        };
        ghidra-vibe-gui = {
          command = "python3";
          args = [ "${cfg.package}/share/ghidra-mcp/bridge_mcp_gui.py" ];
          env.GHIDRA_VIBE_GUI_URL = cfg.mcp.guiControl;
        };
        ghidra-vibe-rag = {
          command = "${cfg.package}/bin/ghidra-vibe-rag-mcp";
          args = [ ];
          env = {
            GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
          };
        };
        ghidra-vibe = {
          command = "python3";
          args = [ "${cfg.package}/share/ghidra-mcp/bridge_mcp_vibe.py" ];
          env = {
            GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
            GHIDRA_VIBE_MCP_EXT_URL = "http://127.0.0.1:8092";
          };
        };
      };
    };
  };
}

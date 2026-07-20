{ lib, pkgs, ... }:

{
  options.programs.ghidra-vibe = {
    enable = lib.mkEnableOption "Vibe Ghidra (Ghidra + bundled MCP)";

    package = lib.mkOption {
      type = lib.types.package;
      description = "Vibe Ghidra package (Ghidra tree with GhidraMCP prebundled).";
    };

    mcp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose MCP bridge path / Cursor snippet helpers.";
      };
      ghidraServer = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8089";
        description = "Ghidra MCP plugin HTTP URL (GHIDRA_MCP_URL).";
      };
      guiControl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8091";
        description = "GhidraVibe GuiControlServer URL (GHIDRA_VIBE_GUI_URL).";
      };
    };

    agent = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show Agent chat sidebar by default (Welcome). Set false / GHIDRA_VIBE_AI=0 to opt out.";
      };
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:11434";
        description = ''
          OpenAI-compatible LLM base URL (Metal Ollama by default).
          Sets GHIDRA_VIBE_AI_BASE_URL (also honors AI_LOCAL_BASE_URL / OLLAMA_HOST).
        '';
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen2.5-coder:3b";
        description = ''
          Default chat model id. Sets GHIDRA_VIBE_AI_MODEL
          (also honors AI_LOCAL_DEFAULT_MODEL).
        '';
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Optional path to a file containing an API key for proprietary LLM opt-in.
          Never put the key string in Nix config. Default null = local Ollama only
          (Metal via OpenAI-compat). Sets GHIDRA_VIBE_API_KEY_FILE.
        '';
      };
      moe = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Mixture of Experts routing across local models (GHIDRA_VIBE_AI_MOE).";
        };
        allowCloudEscalation = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow proprietary API fallback when local fails (GHIDRA_VIBE_AI_MOE_CLOUD).";
        };
        codeModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Expert model for rename/symbols (GHIDRA_VIBE_AI_MODEL_CODE).";
        };
        decompileModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Expert model for improve_decompile (GHIDRA_VIBE_AI_MODEL_DECOMPILE).";
        };
        appleModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Expert model for ObjC/Swift (GHIDRA_VIBE_AI_MODEL_APPLE).";
        };
        planModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Expert model for Autonomous RE (GHIDRA_VIBE_AI_MODEL_PLAN).";
        };
      };
    };

    dyld = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = pkgs.stdenv.isDarwin;
        description = "Enable dyld shared cache helpers (macOS).";
      };
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "GhidraMCP" ];
      description = "Logical extension names (GhidraMCP is always in the package tree).";
    };
  };
}

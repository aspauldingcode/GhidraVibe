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
      # ollama | llamacpp | openai | anthropic | google | openai_compat
      provider = lib.mkOption {
        type = lib.types.str;
        default = "ollama";
        description = "Active Agent provider id (GHIDRA_VIBE_AI_PROVIDER).";
      };
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:11434";
        description = ''
          LLM base URL. Ollama default :11434; llama.cpp :8080; cloud provider defaults apply in GUI.
          Sets GHIDRA_VIBE_AI_BASE_URL.
        '';
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen2.5-coder:3b";
        description = "Default chat model id (GHIDRA_VIBE_AI_MODEL).";
      };
      modelsDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Directory for user-dropped GGUF / .ccp weights (never populated by Nix).
          Sets GHIDRA_VIBE_AI_MODELS_DIR. Default: ~/Library/Application Support/GhidraVibe/models
        '';
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing an API key for proprietary providers.
          Never put the key string in Nix config. Sets GHIDRA_VIBE_API_KEY_FILE.
        '';
      };
      cloudProvider = lib.mkOption {
        type = lib.types.str;
        default = "openai";
        description = "Provider used for MoE cloud escalation (GHIDRA_VIBE_AI_CLOUD_PROVIDER).";
      };
      ollama = {
        ensureModels = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = (import ../agent/models.nix).ollamaEnsureModels;
          description = ''
            Declarative Ollama tags for testing (pulled by ghidra-vibe-agent-ensure-models).
            Does not store weights in the Nix store.
          '';
        };
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
          default = (import ../agent/models.nix).moe.code;
          description = "Expert model for rename/symbols (GHIDRA_VIBE_AI_MODEL_CODE).";
        };
        decompileModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = (import ../agent/models.nix).moe.decompile;
          description = "Expert model for improve_decompile (GHIDRA_VIBE_AI_MODEL_DECOMPILE).";
        };
        appleModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = (import ../agent/models.nix).moe.apple;
          description = "Expert model for ObjC/Swift (GHIDRA_VIBE_AI_MODEL_APPLE).";
        };
        planModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = (import ../agent/models.nix).moe.plan;
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

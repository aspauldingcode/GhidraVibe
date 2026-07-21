# Declarative Agent model *names* for testing — never store LLM weights in the flake.
# Matches models currently available via Ollama on the development machine (2026-07).
# Pull with: nix run .#ghidra-vibe-agent-ensure-models
#
# Weights stay in the user's Ollama store / GHIDRA_VIBE_AI_MODELS_DIR (GGUF drops).
{
  # Default local chat tag (Metal Ollama).
  defaultModel = "qwen2.5-coder:3b";

  # Ollama tags to ensure for MoE / Agent Setup pickers.
  ollamaEnsureModels = [
    "qwen2.5-coder:1.5b"
    "qwen2.5-coder:3b"
    "qwen2.5-coder:7b"
    "llama3.2:1b"
    "llama3.2:3b"
    "gemma3:1b"
    "gemma3:4b"
  ];

  # MoE expert defaults (local tags only).
  moe = {
    code = "qwen2.5-coder:7b";
    decompile = "qwen2.5-coder:7b";
    apple = "qwen2.5-coder:3b";
    plan = "qwen2.5-coder:3b";
    general = "llama3.2:3b";
  };

  # Proprietary defaults (keys via apiKeyFile — never in-store).
  providers = {
    openai.model = "gpt-4o-mini";
    anthropic.model = "claude-sonnet-4-20250514";
    google.model = "gemini-2.0-flash";
  };
}

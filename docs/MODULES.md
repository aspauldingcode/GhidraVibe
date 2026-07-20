# Nix modules

Exports: `nixosModules.default`, `darwinModules.default`, `homeModules.default`.

```nix
{
  imports = [ inputs.ghidra-vibe.darwinModules.default ]; # or nixos / homeModules
  programs.ghidra-vibe = {
    enable = true;
    package = inputs.ghidra-vibe.packages.${pkgs.system}.ghidra-vibe;
    mcp.ghidraServer = "http://127.0.0.1:8089";
    mcp.guiControl = "http://127.0.0.1:8091";
    agent.enable = true;
    # Opt-in cloud API only — path to a key file, never a raw key string:
    # agent.apiKeyFile = "/run/agenix/openai_api_key";
  };
}
```

Launch the UI with `nix run` from this flake.

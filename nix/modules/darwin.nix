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
    environment.systemPackages = [ cfg.package ];
    environment.variables = {
      GHIDRA_INSTALL_DIR = "${cfg.package}/lib/ghidra";
      GHIDRA_VIBE_MCP_BRIDGE = "${cfg.package}/share/ghidra-mcp/bridge_mcp_ghidra.py";
      GHIDRA_MCP_URL = cfg.mcp.ghidraServer;
    };
  };
}

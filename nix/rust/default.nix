{
  lib,
  rustPlatform,
  pkg-config,
}:

rustPlatform.buildRustPackage {
  pname = "ghidra-vibe-tools";
  version = "0.1.0";
  src = ../../rust;

  cargoLock.lockFile = ../../rust/Cargo.lock;

  nativeBuildInputs = [ pkg-config ];

  # rusqlite bundled feature — no system sqlite required
  doCheck = false;

  meta = with lib; {
    description = "JSpace RAG, DSC index, and RAG MCP bridge for GhidraVibe";
    license = licenses.asl20;
    mainProgram = "ghidra-vibe-jspace";
  };
}

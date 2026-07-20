{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ghidra-mcp-extension";
  version = "5.14.2";

  src = fetchurl {
    url = "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/GhidraMCP-${version}.zip";
    hash = "sha256-LDPNUlT4+kqOfHQj29ZDOEJoD5p2vBWyl7DfcV8iml0=";
  };

  bridge = fetchurl {
    url = "https://github.com/bethington/ghidra-mcp/releases/download/v${version}/bridge_mcp_ghidra.py";
    hash = "sha256-ktmnkNFIxJ0KiJ21DnNhoQ1ASN+Y83ITYsvWa5dCdVw=";
  };

  nativeBuildInputs = [ unzip ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/ghidra-extensions" "$out/share/ghidra-mcp"
    unzip -q "$src" -d "$out/share/ghidra-extensions"
    # Normalize version metadata for Ghidra 12.1.2 installs.
    props="$out/share/ghidra-extensions/GhidraMCP/extension.properties"
    if [[ -f "$props" ]]; then
      tmp="$props.tmp"
      sed \
        -e 's/^version=.*/version=12.1.2/' \
        -e 's/^ghidraVersion=.*/ghidraVersion=12.1.2/' \
        "$props" > "$tmp"
      mv "$tmp" "$props"
    fi
    cp "$bridge" "$out/share/ghidra-mcp/bridge_mcp_ghidra.py"
    runHook postInstall
  '';

  meta = with lib; {
    description = "bethington GhidraMCP extension + Python bridge (prebundled)";
    homepage = "https://github.com/bethington/ghidra-mcp";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}

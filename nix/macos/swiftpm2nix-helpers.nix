# swiftpm2nix.helpers, extended for SwiftPM workspace-state v7 (Swift 6.2).
# Keeps the package's Package.resolved (v3) instead of synthesizing the legacy v1 pin file.
{
  lib,
  fetchgit,
}:
let
  inherit (lib)
    concatStrings
    listToAttrs
    mapAttrsToList
    nameValuePair
    ;
in
{
  helpers =
    generated:
    let
      inherit (import generated) workspaceStateFile hashes;
      workspaceState = lib.importJSON workspaceStateFile;
      sources = listToAttrs (
        map (
          dep:
          nameValuePair dep.subpath (fetchgit {
            url = dep.packageRef.location;
            rev = dep.state.checkoutState.revision;
            hash = hashes.${dep.subpath};
            fetchSubmodules = true;
          })
        ) workspaceState.object.dependencies
      );
    in
    {
      inherit sources;
      configure = ''
        mkdir -p .build/checkouts
        install -m 0600 ${workspaceStateFile} ./.build/workspace-state.json
      ''
      + concatStrings (
        mapAttrsToList (name: src: ''
          ln -s '${src}' '.build/checkouts/${name}'
        '') sources
      )
      + ''
        swiftpmMakeMutable() {
          local orig="$(readlink .build/checkouts/$1)"
          rm .build/checkouts/$1
          cp -r "$orig" .build/checkouts/$1
          chmod -R u+w .build/checkouts/$1
        }
      '';
    };
}

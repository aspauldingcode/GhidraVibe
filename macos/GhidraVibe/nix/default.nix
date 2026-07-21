# Generated from `swift package resolve` + nurl (swiftpm2nix-compatible).
# Upstream swiftpm2nix only accepts workspace-state v5–6; Swift 6.2 emits v7.
# Regenerate hashes with:
#   nix-shell -p jq nurl --run '
#     jq -r ".object.dependencies[] | \"\(.subpath) \(.packageRef.location) \(.state.checkoutState.revision)\"" \
#       .build/workspace-state.json | while read n u r; do
#       echo "\"$n\" = \"$(nurl \"$u\" \"$r\" --json --submodules=true --fetcher=fetchgit | jq -r .args.hash)\";"
#     done'
{
  workspaceStateFile = ./workspace-state.json;
  hashes = {
    "swift-concurrency-extras" = "sha256-ENDLqc8lLGZQ6YjCvVYU4mroXxhVT/fIAxNbWh4FB70=";
    "swiftui-math" = "sha256-pXn6IyAGTLr7S3jnknKGbGqFGASiqo7tMiVkkii/C+M=";
    "textual" = "sha256-U3vbOKsXvLxKwR8NAlYT/cN7vxKlExqPk9MVPXjX6PY=";
    "TintedThemingSwift" = "sha256-JlCjL66xNGIwpPV5Giv++44tkNClssomBAJRAr78fdc=";
    "Yams" = "sha256-5uxD2eAJpMVHMStfWUzHcgjlp0d/EYcr1l+Qq2xlMxU=";
  };
}

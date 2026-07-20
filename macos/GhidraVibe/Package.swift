// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GhidraVibe",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "GhidraVibe", targets: ["GhidraVibe"])
    ],
    targets: [
        .executableTarget(
            name: "GhidraVibe",
            path: "Sources/GhidraVibe",
            // JSON catalogs are copied into Contents/Resources by package-app.sh /
            // nix packaging. Do not use SPM `resources:` + Bundle.module — that
            // traps when the .app only contains the Mach-O (nix run / open -n).
            exclude: ["Resources"]
        )
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vocume",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Vocume", targets: ["Vocume"])
    ],
    targets: [
        // Pure annotation logic: mark model, geometry, rendering, OCR matching, AI prompt/reply.
        .target(
            name: "VocumeCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The menu-bar app: windows, editor UI, screenshot watching, Claude/Codex processes.
        .executableTarget(
            name: "Vocume",
            dependencies: ["VocumeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VocumeCoreTests",
            dependencies: ["VocumeCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

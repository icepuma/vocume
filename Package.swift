// swift-tools-version: 6.0
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
            // Swift 5 mode until the AppKit/process glue is migrated to strict concurrency.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VocumeCoreTests",
            dependencies: ["VocumeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

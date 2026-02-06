// swift-tools-version: 6.0
// This Package.swift enables `swift build` verification when Xcode.app is unavailable.
// The primary build system is the Xcode project (Pastel.xcodeproj).

import PackageDescription

let package = Package(
    name: "Pastel",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // KeyboardShortcuts and LaunchAtLogin are in Pastel.xcodeproj for Phase 3/5.
        // Excluded from Package.swift because #Preview macros in KeyboardShortcuts
        // require full Xcode.app (fails with Command Line Tools only).
    ],
    targets: [
        .executableTarget(
            name: "Pastel",
            dependencies: [],
            path: "Pastel",
            exclude: ["Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

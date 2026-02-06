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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pastel",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "Pastel",
            exclude: ["Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

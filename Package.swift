// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BwocMcc",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure, UI-free logic (models + CLI shell-out + parsing) — unit tested.
        .target(
            name: "BwocMccCore",
            path: "Sources/BwocMccCore"
        ),
        // The SwiftUI menu-bar app.
        // The desktop-mascot sprite atlas under Sources/BwocMcc/Resources is NOT
        // declared as a SwiftPM resource: that produces a flat `*.bundle` dir that
        // `codesign` rejects as malformed when packaging the .app. Instead the
        // packaging scripts copy mascot_sheet.png into Contents/Resources, and
        // MascotSprite locates it via Bundle.main (or a dev-path fallback).
        .executableTarget(
            name: "BwocMcc",
            dependencies: ["BwocMccCore"],
            path: "Sources/BwocMcc",
            exclude: ["Resources"]   // shipped via the packaging scripts, not SwiftPM
        ),
        // Dependency-free, runnable checks. This machine has Command Line Tools
        // only (no XCTest), so tests are a plain executable: `swift run CoreChecks`.
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["BwocMccCore"],
            path: "Tests/CoreChecks"
        )
    ]
)

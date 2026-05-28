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
        .executableTarget(
            name: "BwocMcc",
            dependencies: ["BwocMccCore"],
            path: "Sources/BwocMcc"
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

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FinderTweaks",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared plumbing: Accessibility, tracking the focused Finder window, Finder scripting/prefs, paths.
        .target(name: "FinderTweaksCore"),
        // The menu bar app and its features (Sources/FinderTweaks/Features/*).
        .executableTarget(name: "FinderTweaks", dependencies: ["FinderTweaksCore"]),
        .testTarget(name: "FinderTweaksCoreTests", dependencies: ["FinderTweaksCore"]),
    ],
    swiftLanguageModes: [.v5]
)

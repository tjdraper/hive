// swift-tools-version: 6.2

import PackageDescription

// The same concurrency behavior as the app targets' SWIFT_APPROACHABLE_CONCURRENCY and member import visibility.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let swiftLint: Target.PluginUsage = .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")

let package = Package(
    name: "HiveCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HiveCore", targets: ["HiveCore"]),
    ],
    dependencies: [
        .package(path: "../HiveKit"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.2"),
    ],
    targets: [
        .target(
            name: "HiveCore",
            dependencies: ["HiveKit"],
            swiftSettings: swiftSettings,
            plugins: [swiftLint]
        ),
        .testTarget(
            name: "HiveCoreTests",
            dependencies: ["HiveCore"],
            swiftSettings: swiftSettings,
            plugins: [swiftLint]
        ),
    ]
)

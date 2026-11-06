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
    name: "HiveKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "HiveKit", targets: ["HiveKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.2"),
        .package(url: "https://github.com/apple/swift-asn1", from: "1.7.4"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.21.1"),
    ],
    targets: [
        .target(name: "HiveKit", swiftSettings: swiftSettings, plugins: [swiftLint]),
        .testTarget(
            name: "HiveKitTests",
            dependencies: [
                "HiveKit",
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: swiftSettings,
            plugins: [swiftLint]
        ),
    ]
)

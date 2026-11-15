// swift-tools-version: 6.2

import PackageDescription

// The same concurrency behavior as the other packages. `Scripts/build-and-test.sh` sets
// SCOUT_WARNINGS_AS_ERRORS, so a warning can't pass once its file is cached by an incremental build;
// it applies only to Scout's own targets, since SwiftPM compiles dependencies with warnings suppressed.
var swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
if Context.environment["SCOUT_WARNINGS_AS_ERRORS"] != nil {
    swiftSettings.append(.treatAllWarnings(as: .error))
}

// SwiftLint's plugin ships a macOS binary only. Its warnings show only when SwiftPM reruns it, so
// `Scripts/build-and-test.sh` also runs SwiftLint on Scout itself.
var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto", from: "5.1.1"),
    .package(url: "https://github.com/apple/swift-nio", from: "2.105.0"),
    .package(url: "https://github.com/apple/swift-nio-ssl", from: "2.37.6"),
]
var plugins: [Target.PluginUsage] = []
#if os(macOS)
dependencies.append(.package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.2"))
plugins.append(.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"))
#endif

let package = Package(
    name: "Scout",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScoutProtocol", targets: ["ScoutProtocol"]),
        .executable(name: "hive-scout", targets: ["hive-scout"]),
    ],
    dependencies: dependencies,
    targets: [
        .target(name: "ScoutProtocol", swiftSettings: swiftSettings, plugins: plugins),
        .target(
            name: "ScoutCore",
            dependencies: [
                "ScoutProtocol",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .executableTarget(
            name: "hive-scout",
            dependencies: ["ScoutCore", "ScoutProtocol"],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .testTarget(
            name: "ScoutCoreTests",
            dependencies: [
                "ScoutCore",
                "ScoutProtocol",
                "hive-scout",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
            ],
            exclude: ["Captured"],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
    ]
)

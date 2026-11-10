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
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.28.1"),
        .package(url: "https://github.com/apple/swift-asn1", from: "1.7.4"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.21.1"),
        .package(url: "https://github.com/apple/swift-log", from: "1.17.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.105.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl", from: "2.37.6"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.13.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.2"),
    ],
    targets: [
        .target(
            name: "HiveCore",
            dependencies: [
                "HiveKit",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTLS", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "UnixSignals", package: "swift-service-lifecycle"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: swiftSettings,
            plugins: [swiftLint]
        ),
        .testTarget(
            name: "HiveCoreTests",
            dependencies: [
                "HiveCore",
                "HiveKit",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: swiftSettings,
            plugins: [swiftLint]
        ),
    ]
)

// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "C2PA",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        // Main library for consumers
        .library(
            name: "C2PA",
            targets: ["C2PA", "C2PAC"]
        )
    ],
    dependencies: [
        // External dependencies
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        // Main library target
        .target(
            name: "C2PA",
            dependencies: [
                "C2PAC",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/C2PA",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // Binary XCFramework target
        .binaryTarget(
            name: "C2PAC",
            path: "output/C2PAC.xcframework"
        ),
        
        // Unit tests
        .testTarget(
            name: "C2PATests",
            dependencies: [
                "C2PA"
            ],
            path: "Tests/C2PATests",
            resources: [
                .copy("Resources")
            ]
        ),
        
        // Integration tests
        .testTarget(
            name: "C2PAIntegrationTests",
            dependencies: [
                "C2PA"
            ],
            path: "Tests/C2PAIntegrationTests"
        ),
        
        // Performance tests
        .testTarget(
            name: "C2PAPerformanceTests",
            dependencies: [
                "C2PA"
            ],
            path: "Tests/C2PAPerformanceTests"
        )
    ]
)

// MARK: - Platform-specific configurations
#if os(iOS)
package.targets.first(where: { $0.name == "C2PA" })?.swiftSettings?.append(
    .define("IOS_SPECIFIC")
)
#endif
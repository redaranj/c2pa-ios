// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Determine whether to use local or remote binary
let useLocalBinary: Bool = {
    // Check for environment variable
    if ProcessInfo.processInfo.environment["USE_LOCAL_BINARY"] == "1" {
        return true
    }
    // Check if local XCFramework exists
    let localFrameworkPath = "Frameworks/C2PAC.xcframework"
    return FileManager.default.fileExists(atPath: localFrameworkPath)
}()

// Configure the C2PAC binary target based on availability
let c2pacTarget: Target = {
    if useLocalBinary {
        // Use local XCFramework built by our scripts
        return .binaryTarget(
            name: "C2PAC",
            path: "Frameworks/C2PAC.xcframework"
        )
    } else {
        // For now, use the local path since we don't have a remote URL yet
        // TODO: Update with actual remote URL and checksum when publishing
        return .binaryTarget(
            name: "C2PAC",
            path: "Frameworks/C2PAC.xcframework"
        )
        // Future remote configuration:
        // return .binaryTarget(
        //     name: "C2PAC",
        //     url: "https://github.com/contentauth/c2pa-ios/releases/download/v0.58.0/C2PAC.xcframework.zip",
        //     checksum: "CHECKSUM_HERE"
        // )
    }
}()

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
        // C2PAC binary framework
        c2pacTarget,
        
        // Main library target
        .target(
            name: "C2PA",
            dependencies: [
                "C2PAC",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // Unit tests
        .testTarget(
            name: "C2PATests",
            dependencies: [
                "C2PA"
            ],
            path: "Tests",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)

// MARK: - Platform-specific configurations
#if os(iOS)
package.targets.first(where: { $0.name == "C2PA" })?.swiftSettings?.append(
    .define("IOS_SPECIFIC")
)
#endif
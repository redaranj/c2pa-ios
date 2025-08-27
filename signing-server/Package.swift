// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "C2PASigningServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Run", targets: ["Run"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [
                .target(name: "App")
            ]
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
                .target(name: "C2PA"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Llibs", "-lc2pa_c"])
            ]
        ),
        .target(
            name: "C2PA",
            dependencies: [
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
                "C2PAC",
            ],
            path: "Sources/C2PA",
            exclude: ["include"]
        ),
        .systemLibrary(
            name: "C2PAC",
            path: "Sources/C2PA",
            pkgConfig: nil,
            providers: []
        ),
    ]
)

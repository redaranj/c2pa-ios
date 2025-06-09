// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "C2PA",
    platforms: [
        .iOS(.v15),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "C2PA",
            targets: ["C2PA"]),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "C2PAC",
            url: "https://github.com/redaranj/c2pa-mobile/releases/download/v0.0.10/C2PAC.xcframework.zip",
            checksum: "3a8504ab2cd2c75219b4b63b81846f9aedda182d8c52d6031d3e667fa3e4fb6c"
        ),
        .target(
            name: "C2PA",
            dependencies: ["C2PAC"],
            path: "apple/src/C2PA"
        ),
    ]
)

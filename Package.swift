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
            url: "https://github.com/contentauth/c2pa-ios/releases/download/v0.0.1/C2PAC.xcframework.zip",
            checksum: "0beb730e8aeb652f4fca7da8a3b490c163133f58975825fe03f87a15f493cbcf"
        ),
        .target(
            name: "C2PA",
            dependencies: ["C2PAC"],
            path: "src"
        ),
    ]
)

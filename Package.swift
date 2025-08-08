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
            checksum: "28bd8aae763d4f6ada07c309ace588632ab38cd0f74838384193339309993575"
        ),
        .target(
            name: "C2PA",
            dependencies: ["C2PAC"],
            path: "src"
        ),
    ]
)

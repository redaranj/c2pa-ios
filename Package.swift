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
            url: "https://github.com/redaranj/c2pa-ios/releases/download/v0.0.2/C2PAC.xcframework.zip",
            checksum: "c9e2b8f829a6c112d9ea2cb327834594fab65b06fc494011a4fd7bf8646533b4"
        ),
        .target(
            name: "C2PA",
            dependencies: ["C2PAC"],
            path: "src"
        ),
    ]
)

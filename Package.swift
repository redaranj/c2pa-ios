// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "C2PA",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "C2PAC",
            targets: ["C2PAC"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "C2PAC",
            path: "Library/Frameworks/C2PAC.xcframework"
        )
    ]
)

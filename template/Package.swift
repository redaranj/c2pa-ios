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
            path: "Frameworks/C2PAC.xcframework"
        ),
        .target(
            name: "C2PA",
            dependencies: ["C2PAC"],
            path: "Sources/C2PA"
        ),
    ]
)

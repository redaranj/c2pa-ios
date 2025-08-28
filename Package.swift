// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "C2PA",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "C2PA",
            targets: ["C2PA", "C2PAC"])
    ],
    dependencies: [],
    targets: [
        // The C2PA Swift framework built by Xcode
        .binaryTarget(
            name: "C2PA",
            path: "output/C2PA.xcframework"
        ),
        // The C2PAC C library framework
        .binaryTarget(
            name: "C2PAC",
            path: "Library/Frameworks/C2PAC.xcframework"
        ),
    ]
)

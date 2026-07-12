// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spm-cache-proxy",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "spm-cache-proxy",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Rainbow", package: "Rainbow"),
            ],
            path: "Sources"
        ),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FixtureKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "FixtureKit", type: .dynamic, targets: ["FixtureKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.1")
    ],
    targets: [
        .target(
            name: "FixtureKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        )
    ]
)

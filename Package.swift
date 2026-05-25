// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aspace",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DisplayKit", targets: ["DisplayKit"]),
        .executable(name: "aspace", targets: ["AspaceCLI"]),
        .executable(name: "AspaceApp", targets: ["AspaceApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.10.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "DisplayKit",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ColorSync"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "AspaceCLI",
            dependencies: [
                "DisplayKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "AspaceApp",
            dependencies: [
                "DisplayKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "DisplayKitTests",
            dependencies: [
                "DisplayKit",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "aspace",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DisplayKit", targets: ["DisplayKit"]),
        .executable(name: "aspace", targets: ["AspaceCLI"]),
        .executable(name: "AspaceApp", targets: ["AspaceApp"]),
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
        .executableTarget(name: "AspaceCLI", dependencies: ["DisplayKit"]),
        .executableTarget(name: "AspaceApp", dependencies: ["DisplayKit"]),
    ]
)

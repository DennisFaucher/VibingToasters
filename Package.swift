// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlyingToasters",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlyingToasters", targets: ["FlyingToasters"]),
        // Built as a dylib so Tools/make-saver.sh can drop it into a .saver bundle.
        .library(name: "FlyingToastersSaver", type: .dynamic, targets: ["FlyingToastersSaver"])
    ],
    targets: [
        // Shared renderer, physics, shader source and baked sprite frames.
        .target(
            name: "FlyingToastersKit",
            path: "Sources/FlyingToastersKit"
        ),
        .executableTarget(
            name: "FlyingToasters",
            dependencies: ["FlyingToastersKit"],
            path: "Sources/FlyingToasters"
        ),
        .target(
            name: "FlyingToastersSaver",
            dependencies: ["FlyingToastersKit"],
            path: "Sources/FlyingToastersSaver",
            linkerSettings: [.linkedFramework("ScreenSaver")]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BufferMenubar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BufferMenubar", targets: ["BufferMenubar"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BufferMenubar",
            dependencies: [],
            path: "Sources"
        )
    ]
)

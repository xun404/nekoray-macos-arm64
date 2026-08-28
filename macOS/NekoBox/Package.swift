// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NekoBoxNative",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NekoBox", targets: ["NekoBox"])
    ],
    targets: [
        .executableTarget(
            name: "NekoBox",
            path: "Sources/NekoBox"
        )
    ]
)

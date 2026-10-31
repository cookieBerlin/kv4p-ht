// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KV4P",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "KV4PProtocol", targets: ["KV4PProtocol"]),
        .library(name: "KV4PSimulator", targets: ["KV4PSimulator"]),
    ],
    targets: [
        .target(
            name: "KV4PProtocol",
            path: "Packages/KV4PProtocol/Sources/KV4PProtocol"
        ),
        .testTarget(
            name: "KV4PProtocolTests",
            dependencies: ["KV4PProtocol"],
            path: "Packages/KV4PProtocol/Tests/KV4PProtocolTests",
            resources: [.copy("Vectors")]
        ),
        .target(
            name: "KV4PSimulator",
            dependencies: ["KV4PProtocol"],
            path: "Packages/KV4PSimulator/Sources/KV4PSimulator"
        ),
        .testTarget(
            name: "KV4PSimulatorTests",
            dependencies: ["KV4PSimulator"],
            path: "Packages/KV4PSimulator/Tests/KV4PSimulatorTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

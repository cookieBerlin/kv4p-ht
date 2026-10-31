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
        .library(name: "KV4PTransport", targets: ["KV4PTransport"]),
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
            name: "KV4PTransport",
            dependencies: ["KV4PProtocol"],
            path: "Packages/KV4PTransport/Sources/KV4PTransport"
        ),
        .testTarget(
            name: "KV4PTransportTests",
            dependencies: ["KV4PTransport", "KV4PTestSupport"],
            path: "Packages/KV4PTransport/Tests/KV4PTransportTests"
        ),
        .target(
            name: "KV4PSimulator",
            dependencies: ["KV4PProtocol", "KV4PTransport"],
            path: "Packages/KV4PSimulator/Sources/KV4PSimulator"
        ),
        .testTarget(
            name: "KV4PSimulatorTests",
            dependencies: ["KV4PSimulator", "KV4PTestSupport"],
            path: "Packages/KV4PSimulator/Tests/KV4PSimulatorTests"
        ),
        // Test doubles shared by the test targets (manual clock); not part of any product.
        .target(
            name: "KV4PTestSupport",
            path: "Packages/KV4PTestSupport/Sources/KV4PTestSupport"
        ),
        .testTarget(
            name: "KV4PTestSupportTests",
            dependencies: ["KV4PTestSupport"],
            path: "Packages/KV4PTestSupport/Tests/KV4PTestSupportTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

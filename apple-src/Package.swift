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
        .library(name: "KV4PRadio", targets: ["KV4PRadio"]),
        .library(name: "KV4PAudio", targets: ["KV4PAudio"]),
    ],
    targets: [
        .target(
            name: "KV4PProtocol",
            path: "Packages/KV4PProtocol/Sources/KV4PProtocol"
        ),
        .testTarget(
            name: "KV4PProtocolTests",
            dependencies: ["KV4PProtocol", "KV4PTestSupport"],
            path: "Packages/KV4PProtocol/Tests/KV4PProtocolTests",
            resources: [.copy("Vectors")]
        ),
        .target(
            name: "KV4PAudio",
            dependencies: ["KV4PProtocol"],
            path: "Packages/KV4PAudio/Sources/KV4PAudio"
        ),
        .testTarget(
            name: "KV4PAudioTests",
            dependencies: ["KV4PAudio", "KV4PTestSupport"],
            path: "Packages/KV4PAudio/Tests/KV4PAudioTests",
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
            dependencies: ["KV4PProtocol", "KV4PTransport", "KV4PAudio"],
            path: "Packages/KV4PSimulator/Sources/KV4PSimulator"
        ),
        .testTarget(
            name: "KV4PSimulatorTests",
            dependencies: ["KV4PSimulator", "KV4PAudio", "KV4PTestSupport"],
            path: "Packages/KV4PSimulator/Tests/KV4PSimulatorTests"
        ),
        .target(
            name: "KV4PRadio",
            dependencies: ["KV4PProtocol", "KV4PTransport", "KV4PAudio"],
            path: "Packages/KV4PRadio/Sources/KV4PRadio"
        ),
        .testTarget(
            name: "KV4PRadioTests",
            dependencies: ["KV4PRadio", "KV4PAudio", "KV4PSimulator", "KV4PTestSupport"],
            path: "Packages/KV4PRadio/Tests/KV4PRadioTests",
            resources: [.copy("Vectors")]
        ),
        // Development tool for the hardware checklist (macOS).
        .executableTarget(
            name: "kv4p-probe",
            dependencies: ["KV4PProtocol", "KV4PRadio", "KV4PTransport"],
            path: "Packages/KV4PProbe/Sources/kv4p-probe"
        ),
        // Simulated kv4p HT over real BLE (macOS), ADR-0014 B.
        .executableTarget(
            name: "kv4p-sim-peripheral",
            dependencies: ["KV4PSimulator"],
            path: "Packages/KV4PSimulatorPeripheral/Sources/kv4p-sim-peripheral"
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

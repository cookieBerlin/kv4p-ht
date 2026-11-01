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
        .library(name: "KV4PPersistence", targets: ["KV4PPersistence"]),
        .library(name: "KV4PAPRS", targets: ["KV4PAPRS"]),
        .library(name: "KV4PDigital", targets: ["KV4PDigital"]),
        .library(name: "KV4PFlasher", targets: ["KV4PFlasher"]),
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
            name: "KV4PPersistence",
            path: "Packages/KV4PPersistence/Sources/KV4PPersistence"
        ),
        .testTarget(
            name: "KV4PPersistenceTests",
            dependencies: ["KV4PPersistence"],
            path: "Packages/KV4PPersistence/Tests/KV4PPersistenceTests"
        ),
        .target(
            name: "KV4PAPRS",
            path: "Packages/KV4PAPRS/Sources/KV4PAPRS"
        ),
        .testTarget(
            name: "KV4PAPRSTests",
            dependencies: ["KV4PAPRS", "KV4PTestSupport"],
            path: "Packages/KV4PAPRS/Tests/KV4PAPRSTests",
            resources: [.copy("Vectors")]
        ),
        // Codec2 1.2.0, vendored unmodified by tools/codec2-vectors (ADR-0027); only the 1300 mode is compiled.
        .target(
            name: "CCodec2",
            path: "Packages/KV4PDigital/Sources/CCodec2",
            cSettings: [
                .define("CODEC2_MODE_EN_DEFAULT", to: "0"),
                .define("CODEC2_MODE_1300_EN", to: "1"),
                // Third-party code stays unmodified, so its warnings are not ours to fix.
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "KV4PDigital",
            dependencies: ["CCodec2", "KV4PAudio"],
            path: "Packages/KV4PDigital/Sources/KV4PDigital"
        ),
        .testTarget(
            name: "KV4PDigitalTests",
            dependencies: ["KV4PDigital", "CCodec2", "KV4PAudio", "KV4PSimulator", "KV4PTestSupport"],
            path: "Packages/KV4PDigital/Tests/KV4PDigitalTests",
            resources: [.copy("Vectors")]
        ),
        // ESP32 ROM bootloader flashing like esp32-flash-lib (ADR-0009, ADR-0028).
        .target(
            name: "KV4PFlasher",
            dependencies: ["KV4PProtocol", "KV4PTransport"],
            path: "Packages/KV4PFlasher/Sources/KV4PFlasher"
        ),
        .testTarget(
            name: "KV4PFlasherTests",
            dependencies: ["KV4PFlasher", "KV4PProtocol", "KV4PTransport", "KV4PTestSupport"],
            path: "Packages/KV4PFlasher/Tests/KV4PFlasherTests",
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
            dependencies: [
                "KV4PProtocol", "KV4PTransport", "KV4PAudio", "KV4PPersistence", "KV4PAPRS", "KV4PDigital",
                "KV4PFlasher",
            ],
            path: "Packages/KV4PRadio/Sources/KV4PRadio"
        ),
        .testTarget(
            name: "KV4PRadioTests",
            dependencies: [
                "KV4PRadio", "KV4PAudio", "KV4PPersistence", "KV4PAPRS", "KV4PDigital", "KV4PFlasher",
                "KV4PSimulator", "KV4PTestSupport",
            ],
            path: "Packages/KV4PRadio/Tests/KV4PRadioTests",
            resources: [.copy("Vectors")]
        ),
        // Development tool for the hardware checklist (macOS).
        .executableTarget(
            name: "kv4p-probe",
            dependencies: ["KV4PProtocol", "KV4PRadio", "KV4PTransport", "KV4PAudio", "KV4PAPRS", "KV4PFlasher"],
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
            dependencies: ["KV4PTransport"],
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

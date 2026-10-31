# 01 — Feasibility

Status: draft · Last reviewed against upstream commit `a7c6b4d` (firmware version 17,
Android app 2.0.0.1).

## Summary

An Apple app for macOS, iOS and iPadOS is **feasible without firmware changes**.
The firmware already exposes the complete host protocol — control, RX/TX audio,
digital voice and APRS — over a **BLE GATT service**, which every Apple platform
can use through CoreBluetooth without MFi licensing. On macOS, USB serial and
Bluetooth Classic SPP are additionally available.

The Android app cannot be compiled for Apple platforms; the Apple app is a new,
native Swift code base. The Android protocol, codec and AX.25 classes are plain
Java and can be executed unmodified on the JVM to generate golden test vectors,
which keeps both implementations provably compatible.

## Existing system

| Component | Facts |
|---|---|
| Firmware | ESP32-WROOM-32, SA818 VHF/UHF module, `FIRMWARE_VER = 17`. Sessions on USB serial, Bluetooth Classic SPP and BLE run in parallel. |
| Host protocol | KISS framing; AX.25 in KISS DATA frames, kv4p commands in KISS SETHARDWARE vendor frames (`"KV4P"`, version `0x01`). See [03-protocol-spec.md](03-protocol-spec.md). |
| Audio on the wire | 16 kHz mono, IMA ADPCM (WAV variant), 128-byte blocks = 249 samples (~15.6 ms). ≈ 8.2 kB/s per direction plus framing. |
| BLE | Service `00000001-ba2a-46c9-ae49-01b0961f68bb`, preferred MTU 247, notify subscription required, HELLO sent after subscription, flow-control window 4096 bytes. Device name `kv4p-XXXXXX`. |
| Android app | ~15 k lines Java. USB serial first, BLE fallback. |

## Feature inventory (Android app)

| Feature | Android implementation | Apple feasibility |
|---|---|---|
| Connect via USB serial | `UsbSerialRadioTransport`, usb-serial-for-android | macOS only (IOKit/POSIX serial). iOS/iPadOS: not possible without MFi. |
| Connect via BLE | `BleKissRadioTransport` | All platforms (CoreBluetooth). |
| RX audio, squelch, S-meter | `RadioAudioService`, `ImaAdpcm`, `Protocol.calculateSMeterValue` | All platforms (AVAudioEngine). |
| TX audio / PTT, sticky PTT, mic gain boost | `RadioAudioService`, `MicGainBoost` | All platforms; iOS needs `AVAudioSession` play-and-record. |
| Frequency, bandwidth, CTCSS, squelch, power, filters | `HostDesiredState` | All platforms (pure protocol). |
| Memories and groups | Room (`ChannelMemory`) | All platforms. |
| Scan | `RadioMode.SCAN` | All platforms. |
| Find repeaters (RepeaterBook CSV import) | `FindRepeatersActivity` | All platforms (network + CSV parsing). |
| APRS RX/TX, beacon, messages, digipeat | firmware AFSK + `java-aprs` | All platforms; parser must be ported (JVM library). |
| APRS-IS / iGate | `AprsIsClient` (`java-aprs`) | All platforms (TCP). |
| Location for beacons | Play Services Location | CoreLocation. |
| FreeDV 2400B digital voice | modem on ESP32, Codec2 1300 on host (`codec2-android`) | All platforms; Codec2 is C and can be built as an XCFramework. |
| Firmware flashing | `esp32-flash-lib` over USB | macOS over USB is possible; iOS/iPadOS not over USB. |
| Background operation | foreground service | macOS: unrestricted. iOS: `audio` + `bluetooth-central` background modes. |

## Platform constraints

- **iOS/iPadOS USB:** generic USB serial devices require MFi certification. Not an
  option for this project ([ADR-0002](adr/0002-radio-transport.md)).
- **Bluetooth Classic SPP:** only usable on macOS (IOBluetooth); iOS exposes no SPP API.
- **Audio session (iOS):** RX playback and TX recording need `.playAndRecord`,
  interruption and route-change handling. macOS has no `AVAudioSession`.
- **Background (iOS):** keeping a BLE link and audio alive needs background modes
  and has App Review implications.
- **App Store:** an app that transmits on amateur radio frequencies is allowed,
  but review notes should explain the required license and hardware.
- **Firmware updates:** without USB on iOS, flashing stays external
  (web flasher / Android / macOS) unless OTA is added to the firmware
  ([ADR-0009](adr/0009-firmware-updates.md)).

## Dependencies and Apple counterparts

| Android dependency | Purpose | Apple counterpart |
|---|---|---|
| usb-serial-for-android | USB serial | IOKit / POSIX `termios` (macOS only) |
| Android BLE APIs | BLE central | CoreBluetooth |
| AudioTrack / AudioRecord | audio I/O | AVAudioEngine (+ AVAudioSession on iOS) |
| `ImaAdpcm` (own code) | ADPCM codec | Swift port, pinned by golden vectors |
| `javAX25` (own code) | AX.25 packet model | Swift port, pinned by golden vectors |
| `io.github.dkaukov:java-aprs` | APRS parsing, APRS-IS | Swift implementation ([ADR-0006](adr/0006-aprs-ax25.md)) |
| `io.github.dkaukov:codec2-android` | Codec2 1300 | Codec2 C library as XCFramework ([ADR-0005](adr/0005-codec2-freedv.md)) |
| `io.github.dkaukov:esp32-flash-lib` | flashing | out of scope for phase 1 |
| Room | persistence | SwiftData ([ADR-0007](adr/0007-persistence.md)) |
| Play Services Location | location | CoreLocation |

## Reusing the Android code without modifying it

- `Protocol.java`, `ImaAdpcm.java` and `javAX25/` are plain Java. `Protocol`
  only touches `android.util.Log`, `androidx.annotation.NonNull` and Lombok, which
  can be provided as stubs/annotation processor in a separate JVM project.
- `tools/test-vectors/` compiles these sources **by reference** (Gradle source
  sets pointing into `android-src/`) and emits JSON vectors; nothing in
  `android-src/` changes ([ADR-0004](adr/0004-android-code-reuse.md)).
- Firmware native tests (`microcontroller-src/test/`) cover KISS and the audio
  codec and serve as an additional source of test cases.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| BLE throughput/latency on iOS for full-duplex audio framing | audio drop-outs | MTU 247 + write-without-response; measure in phase 1 on macOS; jitter buffer |
| macOS vs. iOS CoreBluetooth behaviour differences | late surprises in phase 2 | Transport behind protocol; simulator scenarios; early iOS smoke build |
| Codec2 build for all Apple platforms | FreeDV delayed | Isolated module, last feature in phase 1 |
| Protocol drift as firmware evolves | incompatibility | Golden vectors regenerated from upstream; CI consistency check; version check on HELLO |
| APRS parser port completeness | APRS gaps | Port incrementally against vectors from `java-aprs` |
| App Store review (radio TX, background modes) | distribution delay | TestFlight first; clear review notes |

## Conclusion

Proceed with a native SwiftUI multiplatform app, macOS first. No changes to the
firmware or the Android app are required.

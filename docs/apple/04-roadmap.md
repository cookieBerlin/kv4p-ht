# 04 — Roadmap

Status: draft. Each milestone is developed test-first, committed step by step and
merged via pull request through the CI gate ([ADR-0013](adr/0013-ci-pr-gate.md)).
Every milestone that changes user-visible behaviour updates the
[manual](manual.md) and [FAQ](faq.md).

## Phase 0 — Planning (current)

- [x] Fork, branch, `CLAUDE.md`
- [x] Feasibility, protocol specification, ADRs, architecture
- [x] Review of proposed ADRs → all accepted (ADR-0009 with option 2)

## Phase 1 — macOS (Apple Silicon)

| # | Milestone | Acceptance criteria |
|---|---|---|
| 1.0 | **Foundation** | SwiftPM package with first module, `Makefile`, `swift format` ([ADR-0015](adr/0015-build-layout-and-tooling.md)), coverage gate script, privacy check, `apple-ci.yml` with all required checks green, branch protection on the fork ([ADR-0016](adr/0016-branch-protection.md)). |
| 1.1 | **Test vectors** | `tools/test-vectors/` builds the unmodified Android `Protocol`, `ImaAdpcm`, `javAX25` and emits JSON vectors; CI consistency check active. |
| 1.2 | **Protocol** | `KV4PProtocol` encodes/decodes all frames and structs of [03-protocol-spec.md](03-protocol-spec.md); passes all vectors; flow-control window implemented. |
| 1.3 | **Simulator A + C** | `KV4PSimulator` with HELLO, desired state, status reports, window updates, TX watchdog; base fault scenarios. |
| 1.4 | **Transport** | `RadioTransport`, BLE chunking/reassembly, `BLETransport` adapter, `SerialTransport` (macOS); connects to real hardware and reads HELLO. |
| 1.5 | **Simulator B** | `SimulatorPeripheral` macOS app advertises the GATT service; app connects to it over real BLE. |
| 1.6 | **Radio control** | `RadioController` state machine; frequency, bandwidth, CTCSS, squelch, power, filters; S-meter; version check and outdated-firmware notice. Minimal macOS UI. |
| 1.7 | **RX audio** | ADPCM decode, jitter buffer, AVAudioEngine playback; squelch indication; audible on hardware without drop-outs over BLE. |
| 1.8 | **TX / PTT** | Mic capture, ADPCM encode, PTT (momentary + sticky), mic gain; TX watchdog respected; tested on hardware into a dummy load. |
| 1.9 | **Memories & scan** | Memories and groups (SwiftData), scan mode, RepeaterBook CSV import. |
| 1.10 | **APRS** | AX.25 + APRS parsing/formatting, message list, beacons (CoreLocation), digipeat setting, APRS-IS client/iGate. |
| 1.11 | **FreeDV 2400B** | Codec2 XCFramework, RX/TX digital voice. |
| 1.12 | **Firmware flashing (macOS)** | `KV4PFlasher` against fake ROM bootloader and vectors from `esp32-flash-lib`; firmware images taken from `android-src` at build time; flashes real hardware and verifies MD5; outdated-firmware notice offers the update. |
| 1.13 | **Release candidate macOS** | Settings parity, manual + FAQ complete for macOS. Signed builds come through TestFlight (2.5, [ADR-0036](adr/0036-no-distribution-outside-app-store.md)). |

## Phase 2 — iOS and iPadOS

| # | Milestone | Acceptance criteria |
|---|---|---|
| 2.1 | **Platform adapters** | AVAudioSession (play-and-record, interruptions, route changes), iOS BLE adapter specifics. |
| 2.2 | **Background operation** | `audio` and `bluetooth-central` background modes; RX continues with screen locked. |
| 2.3 | **Layouts** | iPhone (compact) and iPad (regular, multitasking) layouts; PTT ergonomics on touch. |
| 2.4 | **Firmware notice** | Outdated firmware on iOS/iPadOS links to the web flasher and the manual. |
| 2.5 | **Distribution** | TestFlight builds for iOS, iPadOS and macOS, App Store review notes, manual + FAQ. |

## Phase 3 — Device selection, GUI and sync

| # | Milestone | Acceptance criteria |
|---|---|---|
| 3.1 | **Version and build ID** | The build reads the Android `versionName` and uses its first three numbers as the app version, because App Store Connect accepts no more (2.0.0.1 becomes 2.0.0). The build ID stays the upload time. The commit hash is stored in the bundle, and About shows version, build ID and hash. ADR. |
| 3.2 | **BLE device selection** | The app lists the radios it finds, the user chooses one, and the app remembers it for the next connection. |
| 3.3 | **Error alerts** | When an error needs the user's attention, above all a lost connection to the radio, whatever the cause, the app reports it. On iPhone and iPad, a local notification does so while the app is not in the foreground; the app asks for permission the first time it needs it and works without it. On the Mac, a dialog opens, and the Dock icon bounces while the app is in the background. In the foreground, iPhone and iPad also show the error in the app. A disconnect the user chose causes none, and one failure causes one report. Tested through an adapter behind a protocol. ADR. |
| 3.4 | **Screen layout** | The app is structured like the Android app: frequency and S-meter on top, memories or APRS below, PTT always in reach, settings on their own screen. iPhone, iPad and Mac share this structure and use the extra room on large screens. ADR. |
| 3.5 | **Tooltips** | Every control whose meaning is not obvious explains itself: tooltips on the Mac, an equivalent on touch devices. |
| 3.6 | **Callsign and listen-only** | On start without a callsign, the app asks for it. The user can choose listen-only mode instead, in which the app cannot transmit: no PTT, APRS messages, beacons or digipeating. iGate and the APRS-IS feed stay available once a callsign is set. |
| 3.7 | **Accessibility** | Apple's accessibility audit (`performAccessibilityAudit` in UI tests, Accessibility Inspector) passes on all screens on iPhone, iPad and Mac: VoiceOver labels, contrast, Dynamic Type, hit regions. The findings are fixed, and each exception is justified. The audit runs repeatably through the `Makefile`. ADR. |
| 3.8 | **Settings sync** | Settings (callsign, APRS options, PTT settings, TX limits) changed on one device reach the user's other iPhones, iPads and Macs through iCloud. The chosen radio stays local to each device. ADR. |
| 3.9 | **Memory sync** | Memories and groups sync between the user's devices through iCloud (CloudKit). Concurrent changes and deletions do not lose data, and a device without iCloud keeps working locally. ADR. |

## Phase 99 — App Store release

Deferred: the maintainer plans it later. Until then, the app is distributed through
TestFlight only ([ADR-0036](adr/0036-no-distribution-outside-app-store.md)).

| # | Milestone | Acceptance criteria |
|---|---|---|
| 99.1 | **App Store release** | Store listing, screenshots, privacy policy, App Review for iOS, iPadOS and macOS. |

## Hardware tests

The open tests are listed with IDs in [hardware-tests.md](hardware-tests.md). `make testflight` generates
the *What to Test* text of a build from that list, until the tests are marked as done.

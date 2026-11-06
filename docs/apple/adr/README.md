# Architecture Decision Records — Apple app

Process: [ADR-0001](0001-record-architecture-decisions.md) · Template: [0000-template.md](0000-template.md)

| ADR | Title | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-radio-transport.md) | Radio transport | Accepted |
| [0003](0003-app-technology.md) | App technology | Accepted |
| [0004](0004-android-code-reuse.md) | Reuse of the Android code as reference and test oracle | Accepted |
| [0005](0005-codec2-freedv.md) | Codec2 for FreeDV 2400B | Accepted |
| [0006](0006-aprs-ax25.md) | APRS and AX.25 implementation | Accepted |
| [0007](0007-persistence.md) | Persistence | Accepted |
| [0008](0008-minimum-os-versions.md) | Minimum OS versions | Superseded by 0060 |
| [0009](0009-firmware-updates.md) | Firmware updates | Accepted |
| [0010](0010-repository-structure.md) | Repository structure | Accepted |
| [0011](0011-coverage-policy.md) | Test coverage policy | Accepted |
| [0012](0012-platform-strategy.md) | Platform strategy | Accepted |
| [0013](0013-ci-pr-gate.md) | CI and pull request gate | Accepted, amended by 0015, 0016, 0017 |
| [0014](0014-radio-simulator.md) | Radio simulator | Accepted |
| [0015](0015-build-layout-and-tooling.md) | Build layout and lint tooling | Accepted |
| [0016](0016-branch-protection.md) | Branch protection without required approvals | Accepted |
| [0017](0017-ci-change-detection.md) | CI change detection instead of path filters | Accepted |
| [0018](0018-transport-adapters.md) | Transport logic as state machines behind thin adapters | Proposed |
| [0019](0019-xcode-app-project.md) | Xcode project for the app target | Accepted |
| [0020](0020-rx-audio-pipeline.md) | RX audio pipeline | Proposed |
| [0021](0021-tx-audio-and-ptt.md) | TX audio and PTT | Proposed |
| [0022](0022-memories-and-scan.md) | Memories, scan and RepeaterBook import | Proposed |
| [0023](0023-aprs-receive-path.md) | APRS receive path as a port of java-aprs | Proposed |
| [0024](0024-aprs-messaging.md) | APRS messaging | Proposed |
| [0025](0025-aprs-beacons-and-digipeating.md) | APRS position beacons and digipeating | Proposed |
| [0026](0026-aprs-is-and-igate.md) | APRS-IS and iGate | Proposed |
| [0027](0027-freedv-voice-and-codec2-vendoring.md) | FreeDV 2400B voice and vendored Codec2 | Proposed |
| [0028](0028-firmware-flashing.md) | Firmware flashing as a port of FirmwareUtils | Proposed |
| [0029](0029-app-settings.md) | App settings in the user defaults | Proposed |
| [0030](0030-ios-audio-session.md) | The iOS audio session | Proposed |
| [0031](0031-ios-background-operation.md) | Background operation on iOS | Proposed |
| [0032](0032-ios-layouts.md) | iPhone and iPad layouts | Proposed |
| [0033](0033-store-readiness.md) | App icon, privacy manifest and export compliance | Proposed |
| [0034](0034-macos-release.md) | Signed and notarized macOS release | Superseded by 0036 |
| [0035](0035-testflight.md) | TestFlight distribution | Proposed |
| [0036](0036-no-distribution-outside-app-store.md) | No distribution outside the App Store | Proposed |
| [0037](0037-version-and-build-id.md) | App version, build ID and commit | Proposed |
| [0038](0038-ble-device-selection.md) | Choosing a radio over Bluetooth | Proposed |
| [0039](0039-error-alerts.md) | Reporting a failed connection | Proposed |
| [0040](0040-screen-layout.md) | Screen layout and control explanations | Proposed |
| [0041](0041-simulator-settings.md) | Simulator settings | Proposed |
| [0042](0042-memory-editor.md) | Memory editor | Proposed |
| [0043](0043-pause-other-audio.md) | Pause other audio | Proposed |
| [0044](0044-mute-other-apps-on-the-mac.md) | Mute other apps on the Mac | Proposed |
| [0045](0045-repeater-access-tone.md) | Repeater access tone | Proposed |
| [0046](0046-lock-screen-ptt.md) | PTT from the lock screen | Proposed (deferred) |
| [0047](0047-callsign-and-listen-only.md) | Callsign and listen-only | Proposed |
| [0048](0048-settings-structure.md) | Settings structure | Proposed |
| [0049](0049-two-bundled-firmwares.md) | Two bundled firmwares | Proposed |
| [0050](0050-draggable-squelch-mark.md) | Draggable squelch mark | Proposed |
| [0051](0051-settings-sync.md) | Settings sync | Proposed |
| [0052](0052-memory-sync.md) | Memory sync | Proposed |
| [0053](0053-distance-to-stations.md) | Distance to stations | Proposed |
| [0054](0054-aprs-symbols-and-devices.md) | APRS symbols and devices | Proposed |
| [0055](0055-aprs-packet-types-and-units.md) | APRS packet types and units | Proposed |
| [0056](0056-background-beacons.md) | Background beacons | Proposed |
| [0057](0057-aprs-history.md) | APRS history | Proposed |
| [0058](0058-aprs-messages.md) | APRS messages | Proposed |
| [0059](0059-logging-and-problem-reports.md) | Logging and problem reports | Proposed |
| [0060](0060-minimum-os-27.md) | Minimum OS 27 | Proposed |
| [0061](0061-aprs-chats.md) | APRS chats | Proposed |
| [0062](0062-accessibility-audit.md) | Accessibility audit | Proposed |
| [0063](0063-sstv.md) | SSTV receive and transmit | Proposed |

# 04 — Roadmap

Status: draft. Each milestone is developed test-first, committed step by step and
merged via pull request through the CI gate ([ADR-0013](adr/0013-ci-pr-gate.md)).
Every milestone that changes user-visible behaviour updates the
[manual](manual.md) and [FAQ](faq.md).

**Milestones:** ⬜ open · ✅ implemented and merged. A milestone's pull request ticks its
box. Hardware test results are in [hardware-tests.md](hardware-tests.md).

## Phase 0 — Planning

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ✅ | 0.1 | **Setup** | Fork, branch, `CLAUDE.md`. |
| ✅ | 0.2 | **Planning documents** | Feasibility, protocol specification, ADRs, architecture. |
| ✅ | 0.3 | **ADR review** | Review of proposed ADRs → all accepted (ADR-0009 with option 2). |

## Phase 1 — macOS (Apple Silicon)

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ✅ | 1.0 | **Foundation** | SwiftPM package with first module, `Makefile`, `swift format` ([ADR-0015](adr/0015-build-layout-and-tooling.md)), coverage gate script, privacy check, `apple-ci.yml` with all required checks green, branch protection on the fork ([ADR-0016](adr/0016-branch-protection.md)). |
| ✅ | 1.1 | **Test vectors** | `tools/test-vectors/` builds the unmodified Android `Protocol`, `ImaAdpcm`, `javAX25` and emits JSON vectors; CI consistency check active. |
| ✅ | 1.2 | **Protocol** | `KV4PProtocol` encodes/decodes all frames and structs of [03-protocol-spec.md](03-protocol-spec.md); passes all vectors; flow-control window implemented. |
| ✅ | 1.3 | **Simulator A + C** | `KV4PSimulator` with HELLO, desired state, status reports, window updates, TX watchdog; base fault scenarios. |
| ✅ | 1.4 | **Transport** | `RadioTransport`, BLE chunking/reassembly, `BLETransport` adapter, `SerialTransport` (macOS); connects to real hardware and reads HELLO. |
| ✅ | 1.5 | **Simulator B** | `SimulatorPeripheral` macOS app advertises the GATT service; app connects to it over real BLE. |
| ✅ | 1.6 | **Radio control** | `RadioController` state machine; frequency, bandwidth, CTCSS, squelch, power, filters; S-meter; version check and outdated-firmware notice. Minimal macOS UI. |
| ✅ | 1.7 | **RX audio** | ADPCM decode, jitter buffer, AVAudioEngine playback; squelch indication; audible on hardware without drop-outs over BLE. |
| ✅ | 1.8 | **TX / PTT** | Mic capture, ADPCM encode, PTT (momentary + sticky), mic gain; TX watchdog respected; tested on hardware into a dummy load. |
| ✅ | 1.9 | **Memories & scan** | Memories and groups (SwiftData), scan mode, RepeaterBook CSV import. |
| ✅ | 1.10 | **APRS** | AX.25 + APRS parsing/formatting, message list, beacons (CoreLocation), digipeat setting, APRS-IS client/iGate. |
| ✅ | 1.11 | **FreeDV 2400B** | Codec2 XCFramework, RX/TX digital voice. |
| ✅ | 1.12 | **Firmware flashing (macOS)** | `KV4PFlasher` against fake ROM bootloader and vectors from `esp32-flash-lib`; firmware images taken from `android-src` at build time; flashes real hardware and verifies MD5; outdated-firmware notice offers the update. |
| ✅ | 1.13 | **Release candidate macOS** | Settings parity, manual + FAQ complete for macOS. Signed builds come through TestFlight (2.5, [ADR-0036](adr/0036-no-distribution-outside-app-store.md)). |

## Phase 2 — iOS and iPadOS

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ✅ | 2.1 | **Platform adapters** | AVAudioSession (play-and-record, interruptions, route changes), iOS BLE adapter specifics. |
| ✅ | 2.2 | **Background operation** | `audio` and `bluetooth-central` background modes; RX continues with screen locked. |
| ✅ | 2.3 | **Layouts** | iPhone (compact) and iPad (regular, multitasking) layouts; PTT ergonomics on touch. |
| ✅ | 2.4 | **Firmware notice** | Outdated firmware on iOS/iPadOS links to the web flasher and the manual. |
| ✅ | 2.5 | **Distribution** | TestFlight builds for iOS, iPadOS and macOS, App Store review notes, manual + FAQ. |

## Phase 3 — Device selection, GUI and sync

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ✅ | 3.1 | **Version and build ID** | The build reads the Android `versionName` and uses its first three numbers as the app version, because App Store Connect accepts no more (2.0.0.1 becomes 2.0.0). The build ID stays the upload time. The commit hash is stored in the bundle, and About shows version, build ID and hash. ADR. |
| ✅ | 3.2 | **BLE device selection** | The app lists the radios it finds, the user chooses one, and the app remembers it for the next connection. |
| ✅ | 3.3 | **Error alerts** | When an error needs the user's attention, above all a lost connection to the radio, whatever the cause, the app reports it. On iPhone and iPad, a local notification does so while the app is not in the foreground; the app asks for permission the first time it needs it and works without it. On the Mac, a dialog opens, and the Dock icon bounces while the app is in the background. In the foreground, iPhone and iPad also show the error in the app. A disconnect the user chose causes none, and one failure causes one report. Tested through an adapter behind a protocol. ADR. |
| ✅ | 3.4 | **Screen layout** | The app is structured like the Android app: frequency and S-meter on top, memories or APRS below, PTT always in reach, settings on their own screen. iPhone, iPad and Mac share this structure and use the extra room on large screens. ADR. |
| ✅ | 3.5 | **Tooltips** | Every control whose meaning is not obvious explains itself: tooltips on the Mac, an equivalent on touch devices. |
| ✅ | 3.5a | **Simulator settings** | While the simulator is the chosen radio, the settings show a section to configure it: band (VHF or UHF), firmware version (too old or current), FreeDV modem, power switch and SA818 module (found or missing), and a radio that does not answer. These take effect at the next connection and are locked while connected. These act at once: a button that loses the connection, the received signal with a choice of strength (replacing the present switch) and a button per APRS packet type (message, position, object, weather, status), with placeholder data only. The choices are saved locally on the device and stay out of settings sync (3.8). The section stays in release builds, as App Review uses the simulator. |
| ✅ | 3.5b | **Memory editor** | The storage keeps an order for the memories and migrates existing ones. An editor in the settings edits, adds and reorders the memories and groups, and takes up the RepeaterBook import assistant. Every text field, here and in the memory form, shows a visible label on iOS, where a field otherwise shows only its placeholder. ADR. |
| ✅ | 3.5c | **Pause other audio** | iPhone and iPad first: while the squelch is open and while transmitting, podcasts of other apps pause and music gets quieter. They return once the squelch has stayed closed for a time the settings can change, 3 s by default. No received audio may get lost: it waits in a buffer during the switch, and comes a moment later. PTT pauses all other apps before it opens the microphone, so nothing goes on air; it stays instant while nothing else plays. A test on an iPhone showed that this also works with the screen locked, that the session must be deactivated for each switch, and that it must stay inactive for a moment for podcasts to return ([ADR-0043](adr/0043-pause-other-audio.md)). The feature does not tell voice from APRS packets, so the settings offer *Keep playing* and *Lower all* besides the default. Hardware tests cover the real radio over Bluetooth and Bluetooth headsets. On the Mac, which has no audio session, the user can choose to mute all other apps through a Core Audio tap; they run on silently, and the radio's own sound stays ([ADR-0044](adr/0044-mute-other-apps-on-the-mac.md)). ADR. |
| ✅ | 3.5d | **Repeater access tone** | A button next to PTT on the memories page sends a tone that opens a repeater. It works only while held: the transmitter starts; once the radio reports that it transmits, the set wait passes (the app sends silence), and the tone plays for the set time, over the air at 50 % level for now, and quieter on the device. The transmitter then stops by itself, also if the button is still held. The microphone stays closed. Releasing the button stops the transmission at once and shows a message that the repeater may not have opened. If the radio does not report transmitting within 2 s, the app stops and says so. While transmitting and held, the iPhone vibrates continuously; PTT keeps its short pulses. Settings: tone (off by default, 1000, 1450, 1750 or 2100 Hz), length (0.25, 0.5, 1 by default, 2, 3, 4 or 5 s) and wait (0, 100, 200 by default, 300, 500 or 1000 ms). Each memory can store its own tone and length or follow the settings, which is the default and what existing memories migrate to; the memory takes precedence. The button shows only with a tone set, a connected radio, microphone permission and analog voice. Sticky PTT has no effect on it; the frequency limits and listen-only mode (3.6) apply. Hardware tests cover the function now and the deviation per tone, with and without pre-emphasis, later. ADR. |
| ⏸ | 3.5e | **PTT from the lock screen (optional, deferred)** | Transmitting without unlocking the iPhone, through Apple's Push to Talk framework. A test on an iPhone found a way that works, but it adds more complexity than the app should take on for now, so it stays an option for the future. Findings, open questions and the plan are in [ADR-0046](adr/0046-lock-screen-ptt.md). |
| ✅ | 3.6 | **Callsign and listen-only** | On start without a callsign, the app asks for it. The user can choose listen-only mode instead, in which the app cannot transmit: no PTT, access tone, APRS messages, acknowledgements, beacons or digipeating. iGate and the APRS-IS feed stay available once a callsign is set. Without a callsign nothing goes out at all, also not to the iGate ([ADR-0047](adr/0047-callsign-and-listen-only.md)). |
| ✅ | 3.6a | **Settings structure** | The settings are an overview with pages: Station, Radio, Transmit, Audio, APRS, Memories, Simulator (only while it is the chosen radio), Advanced and, on iPhone and iPad, About. The Mac shows a sidebar, iPhone and iPad a list. The explanations are visible on every platform. No function changes ([ADR-0048](adr/0048-settings-structure.md)). |
| ✅ | 3.6b | **Draggable squelch mark** | The squelch can be set on the S-meter of the main screen: on iOS hold for about 0.3 s, then drag, with a vibration; on the Mac drag directly. The mark moves in steps from 0 to 8, shows the level, and the value is sent on release. Without a radio it stays hidden. While transmitting and during a scan it is locked. The stepper in the settings stays ([ADR-0050](adr/0050-draggable-squelch-mark.md)). |
| ✅ | 3.8 | **Settings sync** | Settings (callsign, APRS options, PTT settings, TX limits) changed on one device reach the user's other iPhones, iPads and Macs through iCloud. The chosen radio and everything that makes a device transmit stay local to it ([ADR-0051](adr/0051-settings-sync.md)). |
| ✅ | 3.9 | **Memory sync** | Memories and groups sync between the user's devices through iCloud (CloudKit). For concurrent changes the last change of a field wins, and memories with the same name, frequency and group alike in everything are merged, and a device without iCloud keeps working locally. ([ADR-0052](adr/0052-memory-sync.md)). |
| ⬜ | 3.7 | **Accessibility** | Comes last in phases 3 and 4, after all their other milestones. Apple's accessibility audit (`performAccessibilityAudit` in UI tests, Accessibility Inspector) passes on all screens on iPhone, iPad and Mac: VoiceOver labels, contrast, Dynamic Type, hit regions. The findings are fixed, and each exception is justified. The audit runs repeatably through the `Makefile`. ADR. |

## Phase 4 — Firmware selection and APRS

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ✅ | 4.1 | **Firmware selection (macOS)** | The Mac app contains two firmwares, and the user chooses at each update. The nightly build, for this app, is preselected and shows its build time, commit and SHA-256. Firmware 17 is clearly marked as suitable only for the Android app, so that a radio can go back to it. The app checks the checksum of the nightly image and never writes the board configuration. It refuses firmware 17, on which it would transmit without sound, and offers the update; after flashing firmware 17 it does not reconnect. iPhone and iPad point to a Mac or the Android nightly app, as the web flasher offers only firmware 17. Flashing stays on the Mac ([ADR-0049](adr/0049-two-bundled-firmwares.md)). |
| ✅ | 4.2 | **APRS position** | A position opens in Apple Maps through a link. The list shows distance and direction from the user's position, once it is known ([ADR-0053](adr/0053-distance-to-stations.md)). |
| ✅ | 4.3 | **APRS symbols** | A received symbol is shown as what it means, not as raw characters. `_3` is found to be the mark of a Yaesu FT5D at the end of a Mic-E comment, and such marks show as the name of the radio. Sending and decoding beacons with the app's own symbols stays as a test. Every known symbol has an icon, by this order: a Unicode character, a system image, one drawn for the app; the beacon symbols in the settings use them too. Details are on the icon: a tooltip on the Mac, holding it on iPhone and iPad ([ADR-0054](adr/0054-aprs-symbols-and-devices.md)). |
| ⬜ | 4.4 | **APRS packet types** | Messages, positions, objects, weather, status, capabilities and unknown packets each have a clear display of their own, at least as readable as in the Android app. |
| ⬜ | 4.5 | **Background GPS** | While the radio is connected and the beacon is on, position beacons keep going with the screen locked, using the *when in use* permission and the system's location indicator. Errors that stop the beacon, such as a missing location permission or no position, are reported through 3.3. ADR, superseding the beacon part of [ADR-0031](adr/0031-ios-background-operation.md). |
| ⬜ | 4.6 | **APRS history** | All packets of the list, not only text messages, can stay stored across restarts of the app. A switch in the settings controls this and is on by default; turning it off asks whether to delete what is stored. The user can delete a single packet (through a button on its row, as a sideways swipe changes the page on a phone) or all of them at once, after a confirmation. The settings choose how long packets stay: 1, 7 or 30 days, or without limit. The list can be filtered and searched by callsign and packet type. It can be exported through the system's share or save dialog, as CSV and as raw packets in text form, and the export follows the filter. A tap on a message fills in its sender as the recipient. New messages to the user show as a number on the APRS tab and, in the background, as a notification (3.3). Messages sent but not acknowledged before a restart are not sent again and show as not delivered. The data stays on the device and is not synced. ADR. |
| ⬜ | 4.7 | **APRS conversations** | Simple chats over APRS, built on 4.6. A conversation is a filtered view of the stored text messages, so it needs no storage of its own. A switch at the top of the APRS page changes between *Packets* and *Chats*; the filter for the user's own messages stays with the packets. *Chats* lists the stations, and a tap opens one in time order, with the user's messages told apart from the other station's and each sent message showing its delivery state. A conversation holds the messages to and from the user only; bulletins and messages between other stations stay in the packet list. Each callsign with its SSID is a conversation of its own, as a reply must reach that SSID. **+** starts a conversation with a callsign that has not sent anything yet. Typing sends to that callsign, with a counter and a stop at the limit of 67 characters, so that nothing is cut off. Each conversation shows its number of unread messages until it is opened, and a tap on a notification opens it. A message not delivered offers *Send again* and is never sent again by itself. A single message or, after a confirmation, a whole conversation can be deleted, which also removes those packets from the packet list. Without a callsign or in listen-only mode (3.6), chats can be read but have no input. The filter and the export of 4.6 apply to the messages. |

## Phase 5 — RepeaterBook and SSTV

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ⬜ | 5.1 | **RepeaterBook download** | The options are evaluated first: embedded web page as in the Android app, official API, stored login. The evaluation covers RepeaterBook's terms. The chosen option replaces the manual CSV download where possible, and the password does not enter the repository. ADR. |
| ⬜ | 5.2 | **SSTV receive** | The milestone starts with two decisions: which modes the app supports, and whether an existing library can be reused or the decoder is written from scratch (including its licence). The app then decodes SSTV images from the received audio and shows and saves them. The decoder is tested with generated test signals, as the Android app has no SSTV to serve as an oracle. ADR. |
| ⬜ | 5.3 | **SSTV transmit** | The user chooses an image, and the app sends it as it is in the chosen modes; the callsign is part of the image. The app's own TX time limit does not apply to it, and the transmission can be stopped at any time. Listen-only mode blocks it, and the frequency limits stay in force. Encoder and decoder pass a round trip in the tests. The firmware ends a transmission after 200 s: longer modes wait until the firmware allows them, as a separate step later. ADR, or part of the ADR of 5.2. |

## Phase 99 — App Store release

Deferred: the maintainer plans it later. Until then, the app is distributed through
TestFlight only ([ADR-0036](adr/0036-no-distribution-outside-app-store.md)).

|   | # | Milestone | Acceptance criteria |
|---|---|---|---|
| ⬜ | 99.1 | **App Store release** | Store listing, screenshots, privacy policy, App Review for iOS, iPadOS and macOS. |

## Hardware tests

The open tests are listed with IDs in [hardware-tests.md](hardware-tests.md). `make testflight` generates
the *What to Test* text of a build from that list, until the tests are marked as done.

# Changelog

What changed for users of kv4p HT for iPhone, iPad and Mac, newest first. Each TestFlight build has a section of its
own, with its version, build and date.

## Unreleased

### Added

- iPhone Duo, folded: the symbols of the pages stand at the side below the status bar, which leaves the pages more
  room.

### Fixed

- When an iPhone Duo folds or unfolds, an iPad window changes from narrow to wide or back, or a large iPhone turns,
  PTT and the access tone stop if they were held, and an unsent APRS message, the open settings and the page shown
  stay.
- iPhone Duo, folded: the next page no longer shows beside the status bar.

## 0.2.0 (20261111.2136) – 2026-11-11

### Added

- A map with your position, the repeaters and frequencies of your memories, and the APRS beacons that have a position,
  each as a layer to switch on and off, by band.
- The APRS stations and objects heard on the map, each at its last position with its symbol, within a time window
  from 15 minutes to all, also from the stored packets; a tap leads to their packets or a chat.
- *Show all* on the map brings every point and your position back into view.
- Import of the DARC repeater lists. A memory is a repeater or a frequency and can have a comment and a position.
- A settings page *Pages*, which switches APRS and its pages off.
- APRS chats: the messages to and from a station in one conversation, a new chat with **+**, *Send again* for a
  message that was not delivered, and notifications that open their chat.
- APRS history: the packets stay stored across restarts, and can be filtered, searched, deleted and exported as CSV or
  raw packets.
- APRS packets show what they are: messages, positions, objects, weather, status and capabilities, with symbols, the
  name of the radio that sent them, the distance and direction to the station, and a link to Apple Maps.
- Position beacons also go out with the screen locked.
- A choice of metric or imperial units.
- Choose a radio from the ones found over Bluetooth; the app remembers it.
- The app reports a lost connection and other errors, also by notification on iPhone and iPad and with the Dock icon on
  the Mac.
- A callsign at the first start, or listen-only mode, in which the app cannot transmit.
- A repeater access tone next to PTT.
- The squelch can be set by dragging its mark on the S-meter.
- The frequency changes digit by digit, in the channel raster.
- A memory editor in the settings, which edits, adds and reorders memories and groups.
- Settings and memories sync between your devices through iCloud.
- Other apps pause or get quieter while the squelch is open and while you transmit.
- Settings for the built-in simulated radio, to try errors without hardware.
- On the Mac, a choice of two firmwares for each update: the nightly build for this app, or firmware 17 for the
  Android app.
- A log on the device and a problem report, also after a crash.
- Tooltips on the Mac and explanations on iPhone and iPad for every control whose meaning is not obvious.
- About shows the version, the build and the commit.
- *What's New* in About shows this changelog, and after an update the app shows once what is new in that build.

### Changed

- The settings are an overview with pages: a sidebar on the Mac, a list on iPhone and iPad.
- The screen is laid out like the Android app: frequency and S-meter on top, memories or APRS below, PTT always in
  reach.
- VoiceOver, Dynamic Type up to the largest text size and contrast work on every screen. The bars above and below the
  lists are opaque, and the button to connect is a darker blue on iPhone and iPad.
- The app needs iOS, iPadOS or macOS 27.
- The app's version is its own, below 1.0 until the App Store release, instead of the Android app's.

### Fixed

- After a firmware update, the main window no longer shows a connection that is gone.

## 0.1 (20261101.2216) – 2026-11-01

### Added

- Control a kv4p HT radio from iPhone, iPad and Mac: over Bluetooth, or by USB cable on the Mac.
- A built-in simulated radio, to try the app without hardware.
- Frequency, bandwidth, CTCSS tones, squelch, power and filters, with an S-meter.
- Received audio, also with the screen locked on iPhone and iPad.
- Transmitting with PTT, held or, with sticky PTT, switched on and off.
- Memories in groups, scanning, and an import of RepeaterBook CSV files.
- APRS: packets, messages, position beacons, digipeating, APRS-IS and an iGate.
- FreeDV 2400B digital voice.
- Firmware updates of the radio by USB cable on the Mac; on iPhone and iPad, a notice of outdated firmware leads to
  the web flasher.
- Layouts for iPhone, iPad and Mac, settings, and an About window with the licences.

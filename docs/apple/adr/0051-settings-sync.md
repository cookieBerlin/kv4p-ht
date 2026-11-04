# ADR-0051: Settings sync

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

A user with an iPhone and a Mac enters the callsign, the APRS options and the limits twice.
Settings are small and rarely change, and iCloud's key-value store is made for them: it
holds 1 MB and 1024 keys, and these settings take a few hundred bytes in ten keys.

## Decision

- **iCloud's key-value store,** behind a protocol with a thin adapter. There is no server of
  our own, and no account other than the Apple ID.
- **What syncs is what is the same for a person:** callsign, sticky PTT, access tone, APRS
  symbol, position accuracy, beacon frequency, APRS filter and frequency limits.
- **What stays on the device** depends on the device or makes it send: the radio, the
  simulator, the memory group, other audio, mic gain, listen only, and the switches for
  the beacon, digipeating, iGate and the APRS-IS feed. Turning on one device must not make
  another one transmit.
- **One key per setting,** so that changes of different settings on two devices do not
  overwrite each other. For the same setting the last change wins.
- **Only changes go up, after a pause of 2 s,** so that a callsign is not sent letter by
  letter; leaving the app sends what waits. Incoming values are not sent back.
- **A new device overwrites nothing:** it takes what the cloud has, and a default is never
  sent as a first value. A device that has a non-default value the cloud does not know
  sends it once, so that existing settings reach the second device. If that happens before
  the device has received the cloud's values, it can win over them, once.
- **A callsign is always synced, also when it is removed.** An incoming callsign closes the
  question at the start, and its removal does not open it during use.
- **A switch *iCloud sync* on the Station page,** on by default. Without iCloud the app
  works as before, with a hint below the switch.
- **Entitlements:** a Mac refuses to start an app that claims iCloud and has no team, so a
  build without a team, as for a contributor, uses the entitlements without iCloud. The build
  setting chooses by `DEVELOPMENT_TEAM`, so a Mac has a second entitlements file. iOS builds
  on a device always need a team, and have one file.

## Consequences

- The callsign is stored in the user's iCloud account, which the FAQ and manual say.
- Changes can take a while to arrive, as the system decides when the store syncs.
- The two Mac entitlements files must stay the same but for iCloud.
- Memories need more than this store, and get their own way in milestone 3.9.

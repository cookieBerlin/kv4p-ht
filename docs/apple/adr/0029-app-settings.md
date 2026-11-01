# ADR-0029: App settings in the user defaults

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

The Android app keeps its own settings as `AppSetting` rows (name and string
value). These include:

- the callsign, mic gain and sticky PTT;
- APRS beacon, symbol, accuracy and frequency;
- digipeating, iGate and the APRS-IS feed;
- the destination filter;
- TX limits per band;
- the last memory group.

`MainActivity.applySettings…` applies them at start. The radio keeps its own
configuration (frequency, squelch, filters, power) in flash.

[ADR-0007](0007-persistence.md) lists a `SettingsRepository` next to the SwiftData
memories. Until now the Apple app kept only the callsign (`@AppStorage`).

## Decision

- **`AppSettings`** (KV4PRadio) holds the settings Android keeps.
  - Defaults are Android's.
  - It encodes as one JSON value; missing or unreadable fields fall back to their
    defaults, so new settings do not reset old ones.
- **`SettingsStore`** (KV4PPersistence) loads and saves that value. The app uses
  `UserDefaultsSettingsStore` with the key `settings`; tests use a store in memory.
  SwiftData is not used for one small value.
- **View model:** it restores the settings at start and saves every change.
  - The TX limits reach the controller (`setTXLimits`, Android
    `updateTxLimitsForBand`).
  - Beacons use the beacon frequency like `aprsBeaconTxOverrideMhz`.
  - The destination filter ports `AprsFeedPolicy.isVisibleToMine`, pinned by
    `aprs-feed-filter.json`.
- **Migration:** the app moves an existing `aprsCallsign` value into the settings
  once.
- **Android-only settings:** *Disable animations* and *Closed captions* are
  Android display settings. macOS has *Reduce motion* and *Live Captions* system
  wide, so the app has no own switches.

## Consequences

- The settings stay on the Mac. No sync and no export yet.
- The APRS history window (`aprsHistoryWindow`) is not needed while the APRS list
  is not stored (Android fixes it to "all").

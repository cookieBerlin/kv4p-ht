# ADR-0025: APRS position beacons and digipeating

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

The Android app sends a position beacon every five minutes once it is enabled
(`AprsBeaconSchedule`; the first one goes out right away). The beacon is
compressed, messaging capable, uses the primary symbol table and the symbol the
user chose (`APRSIconType`). With "approximate" accuracy, the position is
rounded to two decimals. Its content and validation come from java-aprs
(`submitPositionBeacon`, `encodeBeacon`, `isValidBeacon`).

As a fill-in digipeater (`maybeDigipeat`), the library repeats a received packet
once when the first unused path element is `WIDE1-1` or the local callsign, and
replaces that element with the local callsign marked used. The same packet is not
repeated again within 28 s, and the library ignores its own repeats when it hears
them back.

## Decision

- `APRSController` ports beacons and digipeating, pinned by `aprs-beacons.json`
  (valid and rejected beacons with their frames and events) and
  `aprs-digipeating.json`. Weather beacons are left out because the Android app
  does not send them.
- The view model reproduces `AprsBeaconSchedule`, the approximate rounding and
  the symbol list. Beacons and digipeats go through the same transmit rules as
  messages (ADR-0024).
- `LocationProvider` is the location protocol. `CoreLocationProvider` is the only
  adapter and is excluded from coverage. It asks for "while using" permission
  (`CLServiceSession` on iOS, `CLLocationManager` on macOS) and gives up after
  30 s. The app has the location entitlement and usage descriptions.
- A separate beacon frequency, which Android has as an option, is not
  implemented yet; beacons go out on the current TX frequency.

## Consequences

- Positions are only requested while beacons are on, and only sent over RF.
- With digipeating on, the app transmits without a user action; like on Android,
  this needs a callsign and stays inside the ham band.

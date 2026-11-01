# ADR-0026: APRS-IS and iGate

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

The Android app connects to APRS-IS (`rotate.aprs2.net:14580`) with java-aprs
`AprsIsClient` while the iGate or "Show nearby APRS-IS messages" is on:

- **Login:** it logs in with the callsign and passcode. Without the iGate, it uses
  passcode `-1` (receive only). With the feed on, it sets a range filter around
  the phone's position (`r/lat/lon/50`), or `m/50` when the position is unknown.
- **Sending:** it sends at most four queued lines once the login is verified and
  reconnects with a backoff from 1 s to 60 s.
- **iGate:** `AprsController` gates received RF packets with `qAO,<callsign>`.
  It does not gate packets from or for the internet (`TCPIP`, `TCPXX`, `NOGATE`,
  `RFONLY`, `I`, q constructs), queries, or third-party packets nested deeper
  than four. Our own messages and beacons go to APRS-IS with `TCPIP*`.
- **Receiving:** lines received from APRS-IS become internet-only events, which
  are never digipeated, gated or acknowledged.

## Decision

- `APRSController` ports the iGate and APRS-IS parts of `AprsController`, pinned
  by `aprs-internet.json`. `APRSIS` ports `passcode`, `loginLine` and the server
  address rules, pinned by `aprs-is-login.json`. The generator reaches the two
  package-private helpers through `AprsIsAccess`; the library stays unchanged.
- `APRSISClient` ports `AprsIsClient` with Swift concurrency over the
  `LineConnector` protocol. It is tested against a fake server with a manual
  clock. As in `awaitReconnect`, the reconnect delay only ends early when
  the settings or the queue changed during the session. `NetworkLineConnector` (Network.framework, ISO-8859-1 lines) is the
  only adapter and is excluded from coverage.
- The view model follows `updateAprsIsConnection`:
  - connected while either switch is on;
  - transmitting only with the iGate;
  - the feed filter comes from the location when it is known.
- The app has the network client entitlement and identifies itself as
  `kv4p-ht <version>`.

## Consequences

- The passcode is derived from the callsign, as on Android; it is not a secret.
- APRS-IS works without a connected radio (feed); the iGate needs RF.
- A server setting, which Android has internally, is not exposed yet.

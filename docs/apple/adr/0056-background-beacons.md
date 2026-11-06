# ADR-0056: Background beacons

- **Status:** Proposed
- **Date:** 2026-11-05

This supersedes the part on position beacons of
[ADR-0031](0031-ios-background-operation.md).

## Context

With the screen locked, an iPhone keeps receiving, but iOS gives the app no location, so position
beacons wait until the app is on screen again. A failed beacon only shows a line in the app, which
nobody sees then. Beacons go out every five minutes, whatever the user does.

## Decision

- **`CLBackgroundActivitySession` with *when in use* access,** behind a protocol with a thin adapter,
  and the background mode `location`. There is no new question for access and no *Always*. Apple's
  [WWDC23 talk](https://developer.apple.com/videos/play/wwdc2023/10180/) describes this way.
- **It runs only while it serves a beacon:** beacon on, a radio connected, sending allowed and
  location access granted. There is no continuous tracking, and a position is read per beacon.
- **A session can only start in the foreground,** so one that could not start does on the way back.
- **A switch *Beacon in the background*,** on by default and local to the device. It is offered only
  where the limit exists, so not on the Mac. Off, beacons wait for the app, as they did before,
  and the system's indicator stays away.
- **A choice of interval:** 2, 5, 10, 15, 30 or 60 minutes, 5 by default as in the Android app. There
  is no 1, as all stations share the APRS frequency. It syncs like the beacon's other settings,
  as it belongs to the station. A shorter one counts from the moment it is chosen.
- **Failures go the way of [milestone 3.3](../04-roadmap.md):** a position that cannot be found is
  reported once, and again only after a beacon has worked in between, as a tunnel should not bring a
  notice per beacon. The next try comes at the next interval. Access denied ends the beacon, and
  says so.

## Consequences

- With the beacon on and the app in the background, the system's blue indicator stays visible, and
  more battery is used.
- App Review looks closely at the background mode `location`, and the notes explain it.
- Whether beacons really go out with the screen locked can only be tested on a device (HW-35).
  Forum reports speak of updates stopping and of an indicator that stays on iOS 18, unconfirmed
  so far.

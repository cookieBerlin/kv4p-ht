# ADR-0053: Distance to stations

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

The APRS list shows the coordinates of a station as text. Milestone 4.2 asks for a link to
Apple Maps, and the distance and direction from the user's position. Until now, the app
read the position only for beacons and the APRS-IS feed, so the list adds a new reason.

## Decision

- **The position is read only while the list is on screen and access is granted:** when the
  list appears, and then at most once a minute when a new position arrives. There is no
  continuous tracking, and a position read for the beacon or the feed serves as well.
- **It stays on the device.** Nothing is sent for the distance, and it is not rounded by
  the beacon's position accuracy, which is about what others see.
- **The list does not ask for access when it opens.** While the question is open, a button
  *Show distances* asks it. With access denied there is no hint, as the list works without.
- **Haversine on a sphere,** as a list needs no more, and it has no dependency on
  CoreLocation, so it is tested on every platform.
- **Eight directions as text,** which is readable and simple for VoiceOver. Under 100 m the
  direction goes, as the errors of both positions outweigh it.
- **The map opens through a link** on the coordinate line, with a pin named after the
  station or object. The coordinates reach Apple only on that tap. The whole row stays
  free for selecting text.
- **All packets with coordinates count,** so also objects, and those only from the internet.
  Packets of the user's own callsign have no distance.
- **The unit follows the system,** or since [ADR-0055](0055-aprs-packet-types-and-units.md) the setting
  *Units*.

## Consequences

- The purpose text of the location permission names the distances as well.
- A distance can be up to a minute old while moving, and the position of a station is that of
  its last packet.

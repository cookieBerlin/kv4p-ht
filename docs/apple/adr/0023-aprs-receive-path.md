# ADR-0023: APRS receive path as a port of java-aprs

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

[ADR-0006](0006-aprs-ax25.md) decided on an own Swift implementation, pinned by
vectors from the Android code. The Android app does not parse APRS itself: it
hands every received AX.25 frame to `io.github.dkaukov:java-aprs`
(`Parser.parseAX25`). Its `AprsController` turns the packets into the events of
the APRS feed: type, position, message, weather and so on, with repeats merged.
The library has quirks the Android app shows. For example:

- comments of Mic-E and compressed positions start at a fixed offset;
- broken positions read `null INVALID position format.`;
- short timestamped packets are dropped.

## Decision

- `tools/test-vectors` depends on the same library and version as the Android
  app and generates two vector files:
  - `aprs-parser.json`: about 150 frames covering every parser branch;
  - `aprs-events.json`: receive sessions through `AprsController` with an
    in-memory repository that mirrors the app's Room query.
- The generator pins the JVM locale to `en-US`. `Position.getLatitude` formats
  with the default locale, which would otherwise change the vectors with the
  machine.
- `KV4PAPRS` ports the parser and the receive half of `AprsController` faithfully,
  quirks included:
  - Java `char` sign extension;
  - ISO-8859-1, US-ASCII and UTF-8 decoding, `trim` and `split`;
  - `Float` arithmetic for Mic-E and compressed positions;
  - comment offsets and fall-through cases.

  Parts of the library that do not change what the app shows are left out:
  data extensions such as PHG and course/speed, and timestamps.
- With no callsign configured, the receive path acknowledges, digipeats and
  gates nothing, as in the Android app. These parts follow with messaging,
  beacons and APRS-IS.
- The feed is kept in memory for this milestone. Persisting it is part of the
  persistence work for APRS history (ADR-0007).

## Consequences

- The Apple app shows the same events as the Android app for the same packets.
- Changes to java-aprs reach the Apple app through `make vectors`. If the vectors
  change, the port must follow.
- The java-aprs license (GPL-3.0) matches the project license.

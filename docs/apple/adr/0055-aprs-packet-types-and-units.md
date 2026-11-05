# ADR-0055: APRS packet types and units

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

Milestone 4.4 asks for a clear display of each type of packet. A comparison with the Android app
and a run of each type through the parser found more than wording: a station that does not report
a temperature showed as *0 °F · 0 %*, as the event keeps a 0 for what is missing. Rain and snow
were not shown, everything was in °F and mph, packets only from the internet and digipeated ones
were not marked, although the manual said so, and a removed object looked like a live one.

## Decision

- **The event keeps its fields,** as the golden test vectors from the Android code pin them, and
  adds what the display needs: the weather as reported, and whether an object was removed.
- **The text of a row is plain logic in the package,** so that it is tested: the text, a caption
  for what is not plain from it, and the details on the icon.
- **What was not reported is left out,** and so are rain and snow of 0, which are no news.
- **The repeater summary is ported from `AprsObjectSummary`,** the same way as other Android code:
  the generator compiles the unmodified class, and the vectors pin the port. Its map label names
  the pin of an object. It keeps the units of the packet, as range and altitude are what the
  object says.
- **A setting chooses the units:** *System*, *Metric* or *Imperial*, for temperature, distance,
  speed, rain and snow, also the distance to stations of ADR-0053. Pressure stays in hPa, as in the
  Android app. *System* goes by the region, where Britain mixes Celsius and millimetres with miles.
- **The units sync** with the settings of [ADR-0051](0051-settings-sync.md), as they belong to a
  person and not to a device.
- **Telemetry and queries are named, not read.** Reading telemetry needs the definitions a station
  sends separately, which would be a milestone of its own.
- **A removed object stays in the list,** crossed out, as its removal is news as well.

## Consequences

- Snow is taken as the Android code reads it, in inches as sent.
- A region setting of the system other than the measurement system, such as a separate
  temperature unit, is not looked at.
- The list has one more line for many packets.

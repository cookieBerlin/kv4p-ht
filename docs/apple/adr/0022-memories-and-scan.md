# ADR-0022: Memories, scan and RepeaterBook import

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

Android stores channel memories in Room (`ChannelMemory`): name, frequency,
offset (none/down/up, kHz), TX/RX tone labels, group and "skip during scan".
`RadioAudioService` tunes to a memory (`tuneToMemory`, `getTxFreq`) and scans
the memories of the selected group: each one is tuned with the user's squelch
(7 if it is 0). It moves on when the device reports the squelch closed for
250 ms on that memory, and stopping restores the squelch.
`FindRepeatersActivity` embeds the RepeaterBook web page, so the user signs in,
then parses the downloaded CSV (US or international format) into a group of
memories. ADR-0007 chose SwiftData behind repository protocols.

## Decision

- `KV4PPersistence`: `ChannelMemory` is a value type with Android's fields and
  defaults. `MemoryRepository` is the protocol, and `SwiftDataMemoryRepository`
  (a `@ModelActor`) stores it. Ids are assigned in insertion order and are the
  memory id sent to the radio. The tests use in-memory and temporary-file
  stores, so no exclusion is needed.
- `KV4PRadio`:
  - `HamFrequency` holds `makeSafeHamFreq`, shared by the frequency field,
    memories and import.
  - `RadioController.tune(to:)`, `startScan` and `stopScan` implement the
    Android rules. The scan timer runs on the controller's clock and is checked
    on every device state. Transmitting and tuning by hand end the scan.
  - `RepeaterBookImport` ports the CSV parser and the conversion to memories.
- The app imports a CSV file the user downloaded in the browser (file importer,
  user-selected read-only entitlement) instead of embedding RepeaterBook's
  sign-in in a web view.

## Consequences

- Memories are per device; import/export with the Android app is a separate
  topic (ADR-0007).
- The import needs a connected radio for its frequency range, as on Android.
- Scanning depends on the device reporting the squelch: the radio reports every
  change, so a quiet memory is left about 250 ms after the radio confirmed it.

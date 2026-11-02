# ADR-0038: Choosing a radio over Bluetooth

- **Status:** Proposed
- **Date:** 2026-11-02

## Context

The app connects to the first kv4p HT it finds. With several radios in range, the
user cannot choose one. `BLETransport` can already connect to one peripheral, but
its central reports only the identifier, and only while connecting.

## Decision

- **A scanner of its own:** `BLEScanner` finds radios without connecting. It uses a
  central of its own, as a connection takes over the events of its central. A new
  event `advertised` carries the name, which the connection ignores.
- **When it scans:** while the radio screen is visible, the app is active and no
  connection is up or being set up. It scans again after a failed connection or a
  disconnect.
- **The list:** the existing **Radio** picker. After *Bluetooth (first radio found)*
  come the radios found, each with its name and the last four characters of its ID,
  so that radios of the same name differ.
- **Remembering:** `AppSettings.bluetoothRadio` holds the identifier and the name.
  The radio stays in the list before a scan finds it, and it takes a new name when
  a scan reports one. Choosing the first radio found forgets it. Choosing USB or
  the simulator does not.

## Consequences

- The system identifier of a peripheral differs between devices, so this setting
  stays local to each device. Settings sync (milestone 3.8) must leave it out.
- Bluetooth permission is asked when the radio screen first opens, not when the
  user first connects.
- A chosen radio that is off is not replaced by another one: connecting keeps
  waiting for it until the user disconnects.
- Radios that go out of range stay in the list until the next scan reports a new
  list, which is acceptable for a short list.

# ADR-0041: Simulator settings

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

The built-in simulator always behaves like a current radio. Its other behaviour, such
as an old firmware or a missing radio module, exists only for the tests. To check
messages and layouts in the app, the source code had to be changed, as with the firmware
notice. The user also has no sample APRS packets for milestones 4.3 and 4.4.

## Decision

- **`SimulatorSettings`** (KV4PSimulator) holds band, firmware (current or too old),
  FreeDV modem, power switch, SA818 module and whether the radio answers. It builds the
  `Scenario`. `SimulatorRadio` makes the transport of each connection from it.
- **When it applies:** these settings take effect at the next connection and are locked
  while connected, as a radio does not change during a session.
- **What acts at once:** the received signal with a strength (S3, S9, S9+40, overload),
  losing the connection, and receiving an APRS packet of each type. The packets use
  placeholder data only.
- **Where it shows:** a section in the settings, only while the simulator is the chosen
  radio. It stays in release builds, as App Review and testers use the simulator.
- **Storage:** with the other settings on the device. Settings sync (milestone 3.8) must
  leave it out.
- **Dependency:** KV4PRadio now depends on KV4PSimulator, which the app already ships.

## Consequences

- Messages and notices can be tested without hardware or source changes.
- The simulator does not simulate the squelch level: any signal opens the squelch.
- A received signal always carries FreeDV voice frames, as the former switch did;
  analog, it sounds like a tone.

# ADR-0024: APRS messaging

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

The Android app sends APRS messages through java-aprs `AprsController`:
- `postMessage` numbers each message with a base-36 identifier seeded from the clock.
- `tick` (every 500 ms) retries until a matching `ack`/`rej` arrives (15, 30, 60, 120 and 240 s, then 30 s of grace) and acknowledges numbered messages to the local callsign one second after each received copy.

The radio side (`ServiceAprsCallbacks.submitRf`, `AprsRfFrequencyPolicy`) applies these rules:
- transmit only while receiving, not while transmitting or scanning;
- a reliable message stays on the frequency it was first sent on;
- every frame goes out with `COMMAND_HOST_TX_AX25` on the TX frequency with the current bandwidth and tone, inside the ham band.

## Decision

- `APRSController` in `KV4PAPRS` ports both halves of `AprsController` for RF:
  - the receive half (ADR-0023);
  - messaging, as described above.
- Its `transmit` closure answers synchronously like `submitRf`, with three outcomes: accepted, later and never.
- Vectors from java-aprs (`aprs-messaging.json`, `aprs-encoding.json`) pin:
  - identifiers, retry times and delivery states;
  - acknowledgements and the transmitted frames;
  - message payloads and AX.25 encoding.
- The view model implements the radio rules of `submitRf` and ticks every 500 ms. It sends as `APKVPA` via `WIDE1-1,WIDE2-1` and sanitises the text as `sendChatMessage` does: `|`, `~` and `{` become spaces, and an empty recipient becomes `BLN1CQ`.
- `RadioController.transmitAX25` sends one frame with `HOST_TX_AX25`. It refuses before HELLO, while transmitting or scanning, outside the band, and for oversized frames.
- Until the settings milestone, the callsign is kept in the app's user defaults. It is never part of the repository.

## Consequences

- Messages behave like on Android, including that a retry fails once the user has tuned away.
- Messages and their state live in memory like the feed (ADR-0023). Pending messages are not retried after a restart until APRS history is persisted.
- Notifications for messages to the user are not implemented yet.

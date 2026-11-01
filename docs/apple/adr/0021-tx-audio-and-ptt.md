# ADR-0021: TX audio and PTT

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

To transmit, the host sets `PTT_REQUESTED` (with `TX_ALLOWED`) and streams one
IMA ADPCM block per 249 samples as `HOST_TX_AUDIO`. The firmware releases PTT
by itself after 778 ms without TX audio and after 200 s, and bumps the sequence
so the host resynchronises ([protocol spec](../03-protocol-spec.md) §5, §9).

Android (`RadioAudioService.startPtt`, `endPtt`, `sendAudioToESP32`):

- `TX_ALLOWED` follows the TX frequency: only inside 144–148 MHz (VHF) or
  420–450 MHz (UHF), including half the bandwidth at both edges.
- It captures 16 kHz mono, applies the mic gain boost (×1, 1.5, 2, 2.5),
  encodes continuous ADPCM, and ends PTT after 180 s (runaway timer).
- RX audio is muted at PTT start and end, then fades in again.
- PTT is held, or toggled with "Sticky PTT"; a 250 ms debounce smooths touch
  releases.

## Decision

- `RadioController` owns the transmission. `startTransmitting()` checks ready,
  `TX_ALLOWED` and the injected `AudioInput`, starts the microphone, resets the
  `TXAudioEncoder` and the RX fade, and sets PTT. Microphone chunks are encoded
  into `HOST_TX_AUDIO` frames and queued in the same ordered, flow-controlled
  outbox as the desired states, so PTT always precedes its audio.
- The transmission ends on `stopTransmitting()`, the 180 s runaway timer, a
  device-released PTT (the adopted newer desired state no longer has PTT),
  disconnect or failure. Each transmission is numbered, so late microphone
  samples and timers of an earlier one are ignored.
- `TXBand` reproduces the Android rule with its default limits; the controller
  applies it on `tune` and on every in-sync device state, as Android does. The
  limits become settings later.
- `AudioInput` is the capture protocol; `AVAudioEngineInput` is the only adapter
  (coverage exclusion, [ADR-0011](0011-coverage-policy.md)). It asks for
  microphone access and converts the input device to 16 kHz mono with
  `AVAudioConverter`. The app has the audio-input entitlement and a microphone
  usage description.
- The view model implements hold and sticky PTT. The 250 ms release debounce is
  not adopted, because mouse and trackpad releases do not bounce.
- `RadioSnapshot.revision` lets the view model read the controller directly
  after a PTT action without ever going back to an older snapshot.

## Consequences

- No transmission without a TX frequency inside the band, a microphone and a
  ready radio. Hardware tests need a licence and an antenna or dummy load.
- If the link is slower than 64 blocks/s, TX audio queues up (latency grows)
  instead of being dropped; the firmware watchdog still ends TX when the link
  breaks.
- iOS needs an `AVAudioSession` in play-and-record mode (milestone 2.1).

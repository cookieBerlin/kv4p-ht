# ADR-0020: RX audio pipeline

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

The radio streams one IMA ADPCM block (249 samples, 15.5625 ms at 16 kHz) per
`RX_AUDIO` frame, also while the squelch is closed (the firmware mutes the
audio). Blocks arrive irregularly: BLE delivers them per connection interval,
USB in bursts. The output device runs at its own rate (usually 48 kHz) and asks
for samples on a real-time thread.

Android (`RadioAudioService.handleRxAudio`) decodes each block and writes it to
an `AudioTrack` in non-blocking mode, so the `AudioTrack` buffer acts as the
jitter buffer. After each start it also fades the volume in and keeps it muted
for about 60 blocks (≈ 0.9 s).

[02-architecture.md](../02-architecture.md) sketches an `AudioIO` protocol with
`play(_ samples:)`; on Apple platforms, pushing samples asynchronously to
AVAudioEngine adds a second buffer and latency.

## Considered options

1. **Push:** decode on the controller, schedule `AVAudioPCMBuffer`s on an
   `AVAudioPlayerNode`.
2. **Pull:** decode into a jitter buffer; an `AVAudioSourceNode` render
   callback pulls from it.

## Decision

Option 2.

- `KV4PAudio.JitterBuffer` (value type): playback starts once 4 blocks (≈ 62 ms)
  are buffered; an underrun plays silence and waits for the prefill again; an
  overflow drops the oldest samples, so the latency never exceeds 16 blocks
  (≈ 250 ms). Underruns and dropped samples are counted for diagnostics.
- `RXAudioPlayer` decodes `RX_AUDIO` blocks into the jitter buffer and renders
  floats with the volume applied. The render callback holds a `Mutex` only to
  copy samples and does not allocate.
- `RadioController` hands `RX_AUDIO` blocks to an injected `RXAudioSink` once
  `HELLO` was accepted, and resets it on disconnect and failure.
- The `AudioOutput` protocol replaces the `AudioIO` sketch for playback.
  `AVAudioEngineOutput` is the only adapter (coverage exclusion,
  [ADR-0011](0011-coverage-policy.md)); AVAudioEngine resamples 16 kHz to the
  device rate and restarts after a device change.
- The squelch is the firmware's: the app plays what it receives and shows the
  `SQUELCHED` flag.
- The Android fade-in is adopted unchanged: after each reset, every block moves
  the fade 2 % closer to 1, muted below 0.7 (59 blocks, ≈ 0.9 s). On hardware
  the radio sends a transient after it starts (after the USB reset: DC up to full
  scale for about one second, then decaying, while it reports the squelch
  closed); the fade hides it.
- The simulator streams RX audio at the firmware's cadence; a `Carrier` opens
  the squelch and plays a tone, so the whole chain is tested without hardware.

## Consequences

- Playback latency is about 60–250 ms plus the output device latency.
- The first ≈ 0.9 s after connecting are muted, as on Android.
- Clock drift between radio and Mac is absorbed by underruns and overflows
  (each one is a short click); resampling to compensate drift can follow if the
  hardware test shows it is audible.
- TX (milestone 1.8) adds capture to `AudioOutput`'s counterpart and mutes RX
  while transmitting.

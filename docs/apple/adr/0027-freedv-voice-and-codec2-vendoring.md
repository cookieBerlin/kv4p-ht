# ADR-0027: FreeDV 2400B voice and vendored Codec2

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

[ADR-0005](0005-codec2-freedv.md) chose to build Codec2 from C sources. It left
open how the sources get into the build and what the Swift wrapper is tested
against.

- **Android:** it uses `io.github.dkaukov:codec2-android` 0.1.1, a JNI wrapper
  around Codec2 1.2.0 that is pinned to upstream commit `06d4c11e`.
  - Its CMake build compiles only the mode 1300 sources and links with
    `--gc-sections`.
  - The JNI code calls `codec2_encode` and `codec2_decode` without changes.
- **Android app logic:** `RadioAudioService` holds the FreeDV logic:
  - TX: mic gain, then each pair of 16 kHz samples averaged to one 8 kHz sample
    (Java integer division), 320 samples per 7-byte frame;
  - RX: each decoded sample played twice, unless transmitting;
  - one Codec2 instance for both directions.
- **Codec2 itself:**
  - Its LSP codebooks are generated at build time.
  - Its decoder draws random phases for unvoiced sounds from one process-wide
    generator (`codec2_rand`). Decoded samples therefore depend on everything
    decoded before in the process, and concurrent decoders race on that
    generator.
- **Privacy check:** `pack.c` carries a third-party copyright notice with an
  e-mail address, which the personal data check
  ([CLAUDE.md](../../../CLAUDE.md) rule 6) would report.

## Decision

- **Vendoring:** `tools/codec2-vectors/generate.sh` vendors the pinned upstream
  commit unmodified into the `CCodec2` target. It copies the mode 1300 source
  list of codec2-android, the headers those files include, and the codebooks
  and `version.h` it generates as Codec2's CMake build does.
  - SwiftPM debug builds do not dead-strip, so it also vendors `newamp1.c`,
    `mbest.c` and their codebooks. The code paths of the disabled modes refer to
    them; mode 1300 never runs them.
  - The target defines `CODEC2_MODE_EN_DEFAULT=0` and `CODEC2_MODE_1300_EN=1`
    and silences warnings in the third-party code (`-w`).
- **Golden vectors:** the same script builds a reference program against the
  pristine checkout (`-O2`). It writes `codec2.json`: deterministic 8 kHz
  input, the frames, and the RMS of each decoded frame.
  - Frames must match exactly.
  - Decoded levels must be within 30 % or 20 (-64 dBFS), wider than the spread
    over 500 generator states.
  - `make vectors` runs the script and `make vectors-check` also checks the
    vendored sources.
  - The `vectors` job runs on macOS, because floating point on x86 (no FMA)
    gives different decoded samples.
- **Exemptions:** the personal data check skips only the paths in
  `privacy-exclusions.txt`, which is the vendored directory. The coverage gate
  excludes that directory ([ADR-0011](0011-coverage-policy.md)).
- **Swift API:** `KV4PDigital` exposes two types.
  - `Codec2` wraps one Codec2 instance. Calls of all instances run under one
    lock because of the shared generator.
  - `FreeDVVoice` ports the `RadioAudioService` steps above.
- **Radio controller:** `RadioController.setFreeDV` turns the `FREEDV_2400B`
  flag on only if the firmware reports the modem and Codec2 is available. The
  voice is created on first use.
  - RX: `RX_DIGITAL` frames go to the RX audio sink as samples, with the same
    fade-in as audio blocks.
  - TX: in FreeDV mode the microphone is sent as `HOST_TX_DIGITAL`.
- **Simulator:** it mirrors the firmware.
  - In FreeDV mode, a carrier's voice frames arrive every 40 ms instead of RX
    audio, and an analog signal keeps the squelch closed.
  - `HOST_TX_DIGITAL` feeds the TX watchdog.
  - `Scenario.freeDV` and `Carrier.freeDVVoice` let the app's simulator and
    `kv4p-sim-peripheral` demonstrate FreeDV.

## Consequences

- An upstream bump of codec2-android means changing `COMMIT`, then running
  `make vectors` and reviewing the vendored diff.
- The vendored code (about 50 files, 0.7 MB) stays byte-identical to upstream.
  Its licence is in `Packages/KV4PDigital/COPYING-codec2` (LGPL-2.1). An
  in-app licence list is part of the release candidate (1.13).
- The decoder's random phases make decoded audio reproducible only in level,
  not sample by sample.

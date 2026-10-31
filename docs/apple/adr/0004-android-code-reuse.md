# ADR-0004: Reuse of the Android code as reference and test oracle

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The Android app contains a tested implementation of the protocol
(`Protocol.java`), the audio codec (`ImaAdpcm.java`) and AX.25 (`javAX25/`).
It must not be modified. Re-implementing the same expectations by hand in Swift
tests would duplicate knowledge and let the two implementations drift.

`Protocol.java` depends only on `android.util.Log`, `androidx.annotation.NonNull`
and Lombok; `ImaAdpcm.java` and `javAX25/` are plain Java.

## Considered options

1. **Reference only** — read the Java code, write Swift tests by hand.
2. **Test oracle** — a separate JVM project compiles the Java sources by
   reference and generates golden test vectors (JSON) consumed by Swift tests.
3. **Run Java on Apple platforms** — not viable for an App Store app.

## Decision

Option 2. `tools/test-vectors/` is a standalone Gradle project whose source sets
point at the original files in `android-src/` (read-only). It provides minimal
stubs for `android.util.Log` and `androidx.annotation.NonNull` and runs Lombok as
annotation processor. It emits JSON vectors (KISS frames, vendor frames,
structures, ADPCM blocks, S-meter values, AX.25 packets). Where the firmware
native tests (`microcontroller-src/test/`) define cases, they are included too.

Vectors are committed. CI regenerates them and fails if they differ from the
committed ones, so upstream changes to the Android code surface immediately.

## Consequences

- Byte-level compatibility with Android is proven by tests, not by review.
- A JDK is required to regenerate vectors (CI and developers changing vectors).
- If an upstream refactoring moves the referenced files, only the source set
  paths in `tools/test-vectors/` need updating.

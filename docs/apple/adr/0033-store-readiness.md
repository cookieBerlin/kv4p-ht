# ADR-0033: App icon, privacy manifest and export compliance

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

App Store Connect rejects an upload, or asks at each upload, unless the app has:

- an app icon of 1024 × 1024 pixels without transparency;
- a privacy manifest (`PrivacyInfo.xcprivacy`). It declares the data the app
  sends off the device and the reasons for "required reason" APIs; the app uses
  `UserDefaults`.
- an answer on export compliance (`ITSAppUsesNonExemptEncryption`).

TestFlight on macOS also wants a proper app
icon. The project artwork has `artwork/app-icon.svg` (512 × 512).

## Decision

- **Icon:** `make icon` (`scripts/app-icon.sh`) renders the artwork to
  `App/KV4PHT/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
  - The image is 1024 × 1024. The script drops the alpha channel with a JPEG round
    trip at the highest quality; the artwork fills the square.
  - It needs only `sips`. The result is committed; one image serves iOS and macOS.
- **Privacy manifest** (`App/KV4PHT/PrivacyInfo.xcprivacy`):
  - no tracking;
  - collected data: precise location, user ID (the callsign) and other user
    content (APRS messages). All three are linked to the user and used for app
    functionality, as the FAQ describes: beacons and APRS-IS carry them, and
    APRS-IS is public.
  - `UserDefaults` is used with reason `CA92.1`, the app's own settings.
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` in the iOS Info.plist
  fragment. The app has no encryption of its own; links open in the browser.
- **Check:** `scripts/app-plist-check.sh`, run by `make app`, now also requires
  the icon, a compiled asset catalog, the manifest and the export key.

- **No resource bundles in the app:** the App Store export signs the app again but
  keeps the development signature of a nested SwiftPM resource bundle, and App
  Store Connect rejects the build (ITMS-90284). So packages embed their data in
  code. The ESP32 flasher stub is generated into `ESP32Stub.generated.swift`, and
  `scripts/app-plist-check.sh` fails on any nested bundle.

## Consequences

- **Artwork changes:** when the artwork changes, run `make icon` and commit the
  result.
- **Privacy labels:** the App Store privacy labels have to match the manifest.
  The maintainer confirms both when the first build is submitted.

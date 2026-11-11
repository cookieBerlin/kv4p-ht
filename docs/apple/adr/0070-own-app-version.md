# ADR-0070: The app's own version

- **Status:** Proposed
- **Date:** 2026-11-11

## Context

[ADR-0037](0037-version-and-build-id.md) took the app version from the Android `versionName`: 2.0.0.1 became 2.0.0.
The Apple app is an unofficial port with features of its own, so it is not the same release as the Android app. Its
first official release, in the App Store (milestone 99.1), is to be 1.0.0. The first TestFlight build was 0.1
(20261101.2216), before ADR-0037; no build with 2.0.0 was uploaded.

## Considered options

1. **Keep the Android version on TestFlight, 1.0.0 only in the App Store:** a version that goes down from 2.0.0 to
   1.0.0 confuses testers, and App Store Connect orders versions by number.
2. **An own version, below 1.0 until the App Store release:** says that the app is a beta, and leads up to 1.0.0.

## Decision

Option 2.

- **Version:** `Config/Version.xcconfig` holds `MARKETING_VERSION` and is edited by hand. TestFlight builds stay
  below 1.0, starting with 0.2.0 after 0.1; a build that brings something new raises it. The first App Store release
  is 1.0.0.
- **No link to Android:** `scripts/app-version.sh` goes, and with it the check in `make vectors-check` and the
  Android build file in `scripts/apple-paths.sh --oracle`.
- **Unchanged from ADR-0037:** the build ID is the upload time, the commit reaches the bundle as `KV4PCommit`, About
  shows both, and `scripts/app-plist-check.sh` requires a version of three numbers.
- **Tags:** each TestFlight build gets a tag `apple-v<version>-<build>` on the commit it was built from, such as
  `apple-v0.1-20261101.2216`, and a GitHub pre-release. The prefix keeps them apart from the Android tags, such as
  `v2.0.0.1`.

## Consequences

- A version bump of the Android app no longer touches the Apple app.
- Raising the version is a step of a release, next to the build ID that `make testflight` sets.
- This supersedes the version part of ADR-0037; its build ID, commit and display stay.

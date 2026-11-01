# ADR-0037: App version, build ID and commit

- **Status:** Proposed
- **Date:** 2026-11-02

## Context

The Apple app should carry the same version as the Android app, and a build should
be traceable to its commit. The Android `versionName` has four numbers, such as
2.0.0.1. App Store Connect accepts at most three in `CFBundleShortVersionString`,
and only numbers in `CFBundleVersion`, so that field cannot hold a commit hash.

## Decision

- **Version:** the first three numbers of the Android `versionName`, so 2.0.0.1
  becomes 2.0.0. `scripts/app-version.sh` generates `Config/Version.xcconfig` from
  `android-src/KV4PHT/app/build.gradle`. `make vectors` runs it, and `make
  vectors-check` fails if the committed file differs. CI also runs this check when
  the Android file changes (`scripts/apple-paths.sh --oracle`).
- **Build ID:** stays the upload time, as in [ADR-0035](0035-testflight.md).
- **Commit:** `scripts/release-testflight.sh` passes the short hash as the build
  setting `KV4P_COMMIT`, with `-dirty` for uncommitted changes. It reaches the
  bundle as `KV4PCommit`. A local build from Xcode leaves it empty.
- **Display:** About shows, for example, `Version 2.0.0 (20261102.1200, abc1234)`.
- **Check:** `scripts/app-plist-check.sh` requires a version of three numbers and,
  for an archive, the expected commit.

## Consequences

- A change of the fourth Android number alone does not change the Apple version.
  App Store Connect then needs only a new build ID, which every upload has.
- An Android version bump needs `make vectors` and a commit, like the test vectors.
- A file generated from Android stays in the repository, so a plain Xcode build
  needs no script.

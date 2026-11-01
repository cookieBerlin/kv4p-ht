# ADR-0035: TestFlight distribution

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

Milestone 2.5 brings the app to testers through TestFlight
([roadmap](../04-roadmap.md)), on iPhone, iPad and Mac. TestFlight needs an App
Store signature, an
app record in App Store Connect and a new build number for every upload. The team
ID and the account must stay out of the repository.

## Decision

- **Entry point:** `make testflight` runs `scripts/release-testflight.sh`. For iOS
  and macOS, or the platforms named in `PLATFORMS`, it does the following:
  1. archive the app (Release) with automatic signing;
  2. check the bundle with `scripts/app-plist-check.sh`;
  3. upload the build with `xcodebuild -exportArchive`. The export options are
     generated in `.build/testflight`, because they hold the team ID.
- **One app record:** iOS and macOS share the bundle identifier, so they are two
  platforms of one record in App Store Connect.
- **Only way to testers:** there is no build outside App Store Connect
  ([ADR-0036](0036-no-distribution-outside-app-store.md)).
- **Signing data:** `TEAM_ID` comes from the environment. The account comes from
  Xcode. `-allowProvisioningUpdates` lets Xcode create the certificate and the
  provisioning profile.
- **Build number:** `BUILD_NUMBER`, by default the UTC time as `YYYYMMDD.HHMM`, so
  that every upload gets a higher number without a commit. `MARKETING_VERSION`
  stays in `Config/Base.xcconfig`.
- **Dry run:** `DRY_RUN=1` archives without signing and checks the bundles. `make
  app`, and so CI, runs it in every pull request.
- **What to Test:** `scripts/what-to-test.sh` generates the text per platform from
  [`docs/apple/hardware-tests.md`](../hardware-tests.md), and `make testflight`
  writes it to `.build/testflight/WhatToTest-<platform>.txt`. The maintainer pastes
  it into App Store Connect, because the upload cannot set this field. The App
  Store Connect API could, but it needs a key and more code, which is not worth it
  for now.
- **App Review:** the notes for reviewers live in
  [`docs/apple/app-review-notes.md`](../app-review-notes.md).

## Consequences

- **One-time setup by the maintainer:**
  1. Sign in to the Apple Developer account in Xcode → Settings → Accounts.
  2. Create the app in App Store Connect with the bundle identifier from
     `Config/Base.xcconfig`, and add the macOS platform to it.
  3. Run `TEAM_ID=<team> make testflight`.
- **Not automated:** CI does not sign or upload, because the account is not in CI.
  Inviting testers and submitting a build for review stay manual steps in App
  Store Connect.
- **External testers need a review:** Apple reviews the first build for external
  testers. Internal testers can install a build without that review. The review
  notes explain how to test with the built-in simulator.

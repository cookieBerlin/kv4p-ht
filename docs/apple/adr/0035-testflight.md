# ADR-0035: TestFlight distribution

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

Milestone 2.5 brings the iOS and iPadOS app to testers through TestFlight
([ADR-0010](0010-distribution.md)). TestFlight needs an App Store signature, an
app record in App Store Connect and a new build number for every upload. The team
ID and the account must stay out of the repository, as for the macOS release
([ADR-0034](0034-macos-release.md)).

## Decision

- **Entry point:** `make testflight` runs `scripts/release-ios.sh`:
  1. archive the app (Release) with automatic signing;
  2. check the bundle with `scripts/app-plist-check.sh`;
  3. generate the export options in `.build/testflight`, because they hold the
     team ID, and upload the build with `xcodebuild -exportArchive`.
- **Signing data:** `TEAM_ID` comes from the environment. The account comes from
  Xcode. `-allowProvisioningUpdates` lets Xcode create the certificate and the
  provisioning profile.
- **Build number:** `BUILD_NUMBER`, by default the UTC time as `YYYYMMDD.HHMM`, so
  that every upload gets a higher number without a commit. `MARKETING_VERSION`
  stays in `Config/Base.xcconfig`.
- **Dry run:** `DRY_RUN=1` archives without signing and checks the bundle. `make
  app`, and so CI, runs it in every pull request.
- **App Review:** the notes for reviewers live in
  [`docs/apple/app-review-notes.md`](../app-review-notes.md).

## Consequences

- **One-time setup by the maintainer:**
  1. Sign in to the Apple Developer account in Xcode → Settings → Accounts.
  2. Create the app in App Store Connect with the bundle identifier from
     `Config/Base.xcconfig`.
  3. Run `TEAM_ID=<team> make testflight`.
- **Not automated:** CI does not sign or upload, because the account is not in CI.
  Inviting testers and submitting a build for review stay manual steps in App
  Store Connect.
- **External testers need a review:** Apple reviews the first build for external
  testers. Internal testers can install a build without that review. The review
  notes explain how to test with the built-in simulator.

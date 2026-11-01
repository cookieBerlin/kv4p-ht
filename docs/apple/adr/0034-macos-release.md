# ADR-0034: Signed and notarized macOS release

- **Status:** Proposed
- **Date:** 2026-11-01

## Context

Milestone 1.13 asks for a signed and notarized macOS build
([ADR-0010](0010-distribution.md)). Outside the Mac App Store, Gatekeeper only
opens an app without warnings when it meets three conditions:

- it is signed with a **Developer ID Application** certificate;
- it uses the hardened runtime;
- it is notarized by Apple, with the ticket stapled.

The certificate and the notary credentials belong to the maintainer's paid Apple
Developer account. Under the project rules they must not appear in the
repository.

## Decision

- **Entry point:** `make release` runs `scripts/release-macos.sh`:
  1. archive the app (Release) and sign it with `SIGN_IDENTITY`, by default
     *Developer ID Application*, with the hardened runtime and a secure timestamp;
  2. verify the signature and the runtime flag;
  3. pack it into `.build/release/kv4p-HT-<version>-<build>.dmg`, with an
     *Applications* link;
  4. sign the DMG, submit it with `notarytool`, staple it and check it with
     `spctl`.
- **Signing data from the environment only:**
  - `TEAM_ID`: the team ID;
  - `NOTARY_PROFILE`: the name of a keychain profile the maintainer creates once
    with `xcrun notarytool store-credentials`;
  - without `NOTARY_PROFILE`, the DMG is signed but not notarized.

  The certificate stays in the keychain, the password in the notary profile.
- **Dry run:** `SIGN_IDENTITY=-` signs ad hoc and skips notarization. `make app`,
  and so CI, runs this dry run, which catches problems of the Release build and
  of the packaging in every pull request.
- **Versions:** they come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
  in `Config/Base.xcconfig`.

## Consequences

- **One-time setup by the maintainer:**
  1. In Xcode → Settings → Accounts → Manage Certificates, create a *Developer
     ID Application* certificate.
  2. Run `xcrun notarytool store-credentials <profile> --apple-id <id>
     --team-id <team>` with an app-specific password.
  3. Run `TEAM_ID=<team> NOTARY_PROFILE=<profile> make release`.
- **Not automated:** CI does not sign, because the certificate is not in CI.
  Publishing the DMG, for example as a GitHub release, is a manual step.
- **Next:** TestFlight (milestone 2.5) uses the same account with an *Apple
  Distribution* certificate and an App Store Connect record. It is a separate
  step.

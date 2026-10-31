# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## Repository overview

kv4p HT is an open source handheld ham radio: an ESP32-based board with an SA818
RF module, controlled by a host app over USB serial, Bluetooth Classic or BLE.

| Path | Content |
|---|---|
| `microcontroller-src/` | ESP32 firmware (PlatformIO / Arduino) |
| `android-src/KV4PHT/` | Android app (Java, Gradle) |
| `apple-src/` | Apple app for macOS, iOS and iPadOS (Swift, SwiftUI) — see `apple-src/CLAUDE.md` |
| `docs/apple/` | Apple port planning, ADRs, user manual and FAQ |
| `tools/test-vectors/` | Golden test vector generator built on the unmodified Android code |
| `website-src/`, `pcb/`, `3d-print-case/`, `artwork/` | Website, hardware, case, artwork |

## Rules for Apple development

These rules apply to all work on the Apple port (`apple-src/`, `docs/apple/`,
`tools/test-vectors/`, Apple CI workflows).

1. **Android and firmware code are read-only.** Do not modify anything in
   `android-src/` or `microcontroller-src/`. Read it, reference it, and execute it
   (e.g. as a test oracle), but never change it. Exception: changes that are
   explicitly requested and submitted as a separate upstream contribution.
2. **Test-driven development.** Red → Green → Refactor. Write a failing test first,
   then the minimum code to pass it, then refactor.
3. **100 % test coverage** for all Swift packages, enforced by CI. Exclusions are
   only allowed as defined in [ADR-0011](docs/apple/adr/0011-coverage-policy.md).
4. **DRY.** Every piece of knowledge has exactly one authoritative place:
   protocol constants live in one Swift module, cross-platform behaviour is pinned
   by golden test vectors instead of duplicated expectations, and local commands
   mirror CI commands through a single entry point.
5. **English only** for code, comments, documentation, ADRs, commit messages and
   pull requests.
6. **No personal data in the repository.** No real names, e-mail addresses, private
   domains, phone numbers, locations or real callsigns — not in code, test data,
   docs or commit metadata. Use placeholders such as `N0CALL` and documentation
   IP ranges/domains (`example.com`). Exception: the fork maintainer's GitHub
   display name as author of merge commits created by GitHub (e-mail addresses
   stay GitHub noreply addresses).
7. **Architecture decisions require an ADR** in `docs/apple/adr/` (see
   [ADR-0001](docs/apple/adr/0001-record-architecture-decisions.md)). Accepted ADRs
   are immutable; supersede them with a new ADR.
8. **Keep user docs current.** Every user-visible change updates
   [`docs/apple/manual.md`](docs/apple/manual.md) and/or
   [`docs/apple/faq.md`](docs/apple/faq.md) in the same pull request.

## Commits and branches

- Commit every meaningful step separately (one logical change per commit). In TDD,
  the test and the implementation may be separate commits.
- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `test:`, `refactor:`, `docs:`, `ci:`, `build:`, `chore:`,
  optionally scoped, e.g. `feat(protocol): parse HELLO frame`.
- Remotes: `upstream` is the original project, `origin` is the fork.
  Keep `main` in sync with `upstream/main`; work on feature branches
  (`apple/<topic>`) and merge via pull request.
- Pull requests must pass the Apple CI gate (tests, 100 % coverage, lint,
  test vector consistency, personal data check) before merging.

## Key references

- Apple planning index: [`docs/apple/README.md`](docs/apple/README.md)
- Host ↔ device protocol: [`docs/apple/03-protocol-spec.md`](docs/apple/03-protocol-spec.md)
- Firmware protocol source of truth: `microcontroller-src/kv4p_ht_esp32_wroom_32/protocol.h`
- Android reference implementation: `android-src/KV4PHT/app/src/main/java/com/vagell/kv4pht/radio/`

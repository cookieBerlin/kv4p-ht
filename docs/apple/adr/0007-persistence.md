# ADR-0007: Persistence

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The app stores channel memories and groups, settings and APRS history (Android:
Room with 8 schema versions). Minimum OS is 26 ([ADR-0008](0008-minimum-os-versions.md)).
Persistence must be testable without a device, in memory.

## Considered options

1. **SwiftData** — native, integrates with SwiftUI, in-memory containers for tests,
   optional iCloud sync later.
2. **GRDB (SQLite)** — explicit SQL and migrations, very predictable; extra dependency.
3. **Core Data** — mature but verbose; superseded in practice by SwiftData.

## Decision

Option 1, behind repository protocols in `KV4PPersistence` (e.g.
`MemoryRepository`, `SettingsRepository`, `AprsHistoryRepository`). The rest of
the app depends only on the protocols; tests use in-memory containers or fakes.

## Consequences

- Easy SwiftUI integration; schema migrations via `VersionedSchema`.
- If SwiftData limitations appear, the repository protocols allow switching to
  GRDB without touching callers (new ADR).
- Importing Android memories (export/import format) is a separate future topic.

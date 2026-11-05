# ADR-0052: Memory sync

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

Memories and groups should reach the user's other devices. They can be many, and they
change together when sorted or imported, so the key-value store of
[ADR-0051](0051-settings-sync.md) does not fit. The store is SwiftData
([ADR-0007](0007-persistence.md)), which can sync through CloudKit by itself. `CKSyncEngine`
would mean writing and testing the sync ourselves.

## Decision

- **SwiftData with CloudKit,** in the user's private database, with a container named after
  the bundle identifier. Where the app has no entitlement for it, or the user has no
  iCloud, the same store simply stays on the device.
- **The model follows CloudKit's rules:** nothing unique, and every field optional or with
  a default. A test pins this, as a violation shows only on a device: the store would not
  open. The app then falls back to a store without sync.
- **The last change of a field wins,** as CloudKit decides it. Other than the first plan for
  this milestone said, a concurrent change of the same field is not kept twice.
- **A global id** identifies a memory on every device. A store of an earlier version gets
  them when it is first read.
- **The number of a memory belongs to the device.** It goes to the radio and the screens, and
  two devices can give the same number to different memories. The repository hands out
  numbers per run and keeps the stored one if it is free, so that it stays between launches.
- **Copies are merged only if they are alike in everything,** with the lowest global id
  staying, so that each device comes to the same result. Two devices with the same memories
  before their first sync would otherwise hold each twice. Memories with one name and
  frequency that differ in a tone both stay: the plan was to merge those as well, but
  that would silently lose one.
- **The order syncs as the position of each memory.** Two memories on one position stand by
  global id, so in the same order on each device.
- **Each step reads through a new context,** and the view model reloads when iCloud reports
  a change.
- **One switch:** *iCloud sync* also covers memories. As SwiftData sets this up when the
  store opens, it takes effect for memories at the next start.
- **Entitlements and background mode:** the iCloud entitlements gain the container and push
  notifications, and iOS gains the background mode `remote-notification`, by which CloudKit
  reports changes.

## Consequences

- TestFlight and App Store builds use CloudKit's production environment. The schema must be
  deployed to it in the CloudKit Console before such a build can sync, and after that it can
  only grow, so fields of this model cannot be removed or renamed.
- The real sync can only be tested on devices (hardware test HW-31); the tests here cover
  everything around it with two repositories on one store.
- Two devices that sort at the same moment can mix their orders, by the last change of each
  position. Nothing is lost, and sorting again repairs it.
- A device deleting a memory that another one just edited loses that edit.

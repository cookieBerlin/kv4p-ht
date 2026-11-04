# ADR-0042: Memory editor

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

Memories are listed by their id, so they keep the order in which they were added, and
groups are sorted by name. The main screen can only edit and delete one memory at a
time. A RepeaterBook import adds many memories at once, and importing a file again adds
them all again. Android has no way to sort them either.

## Decision

- **Main screen for use, editor for tidying up:** **Manage memories…** in the settings
  opens the editor. **+** and ⋯ stay on the main screen, to store a frequency on the way.
- **Two levels:** the groups, and the memories of one group. A row is dragged inside its
  level, which is more reliable in long lists on a phone than dragging across groups.
  Moving to another group goes through a menu, also for several memories.
- **One order, in a new `position`:** the `id` stays as it is, since it also goes to the
  radio. There is no table of groups: a group stands where its first memory is, and its
  memories are shown next to each other. A group therefore exists as long as it has a
  memory, and "New group" goes straight to the form of its first memory.
- **Migration:** a store of an earlier version has position 0. On first reading, groups
  become alphabetical as in the former picker, no group comes last, and each group stays
  in the order it was added.
- **Group as a choice:** the form offers the existing groups and "New group…" instead of
  free text, so that a typing error adds no group.
- **Form fields:** every field shows its label, also on iOS. The numbers are kept as
  typed and read on Save, as a field with a number format reports its value only when it
  loses focus. Save stays off while the name, frequency or offset is not valid.
- **Import assistant:** it shows what it would add before anything is stored. A repeater
  counts as present if the target group has the same name and frequency. The radio must
  be connected, as only it knows its frequency range.
- **Deleting asks first,** everywhere, as a mistyped ⋯ menu is easy on a phone.

## Consequences

- The main list shows "All" group by group, without headings, and the scan follows it.
- The first start after the update changes the order of "All" if groups were mixed.
- Moving a memory to another group puts it at the end of that group.

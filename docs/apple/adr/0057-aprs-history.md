# ADR-0057: APRS history

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

The APRS list lived in memory and started empty at each start. Milestone 4.6 asks for packets that
stay, on this device only. It has three parts, each with its own pull request: storing and deleting
(4.6a), filtering, searching and exporting (4.6b), and messages (4.6c). This ADR covers 4.6a, and the
others add to it.

## Decision

- **A SwiftData store of its own, which never syncs,** apart from the memories of
  [ADR-0052](0052-memory-sync.md), with the fields to look for a packet by and the event as encoded
  data. A new field of an event needs no migration of the store.
- **The controller stays as the Android code has it.** It gains a way to take back stored events
  and to let events go. The golden test vectors do not change.
- **The packet as a line of text stays with each event,** which the export of 4.6b uses.
- **What is stored:** all packets of the list, on by default, for 30 days. It can be 1, 7, 30 days or
  without limit. Packets only from the internet are not stored by default, as a feed around the
  user brings many, and a switch stores them. Messages to or from this station always are, so that
  none is lost and the conversations of 4.7 have no gaps. These settings stay on the device.
- **Memory holds the newest 500.** The controller goes through its list for each packet, so an
  unlimited history must not be in there. **Load more** at the end brings older ones to the screen.
  What is not stored stays in the list until it leaves memory or the app ends, as before.
- **A message sent but not acknowledged before a restart is not sent again,** and shows as not
  delivered.
- **Writes happen one after another,** away from the screen, and only for what changed. A packet that
  arrives before the stored ones are back waits, and gets a new id, so that ids never repeat.
- **Old packets go at the start, every hour and when the time is shortened.**
- **Switching off stores nothing more, and asks whether to delete what is stored.** A single packet
  goes through a button on its row, as a sideways swipe changes the page on a phone, and without a
  question. Deleting all asks first.

## Consequences

- A stored event that cannot be read any more, as by a later version, stays out of the list, and
  goes with its time.
- The store can grow large with no limit and with packets from the internet; the settings show how
  many there are.
- How many packets a real feed brings, and whether 500 is right, shows only in use.

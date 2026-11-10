# ADR-0065: DARC repeater list import and memory kinds

- **Status:** Proposed
- **Date:** 2026-11-10

## Context

German-speaking users find their repeaters in the DARC repeater lists (relaislisten.darc.de) rather than on
RepeaterBook. The lists offer a CSV export, but no licence for an app to download them. A memory knew only a name,
frequency, offset, tones and a group. It could not tell a repeater from a simplex frequency, and it had no room for
what the lists say about an entry: a comment and a position, which the map of milestone 5.2 needs.

Facts that bound the choice:

- **Export:** `;`-separated, a decimal comma, a header `Call;QRG;Input;Locator;Info;Breite;Länge;CTCSS;Mode/Node`
  and a last column named after the locator the list was made for. *QRG* is the repeater's output, *Input* its
  input, empty for simplex, or `Beacon` for a beacon. Positions are in degrees and minutes (`52°31'N`). The CTCSS
  tone reads `88,5Hz`. *Mode/Node* may be empty. The file may come in UTF-8 or Windows-1252, and the export
  misspells a column name now and then: *Länge* has come with a Cyrillic letter.
- **Modules:** a kv4p HT has a VHF module (134–174 MHz) or a UHF one (400–480 MHz), and the firmware gives these
  ranges. Lists hold repeaters of both bands, and a user may have radios of both kinds.
- **Sync:** memories sync through CloudKit ([ADR-0052](0052-memory-sync.md)). Its schema can only grow, every field
  needs a default, and every device must migrate a memory the same way.
- **RepeaterBook:** its import follows the Android app ([ADR-0022](0022-memories-and-scan.md)) and should stay
  as it is.

## Decision

- **Kinds:** a memory is a *frequency*, a *repeater* or a *beacon*, an automatic station that only sends a
  beacon. New memories are frequencies. The kind does not change with the offset.
- **New fields:** a comment (empty by default) and a position (latitude and longitude in decimal degrees, north
  and east positive, both or neither).
- **Migration:** the kind is stored as text, empty in a store of an earlier version. On reading, a memory with an
  offset becomes a repeater and any other a frequency, and the result is stored. As each device derives it from
  the same offset, the devices agree.
- **Two imports:** **Import from RepeaterBook** and **Import from DARC** are separate buttons and assistants. Each
  reads only its own format. They share reading the file, the preview and the check for duplicates.
- **Reading the file:** UTF-8, or else Windows-1252. Foundation refuses the five bytes Windows-1252 leaves
  unassigned, so each byte is decoded on its own, and a byte order mark is dropped.
- **DARC columns:**
  - The list is recognised by `Call;QRG;Input` at its start. Columns are found by their place, not their name.
  - *Call* is the name, *QRG* the frequency, and *Info* the comment.
  - *Input* minus *QRG* is the offset in whole kHz, also across bands. An empty *Input* is simplex. `Beacon`
    makes a beacon without an offset.
  - *CTCSS* is the TX tone. *Breite* and *Länge* become decimal degrees, south and west negative.
  - Every entry is a repeater, except beacons.
- **Modes:** only FM is imported. An entry without a mode counts as FM, as does one that names FM among others
  (`FM/DMR`). `C4FM` is not FM.
- **Both bands, without a radio:** the ranges of the modules are stated once, with the module type in
  `KV4PProtocol`. An import needs no connected radio. It takes every entry within 2 m and 70 cm, and leaves out
  the rest.
- **Completing:** an entry the group already has, by name and frequency, completes that memory. It adds a missing
  comment, and a position where the memory has none or only half of one. Anything the user set stays, as do the
  kind, offset and tones.
- **Preview:** it names the repeaters and beacons to import and the memories to complete. It also says what it
  leaves out and why: another mode, outside 2 m and 70 cm, already in the group.
- **Access tone:** the DARC assistant offers *Set the access tone*, on by default with 1750 Hz for 3 s, as most
  German repeaters need. It applies to new repeaters, not to beacons or completed memories.
- **Group:** both assistants ask *Add to a group*, on by default. When it is on, the user picks an existing group
  or a new one, proposed by the file name. When it is off, the memories go without a group.
- **RepeaterBook:** it imports as before, also all modes, with the name `Call • Location`. Its memories become
  repeaters. Its exports have no position, and the location is in the name already, so the comment stays empty.
- **What the radio receives:** with a radio connected, the list shows only the memories its module receives. A
  footer says how many it hides, and for which band. The scan takes only what the list shows, and a hidden memory
  is not tuned to. Before a radio is known, the list shows everything. The memory editor in the settings always
  shows all memories. The form takes a frequency of either band, and notes when the connected radio cannot receive
  it.
- **List:** a repeater and a beacon show a symbol (`antenna.radiowaves.left.and.right`,
  `dot.radiowaves.up.forward`), and VoiceOver reads the kind with the row. A frequency keeps the room, so that the
  names line up. The comment shows in one line below the frequency, except with the accessibility text sizes.
- **Form:** it edits the kind, the comment and the position. The position is in decimal degrees to five decimals,
  with the user's decimal separator. A coordinate field takes a minus at its start, and on iPhone and iPad it
  brings a keyboard that has one.
- **Transmitting:** a beacon is not blocked. The kind marks a memory; it does not limit it.

## Consequences

- A memory out of the radio's range is no longer set to the nearest limit, as in the Android app. It is hidden
  instead. The desired state and its golden vectors stay as they are.
- The CloudKit schema grows by four fields. It must be deployed to production before a TestFlight build can sync
  them. An older version of the app keeps syncing and leaves the new fields alone.
- The map of milestone 5.2 can show memories with a position.
- The DARC import has no Android oracle. It is pinned by tests with placeholder data, including an invented locator.
- A position in degrees and minutes is only as exact as a minute, about 1.8 km.

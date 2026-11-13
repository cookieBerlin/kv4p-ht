# ADR-0074: The header on the memories only

- **Status:** Proposed
- **Date:** 2026-11-13

## Context

ADR-0040 put the header with the frequency, the squelch state and the S-meter above every page but the settings, and
above both sides of a wide window. The header serves the memories: a memory tunes the radio, and the frequency shows
what it tuned. On the packets, the chats and the map it takes room that those pages need more, above all the map on a
phone. The Android app is no model here; the GUI may differ from it (ADR-0040 took over its structure only).

## Decision

- **A phone, and a narrow iPad window:** only the memories page shows the header. It still stands outside the pages,
  so it stays in place while they move, and shows as soon as the memories page is the one shown. The packets, the
  chats and the map reach to the top, with no line in place of the header. The status and the page bar at the bottom
  stay as they are.
- **A wide window, on the iPad and the Mac:** the header, the memories, PTT and the status form one column on the
  left, of a fixed width of 400 points. Beside it, the packets, the chats or the map run from the top to the bottom.
  - A fixed width rather than a divider to drag: the column needs no more, and the other side takes all the rest.
  - The Mac's window is at least 720 points wide, for the column and the side beside it.
- **Without APRS and the map,** the column takes the whole width, as before.
- PTT stays where it was: on a phone on the memories page, in a wide window below the memories.

## Consequences

- A phone shows the frequency on the memories page only. The status at the bottom still says whether the radio is
  connected, and the squelch state is heard.
- In a wide window, the packets, the chats and the map are taller, and their switch stands level with the header.
- The UI test `HeaderPlacementTests` checks both layouts.

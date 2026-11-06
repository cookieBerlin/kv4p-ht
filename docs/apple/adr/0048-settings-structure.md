# ADR-0048: Settings structure

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

The settings have grown into one long screen with a dozen sections. Settings that belong
together, such as the access tone and the other transmit settings, are far apart, and the
sync of settings and memories (milestones 3.8 and 3.9) will add more. On the Mac the
explanations appear only as tooltips, which nobody finds without hovering over a control.

## Decision

- **An overview with pages:** Station, Radio, Transmit, Audio, APRS, Memories, Simulator and,
  on iPhone and iPad, About. A page without anything to set is not offered:
  the simulator only while it is the chosen radio, Audio only where it has a setting.
- **The usual form of each platform:** a sidebar in the Mac's settings window, a list that
  leads to the pages on iPhone and iPad.
- **Memories lead directly to the editor,** not to a button that opens it in a sheet. Its
  *Done* button goes.
- **The frequency limits are on the Radio page,** always open.
- **Explanations are visible on every platform.** `explained` puts the text below the row
  on the Mac as well, and has no tooltip any more, as it would say the same.
- **The simulator actions stay visible without a connection,** greyed out and with a note
  that they need one, so that one can see that they exist.
- **No other function changes:** every setting keeps its model property, and its conditions.

## Consequences

- A setting takes one step more to reach, and the main screen stays the place for what
  is used on air.
- The pages are short and leave room for what comes, such as the iCloud switch on the
  Station page.
- Rows on the Mac get taller because of the visible texts.
- The manual names the page of each setting.

# ADR-0075: Connect where PTT stands

- **Status:** Proposed
- **Date:** 2026-11-13

## Context

Since ADR-0071, iPhone and iPad choose and connect the radio in the settings; without a connection, the main screen
shows the status with *Connect in Settings* in place of PTT. The Mac kept a row with the radio and *Connect* at the
top of its header, which also held *Disconnect* while connected. Connecting is the first thing to do, and PTT has
nothing to do before it, so its place is free for it. A connected radio needs no choice of radio on the main screen,
and ending the connection is rare. The Mac had no keys for the connection or for transmitting.

## Decision

- **Without a connection, the connection stands where PTT does:** on the memories page of a phone, and in the left
  column of a wide window (ADR-0074). It shows the status or why the last connection failed, the choice of radio and
  *Connect*; while connecting, *Cancel*. Once connected, PTT alone stands there.
  - The action follows the state, in `ConnectionAction` in KV4PRadio: *Connect* while disconnected or failed,
    *Cancel* while connecting or waiting for `HELLO`, *Disconnect* while ready. The settings use the same button.
  - The other pages of a phone show the status only, as the memories page is a swipe away.
- **Disconnect:** in the settings, under *Connection*; on the Mac under *Radio*. The Mac and a wide iPad window also
  show a small *Disconnect* at the top right of the header while connected, where the line of the memory's name has
  room. A phone, and a narrow iPad window, keep it in the settings.
- **The Mac's header** loses its row with the radio and *Connect*.
- **The Mac's keys:**
  - A *Radio* menu with *Connect*, *Cancel* or *Disconnect* on ⌘K. Return still presses *Connect*, the default
    button of the window.
  - The space bar transmits while it is held, as PTT does; ⌥ and the space bar send the access tone. A menu tells
    only that a key went down, not that it came up, so the window watches these keys itself, through a local monitor
    of AppKit's key events; the menu names them, greyed out.
  - Only in the main window, and never while a text field takes the typing, so that the space bar still types a
    space. A key that repeats while held counts once. Other modifiers leave the space bar alone.
  - Whether a key may transmit is what its button allows, in `canPress` in KV4PRadio, which the buttons use as well.
  - The release of a key held while another window or app comes to the front never reaches the app, so the
    transmission ends then, as it does when the layout changes under a held button (ADR-0071).
  - Sticky PTT applies to the space bar as to the button: each press starts or ends the transmission.

## Consequences

- The choice of radio is no longer on screen while connected; it is in the settings, and the connection panel
  shows it again once the connection ends.
- With full keyboard access on the Mac, the space bar transmits rather than pressing the focused button, while the
  radio is ready. Without a radio, it presses the button as usual.
- The UI test `ConnectionTests` now runs on all three platforms; holding a key cannot be tested by XCTest, so
  the key monitor is checked by hand, and its rules are tested in KV4PRadio.

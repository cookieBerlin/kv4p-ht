# ADR-0054: APRS symbols and devices

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

The list showed `_3` as the comment of some packets. The roadmap assumed a wrong symbol.
Sending and decoding the app's own beacons with all its symbols shows no such text. The cause
is another one: Mic-E radios mark themselves by bytes at the start and end of the comment, and
`_3` is the mark of a Yaesu FT5D. The list also did not show any received symbol.

## Decision

- **`comment` stays as it is,** as the golden test vectors from the Android code pin it. A
  separate field gives the comment to show, without the mark, and another the name of the radio.
- **Only Mic-E packets are read this way,** and only known marks count, so that a normal comment
  ending in `_3` stays as it is, as does an unknown mark.
- **Symbols are kept with the event,** with a table of their meanings. An overlay is a symbol of
  the alternate table with a mark, which a compressed position writes as `a` to `j`.
- **Every known symbol has an icon, by this order:** a Unicode character, also if it only
  roughly fits; then a system image; drawing one remains the last way out, and none is needed
  so far. The name next to it says exactly what is meant. The list becomes colourful, as APRS
  maps have always been.
- **The characters come from the system's fonts when shown,** so the app contains no images of
  them.
- **Details are on the icon:** a tooltip on the Mac, holding it on iPhone and iPad. On the text of
  a row, holding means selecting.

## Consequences

- The meanings come from the aprs.fi APRS symbols index (CC BY-SA 4.0), and the radios from the
  APRS device identification database (CC BY-SA 2.0). About names them. Both ask for a mention
  and for changes to stay under their licence, while the app is under GPL 3.0. How the data
  tables fit with that should be checked before an App Store release.
- New radios need an update of the table; until then, their mark stays in the comment.
- Colours and shapes of the characters can change a little with the system.

## Sources

All retrieved on 2026-11-05.

| Used for | Source | Licence |
|---|---|---|
| Meanings of the symbols (`APRSSymbolTable.swift`) | [aprs.fi APRS symbols index](https://github.com/hessu/aprs-symbol-index), `generated/symbols.dense.json` | CC BY-SA 4.0 |
| Names of the radios (`MicEDevice.swift`) | [APRS device identification database](https://github.com/aprsorg/aprs-deviceid), `tocalls.yaml`, sections `mice` and `micelegacy` | CC BY-SA 2.0 |
| Check of the marks, such as `_3` | [Mic-E types of aprs.org](https://www.aprs.org/aprs12/mic-e-types.txt) | Only read for comparison, nothing copied |
| Icons | Unicode characters and system images, chosen for this app | None taken over: the system's fonts draw them |

The symbol table was written once by a script outside this repository, and the list of radios by hand;
there is no generator here. To update them, compare with these sources. A test checks that every symbol has a name and an icon.

# ADR-0080: The page bar of an iPhone stands at the side in landscape

- **Status:** Proposed
- **Date:** 2026-11-18
- **Amends:** [ADR-0071](0071-iphone-duo.md) (where the page bar stands)

## Context

An iPhone in landscape shows the compact layout: it is compact in width, like in
portrait ([ADR-0032](0032-ios-layouts.md)). Its height is short, 390 pt on a
6.1-inch iPhone. The memories page stacks the header, the group row, the list, the
notice of hidden memories, **Push to talk** and the page bar. Together they took about
50 pt more than the height. The frequency was cut off at the top and the page bar at
the bottom, and about 115 pt were left for the list.

The sides of the screen are not free in landscape: a strip of about 47 pt on each side.
The notch stands in the middle of one of them, on the left or the right, depending on
which way the iPhone is turned.

## Considered options

1. **Flatter rows in landscape:** a smaller header, group row and PTT. The bar stays
   below. The list stays cramped, and every part needs a second size.
2. **Two columns for the memories:** the header and PTT on the left, the list on the
   right. The list gets the whole height, but the page needs a layout of its own.
3. **The page bar in the strip at the side**, as on a folded iPhone Duo
   ([ADR-0071](0071-iphone-duo.md)). The bar would stand behind the notch whenever
   it is on that side; knowing the side needs the orientation, which the app does not
   check (ADR-0071).
4. **The page bar as a column at the right, within the free part of the screen.**
   Its background reaches through the strip to the edge. It takes about 60 pt of the
   width, of which landscape has plenty, and frees the height of the bar for every page.

## Decision

Option 4. Where the vertical size class is compact and the system puts no vertical
bars (`verticalBarEdge` is `nil`), the page bar is a column of 60 pt at the trailing
side, set as a safe area inset of the compact screen. Where the system puts vertical
bars, ADR-0071 still applies. In portrait, nothing changes.

## Consequences

- On a 6.1-inch iPhone in landscape, the memories, the header and PTT fit; the
  other pages gain the height of the bar as well.
- The pages are 60 pt narrower in landscape.
- **Tests:** a UI test turns the iPhone and checks that the frequency, PTT and the
  page bar lie within the window and that the bar stands beside PTT. It runs on any
  iPhone simulator; the 6.1-inch one (iPhone 17e) is the one where the layout did not
  fit.

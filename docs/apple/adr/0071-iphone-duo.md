# ADR-0071: iPhone Duo and layouts that change while the app runs

- **Status:** Proposed
- **Date:** 2026-11-13

## Context

The iPhone Duo folds. Folded, it shows the app on an outer display of 466 × 678 pt;
unfolded, on an inner display of 669 × 951 pt. Apps built with the iOS 27 SDK resize
when it folds or unfolds. Since the iOS 27.1 SDK they reach the edges of both displays.
The status bar then stands at the side, and toolbars and tab bars stand vertically
below it ([Apple: Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)).
The app is built with Xcode 27.2, so every TestFlight build gets this behaviour.

The app already avoids the patterns Apple names: no `UIScreen.main`, no checks of the
idiom, the orientation or fixed sizes. The layout depends on the horizontal size class
([ADR-0032](0032-ios-layouts.md), [ADR-0040](0040-screen-layout.md)). Folded,
the Duo is compact and the app shows its pages. Unfolded, it shows the wide layout. On
the iPhone Duo simulator, these problems showed up:

1. Folding swaps the layout under a finger that holds PTT. The button goes, its touch
   never reports an end, and the radio would stay on air.
2. What the views kept themselves was lost in the swap: a message being written, the
   settings page that was open.
3. Folded, the status bar stands in a strip at the right side, about 90 pt wide, also
   in portrait. The pager reached under it, so the next page showed there.
4. The page bar below the pages took height from the small outer display, while the
   strip below the status bar stayed empty. A system tab bar would stand there.

## Considered options

For problem 3:

1. **Pages across the whole width, the safe area handed back to each page.** This gives
   backgrounds to the edge. Pages with a `NavigationStack`, the settings, do not take the
   safe area that is handed back, and their switches end up under the status bar.
   Rejected.
2. **The pager clipped to its frame.** The pager stays within the safe area, so nothing
   of the next page shows. Chosen.

For problem 4:

1. **Keep the page bar below the pages.** Simple, but it wastes the strip and differs
   from system apps.
2. **The page bar as a column in the strip, below the status bar,** where the system
   puts vertical bars. Chosen.

## Decision

- **PTT and the access tone end when their button goes** while held. Sticky PTT stays on.
- **Drafts live in the view model:** the line of the packets and each chat. The model
  cuts a chat draft at what one message holds and drops it with its chat.
- **One settings path for both layouts.** `RootView` hands it over when the size class
  changes. The settings that were open stay open. The map, packets or chats shown on
  the phone layout are what the side pane shows in the wide layout.
- **The pager is clipped** to its frame.
- **The page bar follows `toolbarVerticalEdge`** (iOS 27.1). Where the system puts
  vertical bars, the page bar becomes a column in the strip below the status bar, on
  that side. The strip gets the bar colour. Everywhere else, also before iOS 27.1, it
  stays a row below the pages. The minimum OS stays 27.0. One modifier,
  `readsVerticalBarEdge()`, reads the value behind `#available` and passes it on as
  the environment value `verticalBarEdge`.

## Consequences

- **Tests:** the drafts are unit-tested in `KV4PRadio`. UI tests change the layout by
  turning a large iPhone, which swaps the layouts as folding does: the iPhone Duo
  simulator cannot be folded from a script, only in Xcode's Device Hub. The page tests
  also run on the iPhone Duo simulator, folded, where the page bar is a column.
- **Hardware test:** [HW-44](../hardware-tests.md#hw-44) checks PTT during a layout
  change on a real radio.
- **Open:** the unfolded layout (a third column, PTT in book pose) and iPhone Duo
  screenshots for the App Store (milestone 99.1) come later. Apple names device poses
  but documents no API for them; the app follows the size only.

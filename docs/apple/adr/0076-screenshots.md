# ADR-0076: Screenshots for the App Store, the website and the manual

- **Status:** Proposed
- **Date:** 2026-11-14

## Context

The App Store release ([release plan](../release.md), milestone 99.1) needs screenshots of iPhone, iPad and Mac. The
website and the manual are to show the app too, in the light and the dark colour scheme, which the website lets the
reader choose. Screenshots taken by hand go out of date with every change of the user interface, and taking them
again for three kinds of device and two colour schemes takes long. App Store Connect wants, at the time of writing:

- iPhone with Dynamic Island, medium display (required): 1206 × 2622 pixels, which the iPhone 18 Pro simulator takes;
- iPad 13-inch (required for an app that runs on iPad): 2064 × 2752 pixels, the iPad Pro 13-inch (M5) simulator;
- Mac (required for a Mac app): 16:10, such as 2560 × 1600 pixels;
- PNG or JPEG without transparency, up to ten per size;
- iPhone Duo, outer and inner display: optional, but required from April 2027 for apps built with the iOS 27.1 SDK.

## Decision

- **Entry point:** `make screenshots` runs `scripts/screenshots.sh` for the devices in `SCREENSHOT_DEVICES`, by
  default the iPhone 18 Pro and the iPad Pro 13-inch (M5) simulators and this Mac. One simulator at a time, shut down
  after its run, as the UI tests do (ADR-0072).
- **One UI test:** `ScreenshotTests` goes through the screens of the demo mode (ADR-0062) and adds each as an attachment
  named `<appearance>-<screen>`. It runs only when the script sets `KV4P_SCREENSHOTS` (as `TEST_RUNNER_KV4P_SCREENSHOTS`
  for `xcodebuild`), and skips otherwise, so that `make a11y` and CI are not slower. The navigation it shares with the
  accessibility audit lives in helpers of the UI tests.
- **Light and dark in one run:** two arguments of the demo mode, which change nothing outside it:
  - `-uitest-appearance light|dark` sets the colour scheme of the app's windows (`preferredColorScheme`);
  - `-uitest-signal <0–13>` lets the simulated radio receive a signal, so that the S-meter shows one.

  The test goes through the screens in light, starts the app again in dark and goes through them once more. The app is
  built and the simulator started once.
- **Simulators of their own:** the script makes, once, a simulator named `<device> (screenshots)` of the same type and
  runtime, in English (`en_US`): an iPad's status bar shows the date in the simulator's language, which the status bar
  override cannot change, and the language of the simulators used otherwise stays as it is.
- **Status bar:** `simctl status_bar override` sets 9:41, full signal and a full battery, as on Apple's images.
- **Demo content:** richer than the audit needs, so that the images look like a day on air: memories in three groups,
  stations apart from each other on the map, and a chat in the abbreviations of radio amateurs. Placeholder callsigns
  only; the names the UI tests look for stay.
- **The Mac:** the test pulls the window to a fixed size and cuts it out of the screen, as the audit does. With the
  colour scheme argument, the app puts its windows at the level of a screen saver, in front of what other apps show
  below the menu bar, which would otherwise be cut out with the window.
  `scripts/screenshot-image.swift` puts it with rounded corners and a shadow on a calm background of 2560 × 1600
  pixels. The images of iPhone and iPad keep their size; the same program drops their transparency.
- **Output:**
  - `.build/screenshots/raw/<device>/` every screen as taken; `.build/screenshots/store/<device>/` the store's images,
    numbered in the order the script names. Neither is committed: both can be taken again at any time.
  - `docs/apple/site/img/screens/<device>-<screen>-<appearance>.webp`: smaller copies for the website and the manual,
    in WebP, which are committed.
- **Light and dark on the pages:** an image named `…-light.webp` has its dark copy beside it. The site's filter
  (`links.lua`) shows both and the stylesheet the one of the chosen colour scheme; GitHub shows the light one. A switch
  in the bar of the website chooses *Auto*, *Light* or *Dark*, and keeps the choice in the browser's `localStorage`.
  Without JavaScript the switch stays hidden, and the page follows the system. Each screenshot has a thin frame and a
  shadow, in the colours of the scheme, so that its edge shows on a page of the same colour.
- **Not in CI:** the screenshots are taken on purpose, before a release or after a visible change, so that the
  repository does not grow with each run.

## Consequences

- The images can be taken again with one command; a change of a screen's layout may need a change of the test's
  route.
- The demo content (`DemoContent`) is what the store shows; it uses placeholder callsigns only.
- The Mac run takes over the mouse and the keyboard, as `make a11y-mac` does.
- The iPhone Duo simulator cannot be folded by a script (ADR-0071): its screenshots, when they become required, are
  taken in the state the simulator is in, with `SCREENSHOT_DEVICES=iPhone Duo`, once folded and once open.
- About 2 MB of images in the repository, which grow only when the screenshots are taken again.

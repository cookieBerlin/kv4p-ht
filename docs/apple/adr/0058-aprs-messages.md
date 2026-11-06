# ADR-0058: APRS messages

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

Milestone 4.6c makes answering easier and tells the user about new messages, also with the app in the
background. Failures already reach the user through a notification on iPhone and iPad
([ADR-0039](0039-error-alerts.md)), and through the Dock icon on the Mac. Chats follow in 4.7.

## Decision

- **A message is for this station if it goes to its callsign with any SSID.** Bulletins and messages
  between others are not. Its own messages are not, but one from another of its SSIDs is.
- **New means an id not seen before.** A repeat stays the same event, so it brings no second count or
  notification. What comes back from the store is not new, and a packet that arrives before the store
  is read waits for it, as it gets a new id then.
- **A number on the APRS page counts new messages** until a list is on screen, on the main page or
  the packets page. It lives in memory only. Side by side, on the Mac and a wide iPad, the list is
  always on screen, so the number exists only where APRS is a page of its own.
- **A notification comes only when the app is not active,** with the sender and the text, one for each
  message. A switch under *APRS*, *History* turns it off, on by default and local to the device.
- **The Mac gets real notifications too,** and asks once, unlike its failures, for which the Dock icon
  is enough: a message has a sender and a text to show. Its scene stays active behind another app, so
  there the app follows the activation of the application instead.
- **The app asks when connecting and when the switch is turned on, also with the simulator,** which
  brings messages as a radio does. It is the same system question the failures use on iPhone and iPad.
  If it was refused, the switch shows a way to the system settings.
- **A connection removes only earlier failures** from the notification centre, not unread messages.
- **A tap on a message fills in the other station as the recipient,** and moves to the text. *Reply* in
  the row's menu does the same. On the packets page only the menu does, as a stray tap would leave the
  page, and it goes back to the main page, where the line to send is. Without a callsign or in
  listen-only mode, nothing can be replied to.

## Consequences

- A notification needs the app to be running, which holds in the background only while it has a reason
  to, such as a connected radio ([ADR-0031](0031-ios-background-operation.md)). There is no server that
  could wake it.
- A tap on a notification just opens the app; 4.7 opens the conversation.
- A list with a filter clears the number, even if the filter hides the message.

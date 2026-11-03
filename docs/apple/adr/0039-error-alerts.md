# ADR-0039: Reporting a failed connection

- **Status:** Proposed
- **Date:** 2026-11-03

## Context

A lost connection shows only as a status text on the radio screen. A user who has
locked the iPhone or works in another app on the Mac does not see it and may think
the radio is still listening.

## Decision

- **What is reported:** every change of the connection into a failed state: a lost
  connection, a connection that cannot be set up and a radio that does not answer
  or has outdated firmware. Each one causes one report. A disconnect the user chose
  causes none. Errors of a single action, such as a packet that cannot be sent,
  stay in the app as before.
- **Where the decision lives:** `RadioViewModel` detects the failure and sets
  `alertMessage` for the dialog or a notice (ADR-0040). The protocol `FailureAlerting` hides the platform.
  Its adapter is in the app target, and the tests use a fake.
- **Mac:** the dialog opens also while the app is in the background, and the Dock
  icon bounces until the user comes back (`requestUserAttention`).
- **iPhone and iPad:** a notice at the bottom of the screen and no dialog. In the
  background, also a local notification; the notice is there on return. The app sets
  no notification delegate, so the system drops a notification sent in the foreground.
- **Permission:** iOS asks when the user connects (ADR-0040). The request cannot appear
  while the app is in the background, when the failure happens. Connecting does not
  wait for the answer, and without permission the app works as before.

## Consequences

- No server, push service or entitlement is needed. The notification depends on the
  app still running, which the `audio` and `bluetooth-central` background modes
  provide while a connection is up.
- A new connection removes the notifications of earlier failures.
- The adapters cannot be tested automatically; hardware test HW-22 covers them.

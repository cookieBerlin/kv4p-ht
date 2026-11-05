# ADR-0047: Callsign and listen-only

- **Status:** Proposed
- **Date:** 2026-11-04

## Context

Transmitting needs an amateur radio licence, and an identification on air. The app so far
lets anyone press PTT. The Android app only shows a hint for a missing callsign. People
without a licence should be able to use the app to listen.

## Decision

- **A question at the start:** without a callsign and without listen-only, the app asks. It
  closes only with a choice. It is not asked while the callsign is edited in the settings,
  only at the next start.
- **No check of the callsign:** what is entered counts, after the existing clean-up of
  spaces and case. Whether a callsign is real cannot be checked.
- **One rule, `canSendOnAir`,** stands in front of every way to transmit: PTT, the access tone
  and AX.25, so also messages, acknowledgements, beacons and digipeating. New functions
  cannot miss it, as they go through the same ways. The screens hide what the rule forbids.
- **Without a callsign nothing goes out,** also not to the iGate, and APRS-IS stays off.
  Removing it ends a transmission at once, as does choosing listen-only.
- **Listen-only with a callsign** keeps the iGate and the APRS-IS feed, which do not transmit
  on air. Settings such as the beacon stay as they are, and work again afterwards.
- **The simulator follows the same rules,** so that it shows the real behaviour. The App Review
  notes ask to enter a callsign.

## Consequences

- Existing users without a callsign see the question once after the update, and cannot
  transmit until they enter one.
- A transmission without a real licence still cannot be prevented, as anything can be
  entered. The question and the licence note make the requirement clear.

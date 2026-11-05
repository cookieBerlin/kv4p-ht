# ADR-0061: APRS chats

- **Status:** Proposed
- **Date:** 2026-11-05

## Context

Milestone 4.7 brings simple chats over APRS, built on the stored packets of
[ADR-0057](0057-aprs-history.md). It has three parts, each with its own pull request: reading (4.7a), writing
(4.7b), and a notification that opens its chat (4.7c). This ADR covers 4.7a, and the others add to it.

## Decision

- **A chat is a view of the messages to and from this station,** with no storage of its own. Bulletins and
  messages between other stations stay in the packets.
- **Each callsign with its SSID is a chat of its own,** as a reply must reach that SSID. This station counts with
  any SSID, and a message between two of its SSIDs is a chat with the other one.
- **The chats come from memory and from the store,** as memory holds only the newest packets. They are read again
  when the callsign changes.
- **A switch at the top of the APRS page changes between *Packets* and *Chats*,** remembered on the device. A chat
  opens in place rather than in a navigation stack, as the page sits in one on a wide iPad.
- **A tap on a message of a chat in the packets opens that chat.** A tap on any other message fills in its sender as
  the recipient, as before, and *Reply* in a row's menu still only fills in the recipient.
- **The number on the APRS page is the sum of the unread messages,** and goes down when a chat is opened on screen.
  When each chat was read is kept on the device, so a restart does not bring old messages back as new.
- **Messages to and from this station have a time of their own,** *Keep messages for*: 30 days, 90 days, 1 year or
  without limit, which is the default, so that chats do not go unexpectedly. It stays on the device. *Keep packets*
  still decides whether anything is stored, so with it off the chats end with the app, and the chats say so.
- **Until 4.7b, the line to send messages stays below the chats,** and opening a chat fills in its station.

### Writing (4.7b)

- **A chat has its own line to write,** and the one below the packets stays there for bulletins and quick messages.
- **The counter stops at 61 characters, not 67.** A message to a station carries its number of up to five
  characters after a `{`, which the ported encoder fits into the 67 by cutting the text. A bulletin has no number,
  so 67 stay. Typing stops at the limit, so that nothing is cut when sending.
- **New chat** takes a callsign of three to six letters and digits, with an SSID of up to two, and refuses a
  bulletin address. The chat shows once its first message is there.
- ***Send again*** is offered for an own message that failed or was rejected, never by itself. It sends the text as a
  new message, and the old one leaves the chat but stays in the packets, marked on the stored event, so that what
  went out stays traceable.
- **Deleting a chat** asks first, and removes its messages from the packets and the store as well. A single message
  goes through its menu, without a question, as in the packets.
- **Without a callsign or in listen-only mode, a chat has no input,** and says why. Without a connected radio, it
  says so.
- **Over the simulator, the station written to answers,** so that chats can be tried without a radio: with an
  acknowledgement after 2 s by default, also with a reply after a time that can be chosen, to see its notification
  with the app in the background, by rejecting, or not at all. The simulator knows no APRS, so the app plays that
  station and hands its answers to the simulator as heard on air, as with the simulated test packets. A repeat is
  acknowledged again but brings no second reply. These settings stay on the device and take effect at once.
- **Messages go over the radio only,** so a station seen only on the internet gets a reply if an iGate passes it
  on. An empty chat says so.

### Notifications (4.7c)

- **A tap on the notification of a message opens its chat,** on the chats page, wherever the user was: on an
  iPhone the APRS page comes to the front, and settings shown over the main page close. The notification carries
  the station of its chat.
- **The app has a notification delegate now,** which also keeps notifications out while the app is in front, as
  before, since the app shows new messages itself there. A failure notification opens nothing but the app.

## Consequences

- The store finds a station's messages by the callsign in sender or recipient, so a few messages of others whose
  callsign contains it can stay as long as the chats.
- How chats behave with very many messages shows only in use.
- An unread message stays unread until its chat is opened, also when it was seen in the packets.

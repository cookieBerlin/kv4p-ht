# ADR-0077: Talking without a radio: medium and frame format

- **Status:** Proposed
- **Date:** 2026-11-14

## Context

Milestone 7.1 first planned simulators that hear each other over the local network. The goal has changed: people
who have the app, but no radio, should be able to talk to each other and exchange APRS messages, for example in a
building at an event, to try the app out. This ADR collects the constraints, the research and a tentative decision.
The decision is not final; that is why the status stays *Proposed*.

### Constraints

- **A mode of its own.** It is a new entry in the choice of radio, beside the real radio (BLE or USB) and the
  simulator. The simulator stays as it is (ADR-0014, ADR-0041), and the new mode does not build on it. Its name is
  open (see *Open questions*).
- **One medium per device, and no bridge.** A device uses exactly one medium at a time. No station connects that
  medium to another network, such as the internet, a WLAN or a radio: that would make it a repeater, which the app
  must not operate. A real radio and the new mode are never connected at the same time.
- **Forwarding within the same medium is allowed.** A station may pass on what it hears to other stations of the
  same medium (a mesh). It never leaves that medium.
- **Many stations, not only two.** Everyone nearby who runs the app in this mode hears everyone else.
- **What it carries:** voice and APRS messages, with the APRS features that make sense without a radio (messages,
  acknowledgements, chats, positions, beacons). It reuses the codecs the app already has: Codec2 1300 (ADR-0005,
  ADR-0027) and IMA ADPCM (protocol spec §5).
- **Kept simple.**
  - One channel in the user interface. The frame format has a channel field, so more channels can follow without
    breaking it.
  - Collisions only so far as this: while another station transmits on the channel, the own PTT is blocked.
  - No frequency, offset, tones or squelch. The S-meter may show the received signal strength of Bluetooth LE
    instead (see *Research*).
- **Callsign and listen-only apply** as with a radio (ADR-0047).
- **No encryption.** Everything is readable by every station, as on air.
- **The device is not identifiable.** The callsign is unique and shows who speaks, as on air. Beyond that, nothing
  the mode sends may identify or track the device: no fixed ID, no name, no model.
- **Range:** no requirement. The range of Bluetooth LE is enough.
- **Platforms:** iOS, iPadOS and macOS first. The frame format is documented so that an Android app could
  implement it later; the Android app of this repository does not take part.
- **Entitlements:** a restricted entitlement could be requested from Apple, but the mode should rather work
  without one, so that App Review has nothing extra to judge.

## Research

### Media on iOS, iPadOS and macOS

| Medium | Many stations | Without a router | macOS | Entitlement | Finding |
|---|---|---|---|---|---|
| WLAN, Bonjour and unicast UDP/TCP | yes, each sends to each | no | yes | none | works |
| WLAN multicast or broadcast | yes, efficiently | no | yes | iOS: restricted, on request | possible |
| Peer-to-peer Wi-Fi (AWDL) through the Network framework | reported limit of about 8 | yes | yes | none | Apple only |
| Wi-Fi Aware | yes | yes | no | its own | does not fit |
| Multipeer Connectivity | about 8 | yes | yes | none | does not fit |
| Bluetooth Mesh (Bluetooth SIG) | yes | yes | — | — | not possible |
| LE Audio broadcast (Auracast) | yes | yes | — | — | not possible |
| Bluetooth LE GATT mesh | yes, through forwarding | yes | yes | none | works |

- **WLAN with Bonjour and unicast.** Registering, browsing and resolving a Bonjour service with a fixed service type
  needs only the local network permission and the type in `NSBonjourServices`. Unicast UDP needs no entitlement
  (TN3179). Each station sends each frame to every other station. For voice in Codec2 1300 that is a few kbit/s per
  peer, which a WLAN carries easily.
- **WLAN multicast.** On iOS and iPadOS, sending or receiving multicast or broadcast needs the restricted entitlement
  `com.apple.developer.networking.multicast`, which Apple grants on request, and the user's consent. macOS needs no
  entitlement (TN3179). Multicast would only save the sending to each peer.
- **Risk of public WLANs.** WLANs for guests and events often block traffic between clients (client isolation) and
  filter mDNS. Then neither Bonjour nor unicast nor multicast reach the other stations. For the use at an event,
  this speaks against WLAN as the first medium.
- **Peer-to-peer Wi-Fi.** The Network framework can use Apple's peer-to-peer Wi-Fi (`includePeerToPeer`) without a
  router. It is Apple only, an Android app could never join, and developers report that the number of peers stops
  at about 8.
- **Wi-Fi Aware** (iOS and iPadOS 26 and later, iPhone 12 and later) is a Wi-Fi Alliance standard that Android
  supports too. It does not fit:
  - There is no macOS.
  - Each pair of devices must be paired first, through DeviceDiscoveryUI or AccessorySetupKit, which does not fit
    "everyone nearby hears everyone".
  - The connections are encrypted at the Wi-Fi layer.
- **Multipeer Connectivity** is Apple's own protocol, made for a small set of peers. Android could not join.
- **Bluetooth Mesh**, the standard of the Bluetooth SIG, needs the advertising bearer. iOS offers no API for it, so
  phones cannot form a mesh with each other; they reach a mesh only through a GATT proxy node, which is hardware.
- **Auracast** (LE Audio broadcast): iOS has no public API to act as a broadcast source.
- **Bluetooth LE GATT mesh.** Each device is at the same time a central (it scans and connects) and a peripheral
  (it advertises and accepts connections). Frames are flooded with a hop limit and duplicate detection. The open
  source app bitchat shows this works on iOS and macOS: TTL 7, a set of frames already seen, random jitter before
  forwarding, frames larger than a write split into fragments. Its whitepaper says it is in the public domain.
  Limits of Bluetooth LE on Apple's platforms:
  - **The number of connections is not defined.** CoreBluetooth reports `connectionLimitReached` ("The device
    already has the maximum number of connections"), but Apple documents no number. Apple's engineers say it is
    "not documented nor defined" and varies with the type and model of the device, the system version, the state
    of the device and the BLE connections of other apps, and may change over time; apps should detect the limit at
    run time. Findings:
    - watchOS and visionOS allow 2 connections per app, which Apple confirmed but never documented. On visionOS,
      the third `connect()` stays in *connecting* without an error, so a limit may also show as a silent hang.
    - iOS: a developer connected 4 devices, which Apple does not guarantee. Other reports, between 8 and 20, are
      anecdotes without a method.
    - No source says whether connections as a central and as a peripheral count together.
    - bitchat chooses its limit itself: at most 6 connections as a central, one new connection every 0.5 s at most,
      and scanning in a cycle of 5 s on and 10 s off.
  - Measured throughput varies widely with the device, the system and the connection interval: from about 40 to
    over 1000 kbit/s.
  - In the background, iOS advertises no local name, and the service UUIDs move to an "overflow area" that only
    an Apple device scanning in the foreground sees. Two phones in the background may not find each other.
  - The kv4p radio itself already connects over BLE (ADR-0038). The new mode uses its own service UUID, so the
    choice of radio does not show other phones as radios.

### Signal strength for the S-meter

- **As a central,** an app reads the received signal strength (RSSI) of a connected peripheral with
  `CBPeripheral.readRSSI()`; about once a second is enough. Each advertisement found while scanning comes with its
  RSSI too.
- **As a peripheral,** an app gets no RSSI of a central connected to it. For frames that arrive this way, the RSSI
  has to come from scanning the same neighbour, which the mesh does anyway, as every device scans and advertises.
- **The values** lie roughly between −30 and −100 dBm and vary a lot with bodies, bags and walls, so they need
  smoothing. A fixed table would map them to S0 to S9+, as for the simulator (ADR-0041).
- **In a mesh,** the RSSI is that of the last hop only: the neighbour a frame came from, not the station that spoke.
  A station heard through three others would show the strength of the last one.
- **Ways out:**
  1. The last hop only: simple, but misleading for forwarded frames.
  2. The weakest link of the path: the header carries the lowest RSSI so far, and each station that forwards a
     frame writes in the lower of that value and its own. The S-meter then shows how good the whole path from the
     speaker was, which comes closest to its meaning on air: a weak link is where the path breaks off first.
  3. The number of hops in addition, "direct" or "through 2 stations", from the start value of the hop limit and
     the hop limit left.

### Privacy

- **Apple's platforms** advertise with a random Bluetooth address that changes over time, so the address alone does
  not track a device. A protocol with a fixed ID of its own would undo that.
- **The advertisement** carries only what the app gives it. Without a local name, it carries only the service UUID.
- **The device name** (such as "N0CALL's iPhone") is part of the Generic Access service of the system, and
  CoreBluetooth offers no setting for it. It is a general topic of Apple's platforms, not of this mode, and is left
  aside here.
- **bitchat** sends lists of its direct neighbours in its announcements. They show who is near whom.
- **The S-meter field and the number of hops** tell roughly how near a speaker is, as the signal strength does on
  air.
- **The system's own Bluetooth traffic** (for example Continuity) is outside the app's control; the mode only adds
  nothing to it.

### Codecs

| Codec | Rate | Per 40 ms | Finding |
|---|---|---|---|
| Codec2 1300 | 1.3 kbit/s | 7 bytes | vendored (ADR-0027); fits a BLE mesh well |
| IMA ADPCM, 16 kHz, 4 bit | 64 kbit/s | 320 bytes | in the app; too much for several hops of a BLE mesh, fine on a WLAN |
| Codec2 3200 or 1600 | 3.2 or 1.6 kbit/s | 16 or 8 bytes | not an option: not vendored, ruled out by the maintainer |

### Standards for what is carried

- **M17** is an open amateur radio standard for digital voice and data. It addresses by callsign (base-40), has a
  channel access number (CAN, 0–15), a packet mode with types for AX.25, APRS and SMS, and a framing over UDP
  (magic `M17 `, stream ID, link setup frame, frame number, 16 bytes of payload, CRC; port 17000). It does not fit
  as it is:
  - M17 voice is Codec2 3200 or 1600, which is not an option here.
  - Its IP part is made for reflectors, that is, for forwarding to other networks.
  - Its ideas fit: the callsign encoding, the stream ID that changes with each transmission, the frame number.
- **AX.25 over UDP (AXUDP)** puts one AX.25 frame, with its CRC, into one datagram. It is informal, without an RFC,
  but common (BPQ, aprsdigi, also over multicast). Carried like this, the APRS stack of the app (ADR-0006,
  ADR-0023) stays as it is; only the modem is replaced.
- **Not suitable:**
  - Apple's PushToTalk framework needs a server and push notifications.
  - MCPTT (3GPP) and OMA Push to talk over Cellular are made for mobile networks and are far too large.
  - AES67 is for studio audio.

## Considered options

### Medium

1. **WLAN with Bonjour and unicast**, multicast later. No entitlement, works on all three platforms, but fails on
   WLANs with client isolation, which are common at events.
2. **Bluetooth LE GATT mesh.** No router and no entitlement, works on all three platforms and on Android. Limited
   throughput, an undocumented number of connections and restrictions in the background.
3. **Both**, one of them chosen per device. Twice the adapters; the frame format is shared.

### Frame format

- **A. M17.** A real standard, but it needs Codec2 3200 or 1600, which is ruled out. About 11 kbit/s per stream
  over IP.
- **B. A format of our own, documented**, with voice in Codec2 1300 and APRS as AX.25 frames, and fields modelled on
  M17. About 1.3 to 2 kbit/s per voice stream.

## Decision

Tentative, not final:

- **Bluetooth LE GATT mesh first (option 2).** WLAN can follow later as a second medium with the same frame
  format, one of the two chosen per device.
- **Frame format B.**
  - A common header for each frame: a version, the type, the channel, the hop limit, the sender's callsign, a
    stream or message ID and a frame number. The channel is 0 for now; the other values are reserved.
  - **Voice:** Codec2 1300 frames, several of them per frame of the format, so that a frame fits one BLE write. A
    transmission has a stream ID and ends with an end mark.
  - **APRS:** one AX.25 frame per frame of the format, as AXUDP does.
  - **Busy channel:** while frames of another station's stream arrived within the last moment (about 500 ms, to be
    measured), the own PTT is blocked, as on a busy frequency.
  - **Forwarding:** each station forwards each frame it has not seen before, with the hop limit counted down and a
    short random delay. It never forwards its own frames back or frames with a hop limit of 0.
  - **S-meter:** the header carries the start value of the hop limit and the weakest RSSI of the path (one byte),
    which each forwarding station lowers to its own RSSI where that is weaker (way 2). Nothing is signed, so any
    station may change it. The S-meter shows that value, and the app shows the number of hops beside it (way 3).
- **Few direct neighbours.** Each station keeps only a few connections, for example at most 6 as a central like
  bitchat, and reaches the other stations through the mesh. It detects the limit at run time, from
  `connectionLimitReached` and from a timeout while connecting, as a limit may also be silent.
- **Privacy:**
  - The advertisement carries the service UUID only, no name and no callsign.
  - The callsign is only in the frames a station sends itself. A station that only listens forwards frames but
    sends none with its callsign, so it stays an anonymous node.
  - The frame format has no fixed device ID. Where the mesh needs one, for example to recognise its own frames, it
    is random and changes regularly, at the latest with each start of the mode.
  - No lists of neighbours, no device name, model, system or app version in the frames; the version field is that
    of the format.
  - APRS positions only when the user has switched beacons on, as with a radio.
  - Nothing leaves the mesh, and the app collects nothing about it.
- **The format gets its own specification** in `docs/apple/`, like the protocol spec of the radio, so that an
  Android app can implement it.

## Open questions

- **The name** of the mode in the choice of radio. "BLE" alone would be mistaken for the BLE connection to a radio.
- **How many stations and hops** really work: the number of connections per device, as a central and as a
  peripheral at the same time, how the limit shows (error or silent hang), the throughput and the delay through
  several hops. To be measured with several iPhones, iPads and Macs.
- **How often the random node ID changes,** and whether it can change together with the Bluetooth address.
- **The background:** whether the mode keeps working while the app is in the background (ADR-0031), and whether two
  phones in the background still find each other.
- **Which APRS features** make sense without a radio: digipeating would duplicate the forwarding of the mesh; APRS-IS
  and the iGate are ruled out, as they would bridge to the internet.
- **The S-meter:** the table from RSSI to S values, the smoothing, and whether the values of iPhones, iPads and
  Macs are comparable. To be measured with the devices of the open question on stations and hops.
- **The hop limit** and the flooding rules: the defaults of bitchat as a starting point, or simpler ones.
- **WLAN as a second medium:** when, and whether multicast is requested from Apple for it.

## Consequences

- Milestone 7.1 is rewritten for this mode. It may be split, for example the frame format and APRS first, voice
  after it.
- The real radio path and the simulator are not touched.
- The mode needs the Bluetooth permission and the background modes for Bluetooth LE, which App Review checks.
- An Android app could join if it implements the frame format and the mesh. Bluetooth LE GATT works there too.

## Sources

- Apple: [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
  [the multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast),
  [Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware),
  [best practices for a peripheral](https://developer.apple.com/library/content/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/BestPracticesForSettingUpYourIOSDeviceAsAPeripheral/BestPracticesForSettingUpYourIOSDeviceAsAPeripheral.html)
- Apple Developer Forums: [peer limit of the Network framework and Multipeer Connectivity](https://developer.apple.com/forums/thread/785308),
  [number of BLE connections](https://developer.apple.com/forums/thread/786878),
  [connections vary and are not published](https://developer.apple.com/forums/thread/786117),
  [visionOS: 2 connections, silent hang](https://developer.apple.com/forums/thread/812353),
  [watchOS: 2 connections per app](https://developer.apple.com/forums/thread/738861),
  [L2CAP throughput](https://developer.apple.com/forums/thread/89644)
- Bluetooth: [nRF Mesh library for iOS (no advertising bearer)](https://github.com/NordicSemiconductor/IOS-nRF-Mesh-Library),
  [bitchat whitepaper](https://github.com/permissionlesstech/bitchat/blob/main/WHITEPAPER.md)
- M17: [IP networking](https://m17-protocol-specification.readthedocs.io/en/latest/ip_encapsulation.html),
  [application layer](https://m17-protocol-specification.readthedocs.io/en/latest/application_layer.html)
- AX.25 over UDP: [BPQ AXIP/AXUDP](https://www.cantab.net/users/john.wiseman/Documents/BPQAXIP.htm),
  [OARC packet protocols](https://wiki.oarc.uk/packet:protocols),
  [aprsdigi](https://www.mankier.com/8/aprsdigi)

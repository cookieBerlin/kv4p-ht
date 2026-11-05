# kv4p HT for Apple — User Manual

> **Status:** the Apple app is in development and not released yet. This manual
> grows with each feature; sections marked *planned* describe intended behaviour.
> Platform notes: 🖥 macOS · 📱 iOS/iPadOS.

## Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [The main window](#the-main-window)
4. [Connecting the radio](#connecting-the-radio)
5. [Receiving](#receiving)
6. [Transmitting](#transmitting)
7. [Memories and scanning](#memories-and-scanning)
8. [APRS](#aprs)
9. [FreeDV digital voice](#freedv-digital-voice)
10. [Settings](#settings)
11. [Firmware updates](#firmware-updates)
12. [Troubleshooting](#troubleshooting)

## Requirements

- 🖥 Mac with Apple Silicon, macOS 27 or later.
- 📱 iPhone or iPad with iOS/iPadOS 27 or later.
- A kv4p HT radio with the firmware for this app, the nightly build. The released firmware 17
  is for the Android app, and this app does not connect to it
  (see [FAQ](faq.md#which-firmware-do-i-need)). 🖥 The Mac app can write it over USB.
- A valid amateur radio license to transmit.

## Installation

📱🖥 **TestFlight:** test builds for iPhone, iPad and Mac come through Apple's
TestFlight app. Install TestFlight from the App Store and open the invitation you
received. A build expires after 90 days; TestFlight then offers the current one.

🖥 To build from source, open `apple-src/App/KV4PHT.xcodeproj` in Xcode and run
the `KV4PHT` scheme (signed to run locally, no developer account needed), or see
[`apple-src/CLAUDE.md`](../../apple-src/CLAUDE.md).

## The main window

The structure is the same on all devices, and similar to the Android app:

- **On top:** the choice of radio, **Connect**, the name of the active memory, the frequency, the band,
  the squelch state and the S-meter. Type a frequency and press Return to tune.
- **Below:** the memories and APRS. 🖥 and on a wide 📱 iPad they stand side by side.
- **At the bottom:** a large **Push to talk** button, the connection status above it
  (🖥 in a status bar at the bottom of the window) and any messages.
- A message, red for a problem such as a missing location and green for a finished
  import, shows at the
  bottom of the screen until you dismiss it with ✕: 📱 on an iPhone above the bar with
  the pages, otherwise above **Push to talk** and in the 🖥 settings window.
- ⚙ **Settings:** all other settings. 🖥 It opens the settings window (⌘,).

📱 On an iPhone or in a narrow iPad window, **Memories**, **APRS** and ⚙ **Settings**
are pages: use the bar at the bottom, or swipe sideways. The app opens the page you
used last. **Push to talk** is on the memories page, and the header on the memories and
APRS pages.

Controls that are not self-explanatory explain themselves: 🖥 point at them for a
tooltip; 📱 a short text is below each setting, and ⓘ explains the
recipient of a message.

The first time you connect, the app asks for access to the microphone and your location
(📱 and for notifications), and over Bluetooth for Bluetooth. You can use it with any of
them denied: the functions that need one say so and offer **Open Settings**.

## Connecting the radio

Choose the connection under **Radio** at the top (📱 on an iPhone, tap the chosen radio) and click **Connect**:

- **Bluetooth:** power on the radio. Once Bluetooth access is settled, at your first
  connection, the app looks for radios while nothing is connected and lists them under **Radio**, each with its name and the end of its ID.
  Choose yours, and the app remembers it for the next start. *Bluetooth (first
  radio found)* connects to whichever kv4p HT it finds first. Allow Bluetooth
  access when the system asks.
  The radio serves one Bluetooth connection at a time, so disconnect other apps
  first.
- **USB (🖥 only):** connect the radio by USB cable; it appears as
  `USB cu.usbserial-…`. The app restarts the radio when connecting, so it
  reports itself.
- **Simulator:** a built-in simulated radio, to try the app without hardware. While it
  is chosen, ⚙ **Settings** has a **Simulator** page: its band, its firmware,
  the power switch, the radio module and whether it answers, which apply at the next
  connection and are locked while connected. The app remembers that the simulator was
  chosen. Each connection starts with squelch 3, as with its fixed frequency. It behaves like a real radio: 🖥 on the Mac,
  **Update firmware…** runs a simulated update with the chosen firmware; 📱 on iPhone and iPad, a firmware other than the one
  for this app fails the connection and shows the same messages as a real radio, without an update. **Simulator actions** are greyed out until it is connected. Then they set a received signal, ramp it through all
  strengths up and down, lose the connection and receive APRS test packets. A weak signal
  is quiet noise, out of which the tone grows up to S9; a real FM signal stays equally
  loud and only gets less noisy. Each squelch level opens from the same S value on.

After connecting, the app shows the firmware version, RF module (VHF/UHF) and
frequency range. The status *Connected, applying settings…* means the radio has not yet
confirmed the latest change. **Disconnect** ends the session; the radio keeps its
settings.

If the connection fails or is lost, the app tells you once, and not when you
disconnect yourself:

- 🖥 A dialog opens, and the status bar at the bottom of the window shows the reason.
  While the app is in the background, its Dock icon also bounces.
- 📱 The reason shows in red above **Push to talk**. In the background, you also get a
  notification if you allowed it.

## Receiving

- **Frequency:** type it in MHz and press Return. As in the Android app, `1467`
  becomes 146.7 MHz and frequencies outside the module range are set to the
  nearest limit. RX and TX use the same frequency (simplex); repeater offsets come
  with memories.
- **Bandwidth:** 12.5 or 25 kHz. **Squelch:** 0 (open) to 8. With 0, the speaker is always on, also without a
  signal; the settings warn about it in red.
- **TX/RX tone (CTCSS):** one of the 38 standard tones or *None*.
- **High power** and the **audio filters** (pre-emphasis, high-pass, low-pass).
- **S-meter:** S0…S9, then S9+20 to S9+60, and *Overload*, also as text. The bars are
  yellow up to S3, green up to S9, orange above S9 and red at overload. The mark over
  the bars shows the squelch level you set.
  Drag on the bars to change it: 📱 hold for a moment until it vibrates, then drag;
  🖥 drag or click directly. The level shows to the right of the bars and applies when
  you let go. While you transmit or scan, the squelch cannot change.
- **Squelch indicator:** a green speaker while a signal is received and played, a
  crossed-out speaker otherwise. The radio mutes the audio itself while the squelch
  is closed.
- **Volume:** the slider in the header (📱 on an iPhone, in ⚙ **Settings** under *Audio*) sets the playback volume in the app; the
  Mac's own volume applies on top. The audio plays on the current output device
  and moves along when you plug in headphones.
- 📱 On iPhone and iPad the audio plays on the speaker, or on a connected headset
  (wired or Bluetooth). Other apps keep playing. A phone call pauses the radio's
  audio; it continues when the call ends.
- 📱 **In the background:** while the radio is connected, reception goes on
  when you lock the screen or switch to another app. This includes the audio,
  APRS, digipeating, the iGate and, with *Beacon in the background* on, position
  beacons. The system then shows its location indicator. Disconnect to save the battery.
  With the switch off, beacons wait until the app is on screen again.
- 📱 **Other audio:** while the squelch is open or you transmit, podcasts of other apps
  pause and music gets quieter. They return once the squelch has stayed closed for the
  time set under **Resume after**, 3 s by default. Choose it in ⚙ **Settings** under
  *Other audio*: *Pause podcasts, lower music*, *Lower all* or *Keep playing*.
  - No received audio gets lost. While other apps play, it comes up to a second late,
    as the system stops the audio for each switch.
  - PTT pauses all other apps, also music and with *Lower all*, so that nothing goes on
    air. This takes up to a second; while no other app plays, PTT stays instant. They
    return after the same time. With *Keep playing* they go on, and the microphone can
    send them on air, so the settings warn about it.
  - A received APRS packet counts too, as the app cannot tell it from voice. With
    frequent packets, choose *Keep playing*.
  - With squelch 0 the squelch is always open, so only transmitting does this.
  - Podcast apps decide themselves whether they continue. If one stays paused, choose
    *Lower all*.
- 🖥 **Other audio:** choose *Mute other apps* in ⚙ **Settings**, under *Audio*. While
  the squelch is open or you transmit and another app plays, all other apps are silent,
  also browsers; the radio stays audible. They return after the time set under **Resume
  after**, 3 s by default.
  - This needs no permission, and the app records nothing.
  - Other apps keep running silently, so a video or podcast goes on without being heard.
  - By default, on *Keep playing*, they go on, and the microphone can send them on air.
- **Simulator:** *Received signal* in ⚙ **Settings** under *Simulator* plays a 1 kHz tone with the squelch
  open.

## Transmitting

Transmitting requires a license and an antenna or dummy load.

- **Push to talk:** hold the button at the bottom (📱 it vibrates when the
  transmission starts and ends) while you speak; release it
  to return to receive. It turns red while PTT is pressed and shows *On air* once
  the radio transmits. Without microphone access, a text replaces the button.
- **Sticky PTT:** each click starts or ends the transmission, as in the Android
  app.
- **Mic gain boost:** *None*, *Low* (×1.5), *Med* (×2) or *High* (×2.5); use it
  if others hear you too quietly.
- **High power** is in ⚙ **Settings** under **Radio**.
- The app only transmits inside the ham band: 144–148 MHz with a VHF module,
  420–450 MHz with a UHF module, including half the bandwidth at both edges.
  Narrower limits can be chosen in ⚙ **Settings** under **Radio**, **Frequency limits**. Otherwise the screen shows
  *Can't transmit here*, with the allowed range. On 144.0000 MHz, half of the channel
  would lie outside the band, so with 25 kHz the first allowed frequency is 144.0125 MHz.
- 📱 A phone call, or a headset that is unplugged or switched off, ends the
  transmission.
- Safety stops: the app ends a transmission after 3 minutes; the radio itself
  ends it when no audio arrives for about 0.8 s (e.g. when the connection drops)
  and after 200 s.
- After a transmission the received audio fades in again over about one second,
  as in the Android app.

## Callsign and listen-only

At a start without a callsign, the app asks for it, or you choose **Listen only**. You can
change both later in ⚙ **Settings** under *Station*. A transmission needs an amateur radio
licence.

- **With a callsign:** everything is available. The app does not check what you enter.
- **Listen only:** the app does not transmit: no PTT, access tone, APRS messages,
  acknowledgements, beacons or digipeating. Reception, memories and the scan work as usual.
  With a callsign, the iGate and the APRS-IS feed stay available. A beacon or digipeating
  you turned on stays set, and works again once you turn *Listen only* off.
- **Without a callsign:** nothing goes out at all, also not to the iGate. Removing the
  callsign ends a transmission at once, and unless *Listen only* is on, the settings warn
  in red.

## Opening a repeater

Some repeaters open only on a tone. Choose it in ⚙ **Settings** under *Transmit*, *Repeater access
tone*: 1000, 1450, 1750 or 2100 Hz, off by default, its length, and the wait before it. A
memory can have its own tone and length, or use the settings, which is the default.

**Hold** the **Tone** button next to PTT on the memories page:

- The transmitter starts, and once the radio reports that it transmits, the set wait
  passes in silence. Then the tone goes out for the set length, on air and on this device,
  and the transmitter stops by itself, also if you still hold the button.
- Releasing earlier stops at once, and the app says that the repeater may not have opened.
  The next press removes this message.
- The button shows the frequency of the tone.
- If the radio does not transmit within 2 s, the app stops and says so.
- 📱 The iPhone vibrates all the time while the button is held.
- The microphone stays closed, so other apps keep playing. Sticky PTT has no effect on the
  button, and the frequency limits apply.

The button shows with a tone chosen, a connected radio, the microphone permission and
analog voice.

## Memories and scanning

The memory list is next to APRS (on an iPhone, in the **Memories** tab).

- **Tune:** click (📱 tap) a memory; 📱 a checkmark marks the active one. The radio switches to its frequency, repeater
  offset (TX = RX ± offset) and tones. Frequencies outside the module range are
  set to the nearest limit, as in the Android app.
- **Add:** **+** creates a memory from the current frequency. **Edit…** and
  **Delete** are behind the ⋯ button of each memory. Deleting always asks first. A
  memory has a name, frequency, offset (none, down or up, in kHz, default 600), TX and
  RX tone, an optional group and *Skip during scan*. With an offset, the form shows
  where the memory transmits.
- **Groups:** the **Group** picker above the list shows one group or all memories.
  **Scan** and **+** are next to it.
- **Scan:** steps through the memories shown, in order, and stays on a memory
  while a signal opens the squelch. It moves on 250 ms after the squelch closes.
  It skips memories marked *Skip during scan* and those outside the module
  range. With squelch 0 it scans with squelch 7, as in the Android app; **Stop
  scan** restores your squelch. Transmitting or tuning by hand ends the scan.
- **Memories** in ⚙ **Settings** shows the groups, and a group its memories.
  Drag a row by its handle to sort: the groups, or the memories inside a group. The main
  list, the **Group** picker and the scan follow this order. A group exists as long as
  it has a memory. A memory's ⋯ button moves it to another group, and **Select** in the
  ⋯ menu at the top moves or deletes several at once. The same menu renames or deletes
  the group; deleting asks whether its memories go too or stay without a group.
- **RepeaterBook import:** **Import from RepeaterBook** in ⚙ **Settings** under *Memories* asks for a
  CSV export, which you download from [RepeaterBook](https://www.repeaterbook.com) in
  your browser (US or international format). It then shows how many repeaters it would
  add, and how many it leaves out because the radio cannot receive them or the group
  already has them (same name and frequency). You choose the group. Connect the radio
  first.
- Memories are stored on this device.

## APRS

The **APRS** tab lists the APRS packets the radio decodes on air, newest
first: positions, messages, weather reports, objects, status reports and
station capabilities. Repeats of the same packet within 30 seconds (numbered
messages: 30 minutes) are counted (×2, ×3, …) instead of listed again. Packets
relayed by another station (third-party) show *via* that station. Tune to the
APRS frequency of your region (e.g. 144.800 MHz in Europe, 144.390 MHz in North
America). The icon of a packet shows its APRS symbol, and the line below names it, along with the
radio if a Mic-E packet says which one it is, such as *Car · Yaesu FT5D*. For the details, 🖥 point at
the icon or 📱 hold it. The line also says what else a packet is, such as a bulletin, a status report or
telemetry, and marks those only from the internet, those your radio digipeated, and objects their owner
removed, which are crossed out. A weather report shows only what the station sends, and a repeater object
its frequency, offset and range. Telemetry and queries are named and shown as they arrive. The coordinates of a station open Apple Maps with a pin named after it. Once your
position is known, the distance and direction from you stand below them, such as *12.3 km NE*, in
the units you chose under ⚙ **Settings**, *APRS*, *Units*: those of your system by default, or metric
or imperial, also for the weather. Pressure stays in hPa; very near stations show no direction. Before you have decided on location
access, **Show distances** at the top of the list asks for it. Without access, the list works as
before. The list stays when the app ends: see *History* below. **Above the list:** the search finds a callsign in the sender or recipient, over everything stored. *For me*
shows only messages from or to your callsign, with any SSID. *Types* narrows the list to the types you
choose. *Export* saves what the list shows, also what is stored, as CSV or as raw packets. The app remembers
the filter on this device. ⚙ **Settings**, *APRS*, *Packets* shows the same list over the full height,
with a filter of its own, so that looking through the history leaves the main page as it is.

**Messages** (licence required): enter your callsign in ⚙ **Settings** under *Station* (the app
ships with none and remembers yours), then a recipient and the text below the APRS list,
then press Return or **Send**. Without a recipient the message goes out as the
bulletin BLN1CQ.

- The message is sent on the current TX frequency, via WIDE1-1,WIDE2-1, only
  while the radio receives (not during PTT or a scan) and inside the ham band.
- Messages to a station are numbered and repeated after 15, 30, 60, 120 and
  240 seconds until the station acknowledges them. The symbol next to the
  message shows the state: waiting, delivered, rejected or not delivered.
  Tuning to another frequency ends the repeats (*not delivered*), as in the
  Android app.
- Numbered messages to your callsign are acknowledged automatically after one
  second.
- `|`, `~` and `{` are sent as spaces; text and number together are limited to
  67 characters.

**Chats:** the switch at the top of the APRS page changes between *Packets* and *Chats*. *Chats* has one chat for
each station you wrote with, with its SSID, newest first, and the number of unread messages. A chat shows the
messages in the order they were written, yours on the right with their delivery. A tap on such a message in the
packets opens its chat. Messages to and from you stay as long as ⚙ **Settings**, *APRS*, *History*, *Keep messages
for* says, without limit by default; with *Keep packets* off, chats end with the app.

**Writing in a chat:** the line at the bottom of a chat sends to its station, with a counter that stops at 61
characters, as the message's number takes the rest of APRS's 67. *New chat* at the top of the list starts one with a
callsign, with its SSID if it has one. A message that was not delivered shows *Send again*; it is never sent again by
itself, and the new one takes its place in the chat, while the packets keep both. Holding a message (right-click on
the Mac) deletes it, and the trash button at the top deletes the whole chat, also from the packets, after a question.
Messages go over the radio; a station seen only on the internet gets them only if an iGate passes them on.

**Answering and new messages:** a tap on a message to others fills in its sender as the recipient, and *Reply* in
the ⋯ menu of its row does the same, also from the *Packets* page. The number on the APRS page, and on *Chats*,
shows unread messages to your callsign, with any SSID, until you open their chat. While the app is in the background, each of them
brings a notification with its sender and text. The app must be running for this, so nothing arrives after it has
ended. *Notify about messages to me* under ⚙ **Settings**, *APRS*, *History* turns this off.

**If something goes wrong:** the app keeps a log on your device, with frequencies and times but without callsigns, message texts or positions.
⚙ **Settings**, *Logging*, *Live log* shows what is being logged as it happens: you can search, filter by level
and category, pause and copy. On the same page, *Report a problem* shows a report, which you can share or attach to a
GitHub issue after looking through it. Issues are public. Nothing leaves your device without you. There you can
also delete the log, and turn on *Detailed logging*, which ends by itself after a day. After a crash, the app asks once whether to report it.

**History:** under ⚙ **Settings**, *APRS*, *History*, *Keep packets* keeps the list across restarts, for 1, 7
or 30 days or without limit, 30 by default. The packets stay on this device and are not synced. Packets only
from the internet can be many, so they stay only with *Keep internet packets* on; messages to or from you
always stay. The box on a row tells you: filled means the packet is stored, empty means it goes when the
app ends. The list shows the newest 500; **Load more** at its end brings older ones. The ⋯ button of a
row deletes that packet at once, and *Delete all packets* in the settings all of them, after a question. A message
that had no acknowledgement when the app ended shows as not delivered, and is not sent again.

**Position beacon** (licence required): choose how often under *Every*, from 2 to 60 minutes, 5 by default.
All stations share the frequency, so choose no more often than you need. 📱 *Beacon in the background*, on
by default, keeps it going with the screen locked. If your position cannot be found, one notice says so,
and another only after a beacon has worked in between. Turn on *Position beacon* in ⚙ **Settings** under *APRS*,
where digipeating and the APRS-IS switches are too. The app sends your position right away and then every five
minutes, as long as the radio is connected and receiving. Choose the symbol
others see (phone, car, house, …) and, under *Position accuracy*, round the position
to about 50, 100, 500 or 1000 m. While the beacon is on, the APRS list says so. Your own beacons appear in the list. Beacons go out on the current TX frequency, or
on the APRS frequency chosen next to the symbol (144.390 … 145.825 MHz); the
radio returns to its frequency afterwards.

**Digipeat** turns the Mac into a fill-in digipeater: packets whose next hop is
`WIDE1-1` or your callsign are repeated once, with your callsign in the path.
This transmits without you pressing anything; only turn it on where a
digipeater is useful.

**APRS-IS** (internet, needs your callsign):

- *Show nearby APRS-IS packets* adds packets from the internet around your
  position (50 km) to the list; they are marked as internet-only. Without a known
  position, the server uses your last reported position.
- *iGate* passes the packets your radio receives to APRS-IS, and your own
  messages and beacons too, so stations elsewhere see them. Packets from the
  internet, marked NOGATE or RFONLY, and queries are not passed on.
- Both use `rotate.aprs2.net` and reconnect by themselves; the label next to the
  switches shows whether the app is connected. The feed works without a radio.

## FreeDV digital voice

FreeDV 2400B is digital voice on FM radios: the radio's firmware runs the
modem, the app encodes and decodes the speech with Codec2.

- Set **Voice mode** to *FreeDV 2400B* in ⚙ **Settings** under *Radio*. The firmware for this app has the
  modem it needs.
- Receiving: the squelch opens only for FreeDV signals; analog stations are not
  heard in this mode. The S-meter shows the signal quality.
- Transmitting (licence required) works like analog voice: PTT, mic gain and the
  same frequency limits. Stations need FreeDV 2400B to understand you.
- The radio keeps the setting while it is on, also when the app reconnects;
  after a restart it is analog again. Switch back to *Analog* for normal FM.
- Try it without a second radio: connect the **Simulator**, choose FreeDV 2400B
  and choose a *Received signal* in ⚙ **Settings** under *Simulator*; you hear a vowel-like test sound.

## Settings

⚙ **Settings** opens an overview of pages: a sidebar on the Mac, a list on iPhone and iPad.
A short text below a setting explains it.

| Page | What it holds |
|---|---|
| **Station** | Your callsign, listen only |
| **Radio** | Bandwidth, squelch, tones, high power, voice mode, audio filters, frequency limits, firmware |
| **Transmit** | Sticky PTT, mic gain boost, repeater access tone |
| **Audio** | 📱 The volume on an iPhone, and what other apps do while the radio is busy |
| **APRS** | Packets, position beacon, units, history, digipeating, iGate, APRS-IS feed |
| **Memories** | Groups and memories: sort, edit, import |
| **Simulator** | The simulated radio; only while it is the chosen radio |
| **About kv4p HT** | 📱 Version and licences; on the Mac in the **kv4p HT** menu |

**iCloud sync**, in its own group under *Station* and on by default, takes your memories and groups, your callsign, sticky PTT, the access
tone, the APRS symbol, position accuracy, beacon frequency and interval, the units and the
frequency limits to your other iPhones, iPads and Macs with the same Apple ID. A change can take a
while to arrive. The radio, the memory group, other audio, mic gain, listen only and the
switches for the beacon and the background, digipeating, the iGate and the APRS-IS feed stay on each device.
For memories, a change of the switch takes effect at the next start. If two devices change the
same field at once, the later change counts. The same memory on two devices becomes one once it
is alike in everything; memories that differ stay apart. Without iCloud the app works as before
and says so below the switch. **Settings last synced** shows when this device last exchanged settings with
iCloud, and **Memories last synced** when a sync of the memories last finished. The two run
separately, so each has its own time; the system decides when they reach
your other devices.

The radio keeps its own settings (frequency, bandwidth, squelch, tones, power,
filters, voice mode) and reports them when the app connects. The app remembers
its settings between launches:

- **⚙ Settings → Transmit:** sticky PTT and mic gain boost; without a radio, the settings
  that need one say that they are not available.
- **⚙ Settings → Radio:** the **Frequency limits**: 2 m from
  144 MHz to 148 or 146 MHz, 70 cm from 420 or 430 MHz to 450 or 440 MHz, as in
  the Android app. The app transmits only inside the band of the radio module.
- **⚙ Settings → Station:** your callsign.
- **⚙ Settings → APRS:** position beacon with symbol, accuracy and frequency, digipeating,
  iGate and the APRS-IS feed.
- **APRS list:** the list filter.
- **Memories:** the group shown.

**kv4p HT → About kv4p HT** (📱 at the end of ⚙ **Settings**) shows the version, build and commit of the app, the
firmwares it contains for USB updates, and the licences of everything it contains
or is ported from, with the licence texts.

For reduced motion and live captions use the system settings (System Settings →
Accessibility); the Android app's own switches for them are not needed on the
Mac.

## Firmware updates

The app needs the firmware for this app, and warns when the radio has another or none
(*The radio needs a firmware update.*). 🖥 The dialog and the main window then offer **Open
Settings**, which leads straight to the update.

- 🖥 Connect the radio by USB, select it under **Radio** and choose **Update
  firmware…** in ⚙ **Settings** under *Radio*, then choose a firmware and **Flash**. The app verifies it, in less than a minute, and the status bar shows the progress. Do
  not disconnect the cable until *Firmware updated and verified.* appears. If an
  update fails, simply start it again: the radio's bootloader is always there.
- 🖥 The app contains two firmwares, and neither needs an internet connection:
  - **Nightly build, for this app** (preselected): sound, USB and Bluetooth LE work. It is a
    development build of the kv4p HT project. The window shows its build time, commit and
    SHA-256; the app offers it only if the checksum matches. The app reconnects afterwards.
  - **Firmware 17, only for the Android app:** for going back to the Android app. It has no
    Bluetooth LE, and this app does not connect to it, as it would have no sound and
    PTT would transmit silence. The app stays disconnected and says that the radio is set up for
    Android; you can come back at any time with the nightly build.
- Neither changes the radio's board configuration.
- 📱 Updating from iPhone or iPad is not possible. As such a radio has no Bluetooth LE, the app
  cannot connect to it and points to a Mac with this app, the Android nightly app and this
  section. The project's [web flasher](https://kv4p.com/firmware.html) offers only firmware 17,
  which does not help here.

## Troubleshooting

| Message | What to do |
|---|---|
| *The radio did not answer.* | Switch the radio on; it needs the firmware for this app. |
| *Firmware … is too old.* | Update the firmware (see [Firmware updates](#firmware-updates)). |
| *This radio has the firmware for the Android app…* | Update it to the firmware for this app (see [Firmware updates](#firmware-updates)). |
| *The SA818 radio module did not respond.* | Restart the radio. The app sends no settings in this state, because the firmware would stop responding. |
| *This device is not a kv4p HT, or its firmware has no Bluetooth LE service…* | Update to the firmware for this app ([Firmware updates](#firmware-updates)). |
| *Bluetooth access is not allowed.* | 🖥 System Settings / 📱 Settings → Privacy & Security → Bluetooth. |
| *… cannot be opened.* | Close other apps that use the USB port. |
| *Microphone access is not allowed…* | 🖥 System Settings / 📱 Settings → Privacy & Security → Microphone, then press PTT again. |
| *The microphone could not be started.* | Press PTT again. If it stays, another app may be using the microphone, or restart the app. |
| *Set your callsign to send APRS messages.* | Enter your callsign in ⚙ **Settings** under *Station*. |
| *Set your callsign to transmit.* | Enter your callsign in ⚙ **Settings** under *Station*. |
| *Listen only: this app does not transmit.* | Turn *Listen only* off in ⚙ **Settings** under *Station*. |
| *Your location is unknown.* | Allow location access in System Settings → Privacy & Security → Location Services, or wait until the Mac has a location. |
| *The APRS message was not accepted for transmission.* | Wait until PTT or the scan has ended, tune inside the ham band, and use a callsign of at most six characters plus SSID. |
| *This file is not a RepeaterBook CSV export.* | Download the CSV export (not the web page) from RepeaterBook. |
| *Connect the radio first, …* | The import needs the radio's frequency range; connect, then import again. |
| *The radio did not start its bootloader.* | Check the USB cable (it must carry data) and close other apps that use the port, then update again. |
| *The radio stopped answering during the update.* / *The firmware could not be verified.* | Start the update again; it can always be repeated. |
| *The audio output cannot be started.* | Check the output device in System Settings → Sound, then connect again. The radio works without audio. |
| 📱 *The audio was interrupted. Connect again to listen.* | Another app took the audio and iOS did not hand it back. Connect again. |

See also the [Apple FAQ](faq.md) and the general [FAQ](../../FAQ.md).

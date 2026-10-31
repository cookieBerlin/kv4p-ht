# 03 — Host ↔ Device Protocol Specification

Status: draft · Derived from upstream commit `a7c6b4d` (firmware version 17).

This document describes the protocol as implemented. The **source of truth is
the code**: `microcontroller-src/kv4p_ht_esp32_wroom_32/protocol.h` (firmware) and
`android-src/KV4PHT/app/src/main/java/com/vagell/kv4pht/radio/Protocol.java`
(Android). If this document and the code disagree, the code wins and this
document must be fixed. Golden test vectors (see
[05-testing-strategy.md](05-testing-strategy.md)) pin the byte-level behaviour.

Swift implementation: `apple-src/Packages/KV4PProtocol` (`RadioState`,
`DeviceState`, `FirmwareVersion`, `Hello`, `WindowUpdate`, `FrameEncoder`,
`KISSParser`, `SMeter`, `FlowControlWindow`).

All multi-byte values are **little-endian**. Floats are IEEE 754 binary32.
Structs are packed (no padding).

## 1. Transports

The same byte stream is carried over every transport. Each transport is an
independent session in the firmware with its own flags and flow-control window.

| Transport | Platforms (Apple) | Notes |
|---|---|---|
| BLE GATT | macOS, iOS, iPadOS | primary transport |
| USB serial | macOS | 115200 8N1 (the ESP32 USB-UART bridge) |
| Bluetooth Classic SPP | macOS (optional) | not planned for phase 1 |

### 1.1 BLE GATT

| Item | Value |
|---|---|
| Service UUID | `00000001-ba2a-46c9-ae49-01b0961f68bb` |
| TX characteristic (host → device) | `00000002-ba2a-46c9-ae49-01b0961f68bb`, Write + Write Without Response |
| RX characteristic (device → host) | `00000003-ba2a-46c9-ae49-01b0961f68bb`, Read + Notify |
| CCCD | `00002902-0000-1000-8000-00805f9b34fb` |
| Advertised name | `kv4p-XXXXXX` (24 bits of the eFuse MAC, hex) |
| Preferred ATT MTU | 247 (payload per write/notify = MTU − 3) |
| Flow-control window | 4096 bytes |

Connection sequence:

1. Scan for the service UUID.
2. Connect, discover the service and both characteristics.
3. Negotiate MTU (CoreBluetooth negotiates automatically; read
   `maximumWriteValueLength(for:)`).
4. Enable notifications on the RX characteristic. **The device only treats the
   session as connected and sends `HELLO` after the notify subscription.**
5. Bytes are a continuous KISS stream: a KISS frame may span several
   notifications/writes, and one notification may contain several frames.
   Writes are chunked to the ATT payload size; Write Without Response is
   preferred when available.

## 2. KISS framing

| Symbol | Value |
|---|---|
| `FEND` | `0xC0` |
| `FESC` | `0xDB` |
| `TFEND` | `0xDC` |
| `TFESC` | `0xDD` |

Frame: `FEND <command byte> <escaped payload> FEND`.
Inside the frame `0xC0` → `DB DC`, `0xDB` → `DB DD`.

The command byte is `port << 4 | command`. Only **port 0** is used; frames for
other ports are ignored.

| KISS command | Value | Direction | Payload |
|---|---|---|---|
| DATA | `0x00` | both | AX.25 frame without FCS, 1…328 bytes |
| TXDELAY | `0x01` | host → device | 1 byte, units of 10 ms |
| PERSIST | `0x02` | host → device | 1 byte, CSMA persistence |
| SLOTTIME | `0x03` | host → device | 1 byte, units of 10 ms |
| SETHARDWARE | `0x06` | both | KV4P vendor frame (§3) |

Parser rules (identical in firmware and Android):

- Bytes before the first `FEND` are ignored.
- Consecutive `FEND`s delimit empty frames, which are ignored.
- An unknown escape sequence drops the frame until the next `FEND`.
- A decoded frame longer than `KISS_MAX_FRAME_SIZE` (= 2048 + 1 + 6) is dropped.
- DATA payloads longer than `AX25_MAX_KISS_DATA_LEN` (= 10·7 + 2 + 256 = 328) are dropped.

## 3. KV4P vendor frames

Carried in KISS SETHARDWARE:

```
FEND 0x06 'K' 'V' '4' 'P' 0x01 <kv4pCommand> <payload ≤ 2048 bytes> FEND
```

`0x01` is the KV4P protocol version. Frames with another prefix or version are
ignored. Payloads are capped at `PROTO_MTU = 2048` bytes.

### 3.1 Host → device commands

| Command | Value | Payload |
|---|---|---|
| `HOST_TX_AUDIO` | `0x0C` | one IMA ADPCM block (§5) |
| `HOST_DESIRED_STATE` | `0x0D` | `HostDesiredState` (22 bytes, §4.1) |
| `HOST_TX_DIGITAL` | `0x0E` | one 7-byte Codec2 1300 frame |
| `HOST_TX_AX25` | `0x0F` | `float freqTx`, `uint8 bw`, `uint8 ctcssTx`, AX.25 bytes (≤ 328) — transmit once on a temporary frequency, then restore RX config |

### 3.2 Device → host commands

| Command | Value | Payload |
|---|---|---|
| `DEBUG_INFO` | `0x01` | UTF-8 text |
| `DEBUG_ERROR` | `0x02` | UTF-8 text |
| `DEBUG_WARN` | `0x03` | UTF-8 text |
| `DEBUG_DEBUG` | `0x04` | UTF-8 text |
| `DEBUG_TRACE` | `0x05` | UTF-8 text |
| `HELLO` | `0x06` | `Hello` (43 bytes, §4.3) |
| `WINDOW_UPDATE` | `0x09` | `uint32 size` (§6) |
| `DEVICE_STATE` | `0x0B` | `DeviceState` (26 bytes, §4.2) |
| `RX_AUDIO` | `0x0C` | one IMA ADPCM block (§5) |
| `RX_DIGITAL` | `0x0E` | one 7-byte Codec2 1300 frame |

Unknown commands are ignored by the host.

## 4. Structures

### 4.1 `HostDesiredState` (22 bytes)

| Offset | Type | Field |
|---|---|---|
| 0 | uint32 | `sequence` — incremented by the host for each new desired state |
| 4 | int32 | `memoryId` |
| 8 | uint16 | `flags` (§4.4) |
| 10 | uint8 | `bw` — `0x00` = 12.5 kHz, `0x01` = 25 kHz |
| 11 | float | `freqTx` (MHz) |
| 15 | float | `freqRx` (MHz) |
| 19 | uint8 | `ctcssTx` — SA818 tone index, 0 = none |
| 20 | uint8 | `squelch` — 0…8 |
| 21 | uint8 | `ctcssRx` — SA818 tone index, 0 = none |

### 4.2 `DeviceState` (26 bytes)

Bytes 0–21 have the same layout as `HostDesiredState` (`sequence` is
`appliedSequence`), followed by:

| Offset | Type | Field |
|---|---|---|
| 22 | char | `radioModuleStatus` — `'f'` found, `'x'` not found, `'u'` unknown |
| 23 | uint8 | `mode` — 0 TX, 1 RX, 2 stopped |
| 24 | uint8 | `lastError` — 0 none, 1 radio config failed, 2 filters failed |
| 25 | uint8 | `latestRssi` — raw SA818 RSSI |

S-meter: `dBm = rssi · 1.2 − 160.8`; S1 = −141 dBm, S9 = −93 dBm, 6 dB per S unit,
then 20 dB steps up to bar 12, above −30 dBm = overload (13). Reference:
`Protocol.calculateSMeterValue`.

### 4.3 `Hello` (43 bytes) = `Version` (17) + `DeviceState` (26)

`Version`:

| Offset | Type | Field |
|---|---|---|
| 0 | uint16 | `ver` — firmware version (currently 17) |
| 2 | char | `radioModuleStatus` |
| 3 | uint32 | `windowSize` — initial flow-control window of this session |
| 7 | uint8 | `rfModuleType` — 0 SA818 VHF, 1 SA818 UHF |
| 8 | float | `minRadioFreq` (MHz) |
| 12 | float | `maxRadioFreq` (MHz) |
| 16 | uint8 | `features` (bitmask below) |

| Feature bit | Meaning |
|---|---|
| `1 << 0` | `HAS_HL` — high/low power switch |
| `1 << 1` | `HAS_PHY_PTT` — physical PTT button |
| `1 << 2` | `HAS_ESP32_AFSK` — AFSK modem in firmware |
| `1 << 3` | `HAS_FREEDV_2400B` — FreeDV 2400B modem in firmware |

The Android app warns if `ver` is lower than its packaged firmware version.

### 4.4 State flags (`uint16`)

| Bit | Name | Host | Device | Scope |
|---|---|---|---|---|
| 0 | `RADIO_CONFIG_VALID` | ✓ | ✓ | global |
| 1 | `PTT_REQUESTED` | ✓ | ✓ | global |
| 2 | `RX_AUDIO_OPEN` | ✓ | ✓ | session |
| 3 | `HIGH_POWER` | ✓ | ✓ | global |
| 4 | `RSSI_ENABLED` | ✓ | ✓ | global |
| 5 | `FILTER_PRE` | ✓ | ✓ | global |
| 6 | `FILTER_HIGH` | ✓ | ✓ | global |
| 7 | `FILTER_LOW` | ✓ | ✓ | global |
| 8 | `PHYS_PTT_DOWN` | | ✓ | device only |
| 9 | `TX_ACTIVE` | | ✓ | device only |
| 10 | `SQUELCHED` | | ✓ | device only |
| 11 | `TX_ALLOWED` | ✓ | ✓ | global |
| 12 | `ENABLE_STATUS_REPORTS` | ✓ | ✓ | session |
| 13 | `FREEDV_2400B` | ✓ | | global |

*Session* flags apply only to the sending session (e.g. RX audio is streamed only
to sessions with `RX_AUDIO_OPEN`). *Global* flags change the radio for all
sessions. With `ENABLE_STATUS_REPORTS`, the device sends `DEVICE_STATE`
periodically (every 500 ms) and on changes.

## 5. Audio

| Item | Value |
|---|---|
| Sample rate on the wire | 16 000 Hz, mono, 16-bit PCM before encoding |
| Codec | IMA ADPCM, WAV block layout (4-byte header + 4-bit nibbles) |
| Block | 128 bytes = 249 samples ≈ 15.56 ms |
| Firmware internal rate | 48 kHz (resampling ×3 on the device) |
| TX watchdog | device stops TX if no audio arrives for 50 blocks (≈ 778 ms) |

In FreeDV 2400B mode the device sends `RX_DIGITAL` instead of `RX_AUDIO`, and the
host sends `HOST_TX_DIGITAL` Codec2 1300 frames (7 bytes each).

Reference implementation: `ImaAdpcm.java`.

## 6. Flow control (host → device)

- On `HELLO`, the host sets its send window to `Version.windowSize`.
- Before writing a frame, the host waits until the window ≥ the **encoded** frame
  length (including `FEND`s and escapes), then subtracts that length.
- After processing each received frame, the device sends `WINDOW_UPDATE` with the
  encoded length it consumed; the host adds it to the window.
- Device → host traffic has no application-level flow control.

## 7. Session lifecycle

1. Transport connects (BLE: after notify subscription).
2. Device sends `HELLO` (version + current device state).
3. Host checks the version, initialises the window, then sends
   `HOST_DESIRED_STATE` with the session flags it needs (`RX_AUDIO_OPEN`,
   `ENABLE_STATUS_REPORTS`) and the radio configuration.
4. Device applies the state and reports `DEVICE_STATE` with `appliedSequence`
   equal to the host's `sequence` once applied.
5. TX: host sets `PTT_REQUESTED` (and `TX_ALLOWED`), streams `HOST_TX_AUDIO`,
   then clears `PTT_REQUESTED`.
6. On disconnect the device clears the session flags.

## 8. Open points

- Exact semantics of `memoryId` on the device side.
- Mapping table of SA818 CTCSS indices (to be extracted from Android `ToneHelper`).
- Behaviour when several sessions request conflicting global flags.

# ADR-0018: Transport logic as state machines behind thin adapters

- **Status:** Proposed
- **Date:** 2026-10-31

## Context

[ADR-0002](0002-radio-transport.md) defines `RadioTransport` with BLE and USB
serial implementations. [ADR-0011](0011-coverage-policy.md) only allows excluding
adapters that forward between an OS API and a Swift protocol without branching.
The BLE connection sequence (power state, scan, connect, service and
characteristic discovery, notify subscription, [03-protocol-spec.md
§1.1](../03-protocol-spec.md)), write chunking with back-pressure, and the serial
reset and disconnect handling are logic and must be covered without hardware.

## Considered options

1. **Transports call CoreBluetooth / POSIX directly** — little code, but the
   logic only runs against hardware; violates ADR-0011.
2. **Mock the OS classes** — `CBCentralManager` and `CBPeripheral` cannot be
   subclassed or constructed meaningfully in tests.
3. **Event/command state machines** — the adapter turns OS callbacks into
   `Event` values and executes `Command` values; a pure Swift state machine
   decides. The transport actor connects both.

## Decision

Option 3.

- `KV4PTransport` defines `RadioTransport` (state stream, incoming byte stream,
  `connect`, `send`, `disconnect`) and `TransportError`.
- **BLE:** `BLELink` is a value-type state machine: `handle(_: BLEEvent) ->
  [BLECommand]`. It owns the connection sequence and the write queue (chunks of
  the maximum write length; Write Without Response when available, next chunk
  when the adapter reports it can send more). `BLETransport` is an actor that
  drives a `BLECentral` (event stream + `perform(_:)`). The CoreBluetooth
  adapter maps callbacks to events and commands to calls, nothing else.
- **Serial:** `SerialTransport` drives a `SerialPort` (open, modem lines, write,
  read stream, close). The POSIX/termios adapter only forwards. An optional
  reset pulse (RTS) restarts the ESP32 so it sends `HELLO`.
- **Simulator:** `SimulatorTransport` in `KV4PSimulator` drives `RadioSimulator`
  with an injected `Clock`, so tests use a manual clock.
- GATT UUIDs live in `KV4PProtocol` (protocol constants exist once).

## Consequences

- All transport logic is covered by `swift test`; only the adapters are listed
  in `coverage-exclusions.txt`.
- Adapters are verified with the hardware checklist and, for BLE, the
  `SimulatorPeripheral` (milestone 1.5).
- Each `AsyncStream` of a transport has a single consumer (the radio
  controller).

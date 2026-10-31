# kv4p HT for Apple platforms

Native SwiftUI app for **macOS (Apple Silicon)** first, then **iOS and iPadOS**,
talking to the kv4p HT over Bluetooth LE (all platforms) and USB (macOS).
No changes to the firmware or the Android app are required.

**Status:** planning complete, implementation starts with phase 1.0
([roadmap](04-roadmap.md)).

## Documents

| Document | Purpose |
|---|---|
| [01-feasibility.md](01-feasibility.md) | Existing system, feature inventory, platform constraints, risks |
| [02-architecture.md](02-architecture.md) | Packages, layers, abstractions, Android → Apple mapping |
| [03-protocol-spec.md](03-protocol-spec.md) | BLE GATT, KISS framing, vendor commands, structures, flow control |
| [04-roadmap.md](04-roadmap.md) | Phases, milestones, acceptance criteria |
| [05-testing-strategy.md](05-testing-strategy.md) | TDD, 100 % coverage, golden vectors, simulator, CI |
| [adr/](adr/README.md) | Architecture Decision Records |
| [manual.md](manual.md) | User manual |
| [faq.md](faq.md) | Apple FAQ |

## Key decisions at a glance

- Native Swift 6 / SwiftUI multiplatform, no Catalyst ([ADR-0003](adr/0003-app-technology.md), [ADR-0012](adr/0012-platform-strategy.md))
- BLE everywhere, USB serial on macOS ([ADR-0002](adr/0002-radio-transport.md))
- Android code reused unmodified as test oracle ([ADR-0004](adr/0004-android-code-reuse.md))
- Minimum OS 26 ([ADR-0008](adr/0008-minimum-os-versions.md))
- 100 % coverage with minimal adapter exclusions ([ADR-0011](adr/0011-coverage-policy.md))
- GitHub Actions PR gate ([ADR-0013](adr/0013-ci-pr-gate.md))
- In-process + BLE peripheral simulator with scenarios ([ADR-0014](adr/0014-radio-simulator.md))

Contribution rules: [`CLAUDE.md`](../../CLAUDE.md).

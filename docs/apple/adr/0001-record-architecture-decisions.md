# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The Apple port is a new code base developed alongside the existing Android app
and firmware, by contributors who may change over time. Decisions such as the
transport, the UI technology or the coverage policy need to stay traceable,
including the alternatives that were rejected.

## Considered options

1. **No formal records** — decisions live in chat and pull requests. Easy, but
   the reasoning is lost and decisions get re-discussed.
2. **Architecture Decision Records (Nygard format)** — one short Markdown file
   per decision, versioned with the code.
3. **MADR (full template)** — more structured, but heavier than needed here.

## Decision

Use lightweight ADRs in the Nygard format, extended with a *Considered options*
section, stored in `docs/apple/adr/` and numbered sequentially. The template is
[`0000-template.md`](0000-template.md), the index is [`README.md`](README.md).

- New ADRs start as **Proposed** and become **Accepted** after review.
- Accepted ADRs are not edited in substance; they are **Superseded** by a new ADR.
- Every architecturally significant change in `apple-src/` references an ADR.

## Consequences

- Reasoning is reviewable and stays with the code.
- Small overhead per decision.
- [`02-architecture.md`](../02-architecture.md) describes *what* the system looks
  like; ADRs explain *why*.

# ADR-0016: Branch protection without required approvals

- **Status:** Accepted
- **Date:** 2026-10-31
- **Amends:** [ADR-0013](0013-ci-pr-gate.md) (branch protection)

## Context

[ADR-0013](0013-ci-pr-gate.md) requires pull requests and green checks before
merging into `main`. The fork currently has a single maintainer. GitHub does not
allow authors to approve their own pull requests, so a required approval would
block every merge.

## Considered options

1. **Require 1 approval** — blocks a single maintainer.
2. **Require pull requests and status checks, 0 approvals** — quality is
   enforced by the automated gate.
3. **No branch protection** — direct pushes to `main` bypass the gate.

## Decision

Option 2 on `main`:

- pull request required, no direct pushes;
- required status checks: `lint`, `privacy`, `test`, `ios-build`
  (plus `vectors` from milestone 1.1), branch must be up to date;
- required approvals: 0;
- force pushes and deletion blocked.

## Consequences

- Merges are fully gated by CI while staying possible for one maintainer.
- When more maintainers join, raise required approvals to 1 with a new ADR.

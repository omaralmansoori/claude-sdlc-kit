---
id: w1-be-02
produced_by: orchestrator-greenfield
produced_at: 2026-06-29T09:00:00Z
consumer_role: fixer-api
priority: high
area: backend
blocked_by: w1-be-01
finding_ref: examples/walkthrough/02-contract/build-plan.md#b-bkg-2
---

# B-BKG-2 — No-overlap-on-confirm constraint + RBAC + read-scope

> This file sits in `escalated/` because the fixer hit its gate-failure ceiling on the database-level
> exclusion constraint and stopped rather than thrash. Tickets are NEVER deleted — the follow-up is a
> NEW ticket, not an edit of this one.

## Context

A booking may be `Confirmed` only if its room + window does not overlap an existing `Confirmed`
booking for the same room; overlap is half-open `[start, end)` (`AC-BKG-02`; `BKG-BR-003` —
`examples/walkthrough/01-kb/bookings/BKG-bookings-requirements.md:24`). Also enforce confirm/reject =
Approver only (`AC-BKG-03`) and row-level read scope (`AC-BKG-04`).

## Reproduction (bug) OR Steps (chore)

1. Add the no-overlap rule to the confirm transition.
2. Back it with a DB exclusion constraint so two concurrent confirms can't both win.
3. Add the capability checks for confirm/reject and the row-scoped read.

## Acceptance criteria (this ticket is done when)

- Two overlapping confirms cannot both succeed (the second is refused), proven under concurrency.
- A Requester confirm/reject attempt returns 403.
- A Requester cannot read another user's booking even by guessing the id.
- ACs to turn green: AC-BKG-02, AC-BKG-03, AC-BKG-04.

## Pointers

- `apps/api/src/bookings/noOverlap.ts`, `db/schema/bookings.prisma`
- AC / spec ref — `examples/walkthrough/02-contract/design-spec.md` §3, §5

## Gate (must pass before `done/`)

```bash
pnpm typecheck && pnpm --filter api test bookings
```

## Activity
- branch: be/bookings-no-overlap-w1-be-02-s4f2a
- started: 2026-06-29T10:05:00Z
- notes: RBAC + read-scope landed and green; the DB-level overlap exclusion is the blocker.

## Escalation reason
- The target DB (SQL Server) has no native `EXCLUDE` constraint, so the half-open no-overlap
  invariant needs a `SERIALIZABLE` transaction + an `INSTEAD OF` trigger (an architectural decision,
  not a < 50-LOC bounded fix). I implemented + greened RBAC (AC-BKG-03) and read-scope (AC-BKG-04),
  but AC-BKG-02 needs an ADR on the isolation/trigger approach before I touch the migration. Tried:
  a unique index (can't express overlap), an app-level check (races under concurrent confirm — proven
  by a failing concurrency test). Beyond "small + clearly in scope" — escalating for an ADR + a
  follow-up ticket scoped to the trigger.

---
id: w1-be-01
produced_by: orchestrator-greenfield
produced_at: 2026-06-29T09:00:00Z
consumer_role: fixer-api
priority: high
area: backend
blocked_by: none
finding_ref: examples/walkthrough/02-contract/build-plan.md#b-bkg-1
---

# B-BKG-1 — Booking entity + guarded state machine + audit

> The ticket carries **pointers, not the full requirement.** The canonical AC/spec lives at
> `finding_ref`. The DIRECTORY is the status: this file sits in `done/` because it closed cleanly.
> (Worked example — keeps its `B-BKG-1` plan slug in the filename alongside the `w1-be-01` queue id.)

## Context

Create the `Booking` entity, its guarded state machine, and the append-only audit on status change
(cite `AC-BKG-01`, `AC-BKG-05`; `BKG-BR-002` —
`examples/walkthrough/01-kb/bookings/BKG-bookings-requirements.md:20`).

## Steps (chore)

1. Add `db/schema/bookings.prisma` (`Booking`, `BookingAudit`) + migration.
2. Add `apps/api/src/bookings/stateMachine.ts` with the legal-transition table; reject any pair not in it.
3. Wire `POST /bookings` and `POST /bookings/:id/transition`; status is never a free PATCH.
4. Write one append-only `BookingAudit` row per transition, transactional with the status change.

## Acceptance criteria (this ticket is done when)

- A new booking is `Requested`; only the four legal transitions succeed; all others are refused.
- Each transition writes exactly one audit row (old → new, actor, ISO timestamp).
- ACs to turn green: AC-BKG-01, AC-BKG-05.

## Pointers

- `apps/api/src/bookings/stateMachine.ts` — transition table + guard
- AC / spec ref — `examples/walkthrough/02-contract/design-spec.md` §7
- commit SHA (if referencing/reverting) — n/a

## Gate (must pass before `done/`)

```bash
pnpm typecheck && pnpm lint && pnpm --filter api test bookings && pnpm --filter contracts build
```

## Activity
- branch: be/bookings-state-machine-w1-be-01-s4f2a
- started: 2026-06-29T09:12:00Z
- notes: state machine + audit landed; tagged `checkpoint/pre-bookings-migration` before the migration.

## Resolution
- changed: added `bookings.prisma` (+ migration), `stateMachine.ts`, `service.ts`, `routes.ts`,
  `authority.ts`, `bookings.contract.ts`; one `BookingAudit` row per transition (transactional).
- commit: a1b2c3d
- gate: `typecheck + lint` clean; `pnpm --filter api test bookings` → 9 passed (state machine +
  audit, against the real test DB); `contracts build` clean. Green vs baseline.

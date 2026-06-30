# Build Plan — module `bookings`

> Filled worked example (see the blank template at `toolkit/contract/build-plan.md.tmpl`). Decomposes
> the design spec into bounded, single-module build tickets.

- **Spec:** `../02-contract/design-spec.md` · **ACs:** `AC-BKG-01..07`
- **Ticket families:** `B-BKG-N` (backend) · `F-BKG-N` (frontend)
- Tickets are filed as `<w-id>-<B/F-slug>-<kebab>.todo.md` into `.orchestrator/tasks/inbox/`
  (see `../03-tickets/`).

---

## Backend tickets

### B-BKG-1 — Booking entity + guarded state machine + audit

| Field | Value |
|-------|-------|
| Files | `apps/api/src/bookings/{stateMachine.ts,service.ts,routes.ts,authority.ts}`, `db/schema/bookings.prisma`, `packages/contracts/src/bookings.contract.ts` |
| Schemas | `CreateBooking`, `Transition`, `BookingResponse` (Zod; integrator regenerates types — do NOT bump version) |
| Seams appended | (1) schema · (2) api registry · (4) contracts index |
| Endpoints | see table below |
| ACs to turn green | AC-BKG-01, AC-BKG-05 |
| Gate | `pnpm typecheck && pnpm lint && pnpm --filter api test bookings && pnpm --filter contracts build` |

| Method | Path | Request | Response | Capability |
|--------|------|---------|----------|-----------|
| POST | `/bookings` | `CreateBooking` | `BookingResponse` | `booking.create` |
| POST | `/bookings/:id/transition` | `Transition` | `BookingResponse` | per-target (see spec §7) |

### B-BKG-2 — No-overlap-on-confirm constraint + RBAC + read-scope

| Field | Value |
|-------|-------|
| Files | `apps/api/src/bookings/{noOverlap.ts,readScope.ts}`, `db/schema/bookings.prisma` (exclusion constraint), `apps/api/src/bookings/authority.ts` |
| Schemas | none new (extends B-BKG-1) |
| Seams appended | (1) schema (migration only) |
| ACs to turn green | AC-BKG-02, AC-BKG-03, AC-BKG-04 |
| Gate | `pnpm typecheck && pnpm --filter api test bookings` |
| blocked_by | B-BKG-1 |

---

## Frontend tickets

### F-BKG-1 — Bookings list + request/confirm/reject controls

| Field | Value |
|-------|-------|
| Files | `apps/web/src/bookings/{BookingsPage.tsx,BookingForm.tsx}` |
| Imports | types from `packages/contracts` `api-types` (generated — never hand-write shapes) |
| Seams appended | (3) nav registry (one entry; unit test enforces unique keyboard chord) |
| ACs to turn green | AC-BKG-06 (UI), AC-BKG-07 |
| Gate | `pnpm typecheck && pnpm lint` + **live-app** verify `/bookings` (opt-in: no test, this is UI) |
| blocked_by | B-BKG-1 |

---

## Run plan (waves & branches)

This is a **greenfield build-from-spec** run: the B-/F- tickets above ARE the inbox, so there is **no
discovery wave** — fixers drain the queue starting at Wave 1. (In discovery/audit mode the numbering
shifts: Wave 1 = discovery, Wave 2 = fix, Wave 3 = re-verify — see PROTOCOL §1 / PLAYBOOK §4.)

| Wave | Runs | Parallelism | Tickets | Notes |
|------|------|-------------|---------|-------|
| **0 — Baseline + plan** | orchestrator captures baseline + writes this run-plan | orchestrator alone | — | Baseline keyed by HEAD SHA + `BASELINE-NOTES`. |
| **1a — Foundation (SOLO)** | data model + contracts + state machine + audit | 1 agent | B-BKG-1 | Tag a checkpoint **before** the migration. Lands alone so there's no race on the seams. |
| **1b — Build (PARALLEL)** | constraint/RBAC + the web surface | up to 3 agents | B-BKG-2, F-BKG-1 | Each owns its module globs; appends to seams; mocked API for web. No contracts version bump. |
| **2 — Re-verify** | re-run gates per branch | parallel | every branch from 1a/1b | Re-run the universal gate vs the baseline. Do NOT integrate. |

> **Integration is NOT a wave here.** Once Wave 2 is green, run `/kit-integrate` as a SEPARATE gated
> pass (pre-merge Opus pr-reviewer → merge in order → atomic-commit rewrite → integrator bumps the
> contracts version + regenerates openapi/api-types ONCE). See `../04-reports/INTEGRATION-REPORT.md`.

### Gate commands (the universal gate)

```bash
pnpm typecheck             # clean
pnpm lint                  # clean
pnpm --filter api test bookings   # protected-core tests green (state machine, overlap, RBAC, audit)
pnpm --filter contracts build     # contracts build clean
# F-BKG-1 is UI: live-app verify /bookings (opt-in testing — no spec)
```

Capture a **baseline** keyed by HEAD SHA + a `BASELINE-NOTES` listing pre-existing failures.

### Dependencies

- `B-BKG-2` and `F-BKG-1` cannot start until `B-BKG-1` is merged (the contract + schema + state
  machine must exist). Recorded in each ticket's `blocked_by`.

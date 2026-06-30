# Design Spec — module `bookings`

> Filled worked example (see the blank template at `toolkit/contract/design-spec.md.tmpl`). One spec
> per vertical-slice module, written AFTER the AC ledger and BEFORE the build plan.

- **Module:** `bookings` · **Owner globs:** see `MODULES.md`
- **Governing requirements:** `BKG-*` in `examples/walkthrough/01-kb/bookings/`
- **ACs in scope:** `AC-BKG-01..07` (from `../02-contract/acceptance-criteria.md`)

## 1. Context

Staff request a meeting room for a time window; an approver confirms or rejects. This module owns the
booking entity, its guarded lifecycle, the no-overlap rule, and the requester/approver authority
split. It deliberately does NOT do recurring bookings, catering, or external guests (`BKG-BR §1`). It
consumes the shared `audit` and `auth` infra modules.

## 2. Module shape & boundaries

| Aspect | Value |
|--------|-------|
| Owned globs (web · api · contracts · db) | `apps/web/src/bookings/**` · `apps/api/src/bookings/**` · `packages/contracts/src/bookings.contract.ts` · `db/schema/bookings.prisma` |
| Append-only seams touched | (1) schema · (2) api registry · (3) nav · (4) contracts index |
| Shared-infra consumed | `audit`, `auth` |
| Depends on (other modules) | none |

## 3. Data model

| Entity | Key fields | Notable constraints |
|--------|-----------|---------------------|
| `Booking` | `id` (pk), `room_id`, `requested_by`, `starts_at`, `ends_at`, `status` | `status` CHECK in (`Requested`,`Confirmed`,`Rejected`,`Cancelled`); `ends_at > starts_at` CHECK; **no two `Confirmed` rows for the same `room_id` with overlapping `[starts_at, ends_at)`** (exclusion constraint / guarded in the transition tx) |
| `BookingAudit` | `id` (pk), `booking_id` (fk), `old_status`, `new_status`, `actor_id`, `at` | append-only; in-band `UPDATE`/`DELETE` forbidden by trigger |

- **Append-only audit:** `status` is the audited field — one `BookingAudit` row per transition. Use the
  shared audit primitive; do not hand-log.
- **Temporal:** `[starts_at, ends_at)` is half-open; the no-overlap check uses half-open comparison
  (`a.starts_at < b.ends_at AND b.starts_at < a.ends_at`).

## 4. Contracts & API surface

```ts
// packages/contracts/src/bookings.contract.ts
export const CreateBooking = z.object({
  roomId: z.string(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
}).superRefine((v, ctx) => {
  if (v.endsAt <= v.startsAt) ctx.addIssue({ code: "custom", message: "endsAt must be after startsAt" });
});
export const BookingResponse = z.object({
  id: z.string(), roomId: z.string(), requestedBy: z.string(),
  startsAt: z.string(), endsAt: z.string(),
  status: z.enum(["Requested", "Confirmed", "Rejected", "Cancelled"]),
});
export const Transition = z.object({ to: z.enum(["Confirmed", "Rejected", "Cancelled"]) });
```

| Method | Path | Request schema | Response schema | Capability (RBAC) |
|--------|------|----------------|-----------------|-------------------|
| GET | `/bookings` | `ListQuery` | `BookingResponse[]` | `booking.read` (row-scoped) |
| POST | `/bookings` | `CreateBooking` | `BookingResponse` | `booking.create` |
| POST | `/bookings/:id/transition` | `Transition` | `BookingResponse` | per-target capability (see §7) |

> Status is **never** a free `PATCH`. There is no endpoint that sets an arbitrary status.

## 5. RBAC

| Capability | Roles that hold it | Row-level read-scope |
|-----------|--------------------|----------------------|
| `booking.read` | Requester, Approver | Requester → own only; Approver → all (`BKG-AUTH-004`) |
| `booking.create` | Requester, Approver | — |
| `booking.confirm` / `booking.reject` | Approver only (`BKG-AUTH-002`) | — |
| `booking.cancel` | Approver; Requester for own (`BKG-AUTH-003`) | Requester → own only |

"To change who can do X, edit the matrix row for X" — the matrix lives at
`apps/api/src/bookings/authority.ts`.

## 6. Audit

| Audited field | Trigger | Audit row content |
|---------------|---------|-------------------|
| `status` | on every transition | old → new, actor, ISO timestamp (`BKG-BR-005`) |

One row per transition; append-only; no in-band UPDATE/DELETE.

## 7. State machine

| From | To | Guard / who | Side effects |
|------|----|-------------|--------------|
| `Requested` | `Confirmed` | `booking.confirm` (Approver) **AND** no overlap (`BKG-BR-003`) | audit row; notify requester (`BKG-BR-004`) |
| `Requested` | `Rejected` | `booking.reject` (Approver) | audit row; notify requester |
| `Requested` | `Cancelled` | `booking.cancel` (Approver, or Requester for own) | audit row |
| `Confirmed` | `Cancelled` | `booking.cancel` (Approver, or Requester for own) | audit row |

Transition map lives at `apps/api/src/bookings/stateMachine.ts`. Any from/to pair not in the table is
rejected (`BKG-BR-002`).

## 8. Acceptance criteria sub-family

| AC id | Requirement (short) | Surface | Verified by |
|-------|---------------------|---------|-------------|
| AC-BKG-01 | guarded lifecycle | `[backend]` | `stateMachine.test.ts` (protected core) |
| AC-BKG-02 | no-overlap on confirm | `[backend]` | `noOverlap.test.ts` (protected core) |
| AC-BKG-03 | confirm/reject = Approver only | `[backend]` | `rbac.test.ts` (protected core) |
| AC-BKG-04 | row-level read scope | `[backend]` | `readScope.test.ts` (protected core) |
| AC-BKG-05 | one append-only audit row per transition | `[backend]` | `audit.test.ts` (protected core) |
| AC-BKG-06 | requester notified, plain language | `[both]` | `live-app: /bookings/:id` |
| AC-BKG-07 | list + controls render per capability | `[frontend]` | `live-app: /bookings` |

## 9. Open questions

- **May a Requester edit a pending request before approval?** The corpus is silent. Conservative
  default chosen: **no edit** — cancel + re-create. Logged to `docs/open-questions.md`.

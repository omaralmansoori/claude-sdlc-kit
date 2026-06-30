# Acceptance Criteria Ledger — Room Booking

> The **AC is the unit of "done."** Every criterion in the BRD for this area is copied here
> **verbatim**, given a stable id, tagged with the surface it touches and a delivery round, and
> linked to the **verification** that proves it. (Filled worked example — see the blank template at
> `toolkit/contract/acceptance-criteria.md.tmpl`.)

- **Area family:** `AC-BKG-NN` (stable; never renumber — append only).
- **Source:** `examples/walkthrough/01-kb/bookings/` (native requirement IDs preserved; cite `file:line`).
- **Surface tags:** `[backend]` · `[frontend]` · `[both]` · `[contract]`.
- **Delivery round:** which build round this AC is committed to (`R1`, `R2`, …).

> **Verification ref** holds a **test path** for protected-core ACs (state machine, RBAC, audit,
> temporal/SLA) and `live-app: <route>` for everything else. Testing is opt-in — see PLAYBOOK §7.

## Ledger

| AC id | Requirement (verbatim) | Source citation (native id + file:line) | Surface | Round | Verification ref |
|-------|------------------------|------------------------------------------|---------|-------|------------------|
| AC-BKG-01 | A new booking is created in `Requested`; the only legal transitions are `Requested → Confirmed`, `Requested → Rejected`, `Requested → Cancelled`, `Confirmed → Cancelled`; any other transition MUST be refused. | `BKG-BR-002` — `examples/walkthrough/01-kb/bookings/BKG-bookings-requirements.md:20` | `[backend]` | R1 | `api/src/bookings/stateMachine.test.ts` (protected core — state machine) |
| AC-BKG-02 | A booking may be `Confirmed` only if its room and time window do not overlap an already-`Confirmed` booking for the same room; overlap is half-open `[start, end)`. | `BKG-BR-003` — `examples/walkthrough/01-kb/bookings/BKG-bookings-requirements.md:24` | `[backend]` | R1 | `api/src/bookings/noOverlap.test.ts` (protected core — temporal) |
| AC-BKG-03 | `booking.confirm` / `booking.reject` are held by Approver only; a Requester attempt is refused at the API edge (HTTP 403). | `BKG-AUTH-002` — `examples/walkthrough/01-kb/bookings/BKG-bookings-rbac.md:16` | `[backend]` | R1 | `api/src/bookings/rbac.test.ts` (protected core — RBAC) |
| AC-BKG-04 | A Requester sees only bookings they created; an Approver sees all; read scope is enforced server-side and cannot be bypassed by guessing an id. | `BKG-AUTH-004` — `examples/walkthrough/01-kb/bookings/BKG-bookings-rbac.md:25` | `[backend]` | R1 | `api/src/bookings/readScope.test.ts` (protected core — RBAC) |
| AC-BKG-05 | Every status change writes exactly one append-only audit row (booking id, old status, new status, actor, ISO timestamp); the audit log is never updated or deleted in-band. | `BKG-BR-005` — `examples/walkthrough/01-kb/bookings/BKG-bookings-requirements.md:35` | `[backend]` | R1 | `api/src/bookings/audit.test.ts` (protected core — audit) |
| AC-BKG-06 | When a booking moves to `Confirmed` or `Rejected`, the requester is notified in plain language with no internal requirement IDs in the text. | `BKG-BR-004` — `examples/walkthrough/01-kb/bookings/BKG-bookings-requirements.md:30` | `[both]` | R1 | `live-app: /bookings/:id (confirm → toast + requester notice)` |
| AC-BKG-07 | The bookings list and the request/confirm/reject controls render for the persona's allowed capabilities. | `BKG-AUTH-001` — `examples/walkthrough/01-kb/bookings/BKG-bookings-rbac.md:14` | `[frontend]` | R1 | `live-app: /bookings` |

## Rules

1. **Verbatim.** Copy the criterion exactly as written — do not paraphrase. (Here the verbatim text is
   lightly trimmed only where one corpus sentence bundled several checks; the split is noted by the
   shared `file:line`.)
2. **One row = one testable assertion.** AC-BKG-01 split the lifecycle clause from the create-state
   clause; both cite `BKG-BR-002`/`BKG-BR-001`.
3. **Every AC maps to a verification.** Protected-core ACs (01–05: state machine, temporal, RBAC,
   audit) carry a test path; non-core ACs (06–07: notification UX, list rendering) carry `live-app:`.
4. **Stable ids, append-only.** Never renumber.
5. **Surface tag drives the ticket split.** `[backend]`→ B-ticket, `[frontend]`→ F-ticket, `[both]`→ both.
6. **Silence is logged, not invented.** The corpus is silent on whether a Requester may *edit* a
   pending request — logged in the design spec's open questions with a conservative default (no edit).

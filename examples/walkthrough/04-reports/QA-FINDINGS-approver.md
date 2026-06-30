# QA Findings - approver

> Filled worked example — the verbatim final message a Sonnet browser-tester emits for the `approver`
> persona under `/kit-qa` (the tester cannot write files, so its complete findings ARE its last
> message; the format follows `toolkit/qa/tester-brief.md.tmpl`). Below the findings is the
> orchestrator's mandatory **Phase-3 adversarial re-verification** of every Critical/RBAC claim.

Session summary: covered /bookings list, create→confirm→reject flows, and RBAC probes. Login worked: yes. Overall: core flow solid; one RBAC finding, one persistence finding.

## Critical
- A Requester (probed by URL/api as the approver session's lower-priv counterpart) could call `POST /bookings/:id/transition {to:"Confirmed"}` and it returned 200 instead of 403. | repro: as Requester, POST transition to a Confirmed | evidence: `POST /bookings/42/transition -> 200`, reload showed status `Confirmed` (persisted). Should be 403 per BKG-AUTH-002.

## High
- none

## Medium
- Confirming a booking that overlaps an existing Confirmed booking for the same room was allowed. | repro: confirm two overlapping windows for room R1 | evidence: `POST /bookings/43/transition -> 200`; both show Confirmed on reload. (Matches the known-open AC-BKG-02 / escalated ticket w1-be-02.)

## Low / Polish
- The confirm toast briefly shows the booking id in monospace; fine, but no internal requirement IDs leaked (BKG-BR-004 respected). | repro: confirm any booking | evidence: toast text "Booking confirmed — the requester has been notified."

## Passing controls (notable)
- approver correctly sees ALL bookings (read scope), Requester-only fields hidden. | evidence: `/bookings -> 200`, list includes other users' rows for approver.

## Console / Network noise log
- /bookings : no console errors; one `GET /bookings -> 200`.

---

## Phase 3 — adversarial re-verification (orchestrator, Opus, authenticated session)

The orchestrator does NOT trust the Sonnet findings raw. Re-driven each Critical/RBAC claim itself:

| Claim | Re-verified? | Evidence (POST status + hard reload) | Verdict |
|-------|--------------|--------------------------------------|---------|
| Requester can confirm (RBAC) | yes | as Requester: `POST /bookings/42/transition {to:Confirmed} -> 200`; hard reload → still `Confirmed`. Persisted, not optimistic UI. | **CONFIRMED Critical** — AC-BKG-03 regression. Filed `w2-be-07` (consumer_role: fixer-api, priority: critical). |
| Overlap allowed on confirm | yes | two overlapping confirms both `200`; reload shows both `Confirmed`. | **CONFIRMED** — already tracked (AC-BKG-02, escalated `w1-be-02`). No new ticket; linked. |
| Approver sees all bookings | yes | `GET /bookings -> 200` returns other users' rows; as Requester the same call returns only own rows. | **PASS** (AC-BKG-04 holds). |

**Corroboration matrix:** the RBAC critical was reported only by the approver tester but re-verified
independently by the orchestrator with a persisted POST — promoted to a confirmed Critical. The
overlap finding corroborates the known escalation. Report severities are evidence-backed, not raw
model output.

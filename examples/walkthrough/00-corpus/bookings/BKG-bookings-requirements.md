# Room Booking — Business Requirements (synthetic)

This is a **synthetic** requirement document for the worked example. It stands in for an
original `.docx`/`.pdf` in a real corpus. Native requirement IDs (`BKG-BR-*`) are preserved
verbatim so an agent can `rg -n "BKG-BR-002"` and land on the governing clause.

## 1. Scope

A small internal tool that lets staff request a meeting room for a time window, and lets an
approver confirm or reject the request. Out of scope: recurring bookings, catering, external
guests.

## 2. Lifecycle

**BKG-BR-001** A booking has exactly these states: `Requested`, `Confirmed`, `Rejected`,
`Cancelled`. A new booking is created in `Requested`.

**BKG-BR-002** The only legal transitions are: `Requested → Confirmed`, `Requested → Rejected`,
`Requested → Cancelled`, and `Confirmed → Cancelled`. Any other transition MUST be refused. A
status is never set by a free update — it changes only through the transition action.

**BKG-BR-003** A booking may be `Confirmed` only if its room and time window do not overlap an
already-`Confirmed` booking for the same room. Overlap is half-open: `[start, end)`, so a
booking ending at 10:00 and one starting at 10:00 do not overlap.

## 3. Notification

**BKG-BR-004** When a booking moves to `Confirmed` or `Rejected`, the requester is notified.
The notification text is plain language and MUST NOT contain internal requirement IDs.

## 4. Audit

**BKG-BR-005** Every status change writes exactly one append-only audit row capturing: booking
id, old status, new status, the actor, and an ISO-8601 timestamp. The audit log is never
updated or deleted in-band.

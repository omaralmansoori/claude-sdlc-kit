> Source: bookings/BKG-bookings-rbac.md

# Room Booking — Authority Matrix / RBAC (synthetic)

Synthetic companion to the requirements doc. Native IDs `BKG-AUTH-*` are preserved verbatim.

## Roles

- **Requester** — any staff member. Creates booking requests; sees their own bookings.
- **Approver** — facilities staff. Confirms / rejects requests; sees all bookings.

## Authority matrix

**BKG-AUTH-001** Capability `booking.create` is held by Requester and Approver.

**BKG-AUTH-002** Capability `booking.confirm` and `booking.reject` are held by **Approver only**.
A Requester attempting to confirm or reject MUST be refused at the API edge (HTTP 403), not
merely hidden in the UI.

**BKG-AUTH-003** Capability `booking.cancel` is held by the Approver, and by the Requester **only
for their own** bookings (row-level scope).

## Read scope

**BKG-AUTH-004** A Requester sees only bookings they created. An Approver sees all bookings.
Read scope is enforced server-side and cannot be bypassed by guessing an id.

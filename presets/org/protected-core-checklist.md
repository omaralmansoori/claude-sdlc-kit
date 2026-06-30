# Protected-Core Checklist (preset — statutory / child-protection)

This is the **non-negotiable** core for a statutory, child-protection case-management domain.
Everything here is "protected core": a silent error in any of these is not a bug, it is a
**statutory failure**. The core kit already names protected core as the trigger for opt-in
testing — this preset enumerates exactly what protected core *is* for ORG, and demands a
**passing test** for each item, run against a **real database**, not a mock.

Use it as a literal checklist. Every box must be backed by an executable gate before the
feature that touches it is allowed to merge.

---

## 1. The case lifecycle is a guarded STATE MACHINE — never a free status PATCH

- [ ] Status transitions are modeled **explicitly** with named states and named transitions:
      `Intake -> Assessment -> Planning -> Execution & Monitoring -> Closure`, plus the
      cross-stage transitions (transfer, handover, emergency committee, urgent plan, early
      closure). Cite the governing `ORG-*` requirement on each transition.
- [ ] Each transition has a **guard** (preconditions + who may perform it). An illegal
      transition is **rejected**, not silently applied.
- [ ] `status` is **never** a free `PATCH` field. There is no endpoint that lets a client set
      an arbitrary status. State changes go only through the transition API.
- [ ] **Test (real DB):** every legal transition succeeds; every illegal transition is refused;
      guards are enforced; a transition emits its audit rows (see §3). A wrong transition that
      "looks fine in the UI" must fail a test.

## 2. The Authority Matrix is RBAC — a capability matrix + row-level read-scope

- [ ] The BRDs ship explicit **Authority Matrices** (who may do what, per stage/role). Implement
      them as a **capability matrix** (role x capability), **not** scattered `if (role === ...)`
      checks. "To change who can do X, edit exactly here" must hold true.
- [ ] **Row-level read-scope** is enforced server-side: a user sees only the cases/records their
      role and assignment scope permit. Read-scope is not a UI filter the client could bypass.
- [ ] In-app roles are mapped from the identity provider's claims through **one** explicit table
      (see `auth-entra-adr.md.tmpl`), deny-by-default for unmapped claims.
- [ ] **Test (real DB):** for each role, allowed capabilities pass and forbidden ones are
      refused at the API edge; row-level scope hides out-of-scope rows even when the ID is
      guessed. RBAC claims from QA are **re-verified** by the orchestrator (POST status +
      hard-reload), never trusted from UI optimism.

## 3. AUDIT is append-only — one row per changed field, no in-band UPDATE/DELETE

- [ ] Every audited field change writes **exactly one** audit row — never zero, never two —
      capturing: entity, field, old value, new value, actor, timestamp, and the transition/
      action that caused it.
- [ ] The audit table is **append-only**: `UPDATE` and `DELETE` on it are forbidden **in-band**
      and enforced by **database triggers/rules**, not merely by application convention. A
      tamper attempt fails at the DB, not just in code review.
- [ ] Audit writes are **transactional** with the change they record — you cannot persist a
      data change without its audit row, and vice versa.
- [ ] **Test (real DB):** a single-field edit yields exactly one row with correct before/after;
      a multi-field edit yields one row per changed field; a direct `UPDATE`/`DELETE` against
      the audit table is rejected by the trigger.

## 4. Configurable FORMS / MEASURES + scoring is a data-driven engine — scoring-as-data

- [ ] Clinical instruments, questionnaires, and "configurable forms & measures" are driven by a
      **data-driven form/measure engine**, **not** hardcoded forms. Definitions are data.
- [ ] Form/measure definitions are **versioned**. Editing an instrument creates a new version;
      prior versions and the responses tied to them are preserved (you can always re-derive a
      historical score from the version that was in force).
- [ ] **Scoring is data, not code:** item weights, reverse-scored items, subscale groupings, and
      cut-off thresholds are stored as part of the versioned definition and evaluated by a
      generic scorer — changing a threshold is a data/version change, not a code deploy.
- [ ] OCR'd Arabic instruments are **verified against the canonical source** before their scoring
      is trusted (see `i18n-rtl.md`).
- [ ] **Test (real DB):** known responses produce known scores for a given version; a version
      bump does not retroactively change historical scores; reverse-scored/cut-off logic is
      exercised with boundary cases.

## 5. SLA / TEMPORAL math is protected core — test against a real DB

- [ ] SLA windows, scheduling, visitation windows, deadlines, escalation timers, and
      eligibility-by-date are computed by explicit, **unit-of-time-correct** logic (time zone,
      working days/holidays, inclusive/exclusive bounds all decided and documented per the
      corpus).
- [ ] Breach / overdue state is **derived and tested**, and surfaces only through the reserved
      critical-alert affordance (see `brand.md` — Red is for alerts only).
- [ ] **Test (real DB, never a mock clock-of-convenience):** boundary cases (exactly-on-deadline,
      DST changes if relevant, weekend/holiday spanning, leap dates) produce the correct
      due/overdue/eligible results. Date math is tested directly against a real database, not a
      stubbed repository.

## 6. Data residency + governed document storage

- [ ] Application data and the database sit **in-region**, **pinned** to the approved government
      hosting boundary / region. Data residency is a deployment-gate, recorded in the infra ADR.
- [ ] Sensitive case files / documents (custody, child-protection attachments) use **governed
      document storage** within the approved boundary, with access mediated by the same
      Authority Matrix and read-scope as the records they belong to — not a public bucket, not a
      personal drive.
- [ ] **Heavy-QA box must sit inside the approved hosting boundary** for any non-synthetic data.
      A personal remote QA box is acceptable **only** for synthetic seed data; regulated/PII data
      must never leave the approved boundary (see the core kit's heavy-QA data-residency caveat).

## 7. External-LLM gate — decide whether PII may leave the boundary AT ALL

- [ ] Before any feature sends case data to an external LLM/API, **explicitly evaluate whether
      external LLM calls are permissible for this data at all.** For statutory child-protection
      PII the default answer is **no** unless a governance decision says otherwise.
- [ ] If external inference is used, it is restricted to **non-PII / synthetic** inputs, or an
      **in-boundary** model, with the decision recorded in an ADR and enforced (not left to
      developer discretion at call sites).
- [ ] **Test / guard:** a code path that would send identifiable case data to an out-of-boundary
      service is blocked by policy (lint rule, egress control, or interface that forbids PII in
      the payload), not merely discouraged in a comment.

---

## How this checklist is enforced

- **Protected core triggers tests.** Per the core methodology, testing is opt-in *except* for
  protected core — and **every item above is protected core**. No box is "done" without a
  passing, executable gate.
- **Tag before you touch it.** Tag a checkpoint **before** any change to the state machine,
  Authority Matrix, audit schema, forms/measures engine, SLA math, or migrations — these are
  exactly the protected-core surfaces the core kit says to checkpoint.
- **Re-verify, don't trust.** Critical and RBAC findings from QA are re-verified in an
  authenticated orchestrator session (POST status + hard-reload to prove persistence vs
  optimistic UI) before they are believed.
- **Provenance.** Each item's implementation cites its governing `ORG-*` / `DC_*` requirement in
  a code comment — never in a user-facing string.

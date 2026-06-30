# CONTEXT-INDEX.md — on-demand read index for orchestrator-protocol

The orchestrator and every sub-agent consult THIS file. Sub-agents fetch other sources **only when a trigger fires**. As of LESSONS L22 (the targeted-brief revision), TIER-0 is no longer eager — it is a fallback for the case where the orchestrator failed to inline what the sub-agent needed.

Four tiers (was three before L22):

- **Inlined (always, via brief composer):** the orchestrator inlines hard rules, today/infra/auth, wave/queue, and per-profile `inline_keys:` content into every brief. Sub-agents read these from the brief, NOT from the source files.
- **TIER-0 (fallback only):** the static sources the inlined content came from. Read these only if you find the inlined version contradicts itself or is clearly out of date. Default: do not read.
- **TIER-1 (role-keyed escape hatch):** fetch when your profile's `index_keys:` references it AND a surprise during work makes it relevant.
- **TIER-2 (trigger-keyed):** fetch only when the named trigger applies to your task.

Sub-agents quote the matched key(s) in their report-back's `Index keys consumed:` line so the operator can audit the actual read budget.

---

## Inline-key registry

The orchestrator's brief composer reads these sources, extracts the named snippet, and inlines it into the brief's "Inlined facts" section. Profiles reference these by name in their `inline_keys:` field.

| Inline key | Source | What it gives the sub-agent |
|---|---|---|
| `hard-rules` | `PROTOCOL.md` §6.1 | Universal hard rules (~15 lines). Inlined into EVERY brief regardless of profile. |
| `code-conventions` | Project root `CLAUDE.md` "## Code conventions" heading | Project's typing / palette / icon / commit rules. Inlined for fixers and reviewers. |
| `palette-rules` | Project root `CLAUDE.md` palette bullet | Just the colour + emoji rules. Subset of `code-conventions`. Useful for frontend-only profiles that don't need backend conventions. |
| `msw-rules` | `apps/web/CLAUDE.md` MSW section (if present) | MSW conformance rules. Inlined for `fixer-web` and `qa-playwright`. |
| `wave-mode-and-queue` | Computed by the orchestrator at compose time | Current wave number + inbox path + gate command. Inlined for every consumer. |
| `today-infra-auth` | Computed by the orchestrator at compose time | Date + infra one-liner + auth one-liner. Inlined into EVERY brief. |
| `triage-rubric` | `PROTOCOL.md` §4 "Triage rubric" block | Test bug / product bug / spec gap / infra flake table. Inlined for producers and re-verifiers. |

**Producers may ADD new inline keys** when a sub-agent reports that the same project-fact was needed across two missions in a row. Procedure: append a row here with a source path + a one-line description, and the profile that needs it adds the key to its `inline_keys:` list.

---

## TIER-0 — Fallback only

These were eager reads in the pre-L22 protocol. They are now references the sub-agent consults ONLY if the inlined version in its brief is missing, contradictory, or obviously stale. Default behaviour: do not read.

| Key | Source | What it gives you (when you DO need it) |
|---|---|---|
| `t0-protocol-core` | `PROTOCOL.md` §1, §4, §5, §6 | Wave model, sub-agent contract, report-back shape, universal hard rules. (§6 is also inlined as `hard-rules`.) |
| `t0-project-flags` | Project root `CLAUDE.md` — "## Architecture" + "## Code conventions" headings | Removed features, palette/lint rules, infra ports. (`code-conventions` covers the second heading inline.) |
| `t0-index` | This file | Self-reference; cites trigger keys when fetching more. |

Default size: ~200 lines combined. Skip entirely in the happy path.

---

## TIER-1 — Role-keyed

Fetch by `index_keys:` declared in the agent profile (`agent-profiles/<role>.yaml`).

| Key | Source | Who triggers it |
|---|---|---|
| `t1-isolation` | `PROTOCOL.md` §11 (cross-session git isolation) | every fixer / re-verifier / integrator that creates branches |
| `t1-commit-discipline` | `PROTOCOL.md` §12 | every agent that commits (producer that adds specs, fixer, integrator) |
| `t1-pr-review-gate` | `PROTOCOL.md` §13 | `pr-reviewer.yaml` only |
| `t1-logging-contract` | `PROTOCOL.md` §15 | `qa-playwright`, `log-reader-triage`, any backend fixer that adds new error paths |
| `t1-integration-template` | `templates/integration-report.md.tmpl` | `/integrate` runs only — NEVER for `/orchestrate` |
| `t1-queue-protocol` | `queue/README.md` | every consumer (re-pickup / re-close protocol details) |
| `t1-ticket-template` | `templates/ticket.todo.md.tmpl` | every producer that files tickets |
| `t1-package-claude-md` | `apps/<package>/CLAUDE.md` for the package you edit | fixers only — load ONLY the package CLAUDE.md whose code you touch |

---

## TIER-2 — Trigger-keyed

Fetch ONLY if the trigger applies. The trigger is a question; if the answer is no, do NOT read.

| Key | Source | Trigger (read when) |
|---|---|---|
| `t2-lessons-L11` | `LESSONS.md` L11 | you set up or modify logging infra |
| `t2-lessons-L17` | `LESSONS.md` L17 | you write tests that cross more than one surface (e.g. API + web in same flow) |
| `t2-lessons-L18` | `LESSONS.md` L18 | you touch MSW handlers OR mock/real-API conformance |
| `t2-lessons-L19` | `LESSONS.md` L19 | you touch the client-side error sink / fatal error path |
| `t2-lessons-L20` | `LESSONS.md` L20 | you are doing session cleanup OR a consolidator at session close |
| `t2-tooling-assessment` | `TOOLING-ASSESSMENT.md` | the operator asks "which code-intel / swarm tool should we use" |
| `t2-user-guide` | `USER-GUIDE.md` | the operator is choosing the orchestrator tier (light vs harness) |
| `t2-harness-mode` | `harness-mode/README.md` + matching protocol | mission is BRD-driven multi-week with a live dashboard (rare) |
| `t2-adr-context` | `docs/guides/adr-context.md` (or the project's ADR tree) | you touch a symbol cited in an ADR |
| `t2-prior-readiness-report` | most-recent `*-READINESS.md` / `*-DELIVERY-REPORT*.md` | re-verifier, pr-reviewer, consolidator |
| `t2-orch-state` | `.orchestrator/state.md` | you need to know which wave is current OR what prior agents claimed |
| `t2-project-memory` | `~/.claude/projects/<slug>/memory/MEMORY.md` (the index, NOT the per-memory files) | every agent at start — but read ONLY the index, fetch a per-memory file only when its description matches your task |
| `t2-open-questions` | `docs/open-questions.md` | escalation step; check before filing an `escalate` ticket so you don't dupe |

---

## GitNexus replaces grep-and-read

When the trigger says "fetch X by file:line", or when you need to know what a symbol does / who calls it / what breaks when you change it — DO NOT grep + read. Use GitNexus instead. See [`templates/gitnexus-stanza.md`](templates/gitnexus-stanza.md) for the verbatim block injected into every brief whose profile has `code_intelligence: gitnexus`.

Headline tools (consult the project's `CLAUDE.md` "GitNexus" section for the full list):

- `gitnexus_query({query: "concept"})` — find execution flows ranked by relevance. Use **instead of grep** when exploring.
- `gitnexus_context({name: "symbolName"})` — full context on a symbol (callers, callees, processes).
- `gitnexus_impact({target: "symbol", direction: "upstream"})` — **mandatory** before any product-symbol edit.
- `gitnexus_detect_changes()` — **mandatory** before commit; verifies your change-set is what you intended.
- `gitnexus_rename` — for renames; never find-and-replace symbols.

If `gitnexus_query` warns the index is stale, the agent runs `npx gitnexus analyze` once and notes the result in its report.

---

## How a sub-agent uses the index (the contract)

1. **TIER-0 reads** happen at brief-acknowledgement (3 sources, ~200 lines total).
2. **TIER-1 reads** happen only for the keys in the profile's `index_keys:`. The brief template lists them by name; the agent fetches them in parallel.
3. **TIER-2 reads** happen on-demand. The agent evaluates each trigger against its current sub-task; if no, it does not read.
4. **Symbol-shaped reads** go through GitNexus, not grep + Read.
5. **Report-back** includes a line: `Index keys consumed: t0-…, t1-…, t2-…` so the operator can see the actual read budget.

---

## How a producer ADDS a new index entry

When a sub-agent discovers a context source that future agents will need (e.g. a new ADR, a new lessons entry, a new architectural doc), it appends one row to the appropriate tier with a `trigger:` cell. The orchestrator commits this in the same atomic infra commit that closes the run. NEVER add an entry without a trigger — entries without triggers regress us back to eager-reads.

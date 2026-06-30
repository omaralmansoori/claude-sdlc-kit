# LESSONS — methodology-level rules

The hard-won rules that shape *how the method is run*, distilled to the level a leader or a new operator needs. These are the principles; the **detailed, numbered, engine-level lessons** (with originating incidents and exact hooks) live in `skills/orchestrator-protocol/LESSONS.md` and are referenced here by `L<N>` — read those for the why-behind-the-why. This file does **not** renumber or duplicate them.

> Format: each rule leads with the imperative, then the one-paragraph reason, then the engine-lesson cross-reference.

---

## 1. Worktree isolation is non-negotiable

Every sub-agent runs in its **own git worktree**. The main tree is read-only for sub-agents. Branch names embed the session short-id so two concurrent sessions cannot collide. The moment agents share a working tree they swap `HEAD` mid-edit, clobber each other's appends, and leak commits onto the wrong branch — and you pay back the parallelism speedup with a day of untangling. There is no "lightweight" exception worth the risk; isolation is the default and an override needs a written reason in the brief.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L1**, **L11**.

## 2. The ticket queue is the only shared state

Coordination between parallel agents flows through **one** append-only surface: the ticket queue. Everything else an agent touches, it owns. Tickets are never deleted (a mistake becomes a new ticket); producers never edit their own queued tickets; lifecycle is encoded by **directory** (`inbox/ → in-progress/ → done/` or `escalated/`), not a mutable status field; and the canonical requirement lives in the KB, referenced by `finding_ref` — the ticket carries pointers, not the requirement. When the only shared mutable state is a queue you append to, there is nothing left to race on.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L9**, **L15**; queue contract in `skills/orchestrator-protocol/queue/README.md`.

## 3. The four seams are append-only, and `merge=union` makes them conflict-free

Cross-module coordination happens through exactly four shared files — the per-module DB schema dir, the API registry, the nav registry, and the contracts schema + index export. Each agent **appends one line** and never edits another module's lines. `.gitattributes` with `merge=union` on these docs resolves pure-append collisions automatically. The day someone edits inside another module's seam region instead of appending to their own is the day the union driver can't save you.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L2** (pre-commit `.gitattributes`/`.gitignore` before Wave 1).

## 4. The contracts version bump is the coordination signal — and only the integrator bumps it

The contracts package is the single source of truth for request/response shapes, and its `package.json` version bump is the backend↔frontend coordination signal. **Parallel agents do not bump it and do not regenerate OpenAPI/types.** The integrator does that **once**, at merge. This is the rule that removes the *last* shared-file collision: if every agent could regenerate the contract, every agent would conflict on it. Defer the bump, centralize it, and parallelism stays clean.

→ See `PLAYBOOK.md` §4–§5; `toolkit/conventions/contracts-package-CLAUDE.md.tmpl`.

## 5. Gates are executable, not vibes

The orchestrator **runs** the gates — typecheck + lint clean, unit tests green, browser/e2e green, contracts build clean — and never trusts an agent's self-declared "done." Capture a baseline keyed by HEAD SHA plus a `BASELINE-NOTES` list of pre-existing failures, so a regression is distinguishable from a red that was already there. Every commit must be independently green. "The agent said it passed" is not a gate; the gate is the command and its exit code.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L12** (logical-boundary green commits).

## 6. Integration is a separate run

Merging N branches is **not** a wave of the build run — it is its own invocation with its own order, its own reviewer, and its own atomic-rewrite phase. It merges in documented order, then re-emits the result as **atomic conventional commits** via cherry-pick by file-set, so the final history reads clean per-concern instead of as a merge swamp. It explicitly **does not push and does not open a PR** — the output is a local branch for the operator to review. Mixing integration into discovery muddles both.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L4**, **L10**; command `/kit-integrate`.

## 7. A senior reviewer gates the merge, on Opus

Before integration, an Opus `pr-reviewer` sees the whole diff and **blocks on any critical/high finding** (filing them as new tickets). Real SDLC has a senior reviewer who gates merge; putting that role on the strongest model buys depth where it matters most. An integration run that no second eye examined is not reviewed — it is merely merged.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L13**.

## 8. Tag before you touch protected core

Protected core = the state machine, authority/RBAC, audit invariants, temporal/SLA math, and scoring. Before **any** change to these — or to schema or migrations — tag a checkpoint. A silent wrong transition or a broken audit invariant is a statutory-grade failure, and you want a labeled point to roll back to that you didn't have to reconstruct. Tag first, change second.

→ See `PLAYBOOK.md` §5; `presets/org/protected-core-checklist.md` for a worked protected-core list.

## 9. Heavy QA must be adversarially verified — Phase 3 is what makes the report trustworthy

The browser-tester farm runs N Sonnet sessions confined to `mcp__playwright` (the safety boundary — they cannot touch code, DB, or files, so each emits findings as its final message). But the Opus orchestrator does **not** trust those findings raw. It re-verifies **every Critical/RBAC claim in its own authenticated session**, capturing the POST status and doing a hard reload to prove *persistence* versus an optimistic-UI illusion, then reconciles severities across personas into a corroboration matrix *before* writing the report. The verification pass — not the test run — is what makes the report something a leader can act on.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L17** (cross-surface session bugs that isolated specs miss); QA pillar `toolkit/qa/`.

## 10. The remote-QA plumbing must be a committed script, not tribal knowledge

In the original project, the "run the QA farm on a remote box over an SSH tunnel" recipe was **never committed** — it lived in the operator's head, and every new run reinvented it. The kit's fix: the **local recipe is canonical**, and the remote launcher is shipped as a real, version-controlled artifact (`toolkit/qa/remote-qa-launcher.sh`). If a step only exists in someone's memory, it does not exist. **Data-residency caveat:** a personal remote box is fine for **synthetic** seed data only; for regulated/PII data the QA box must sit inside the approved hosting boundary.

→ See `PLAYBOOK.md` §6; `toolkit/qa/parallel-browser-qa.md`.

---

## 11. Sub-agent briefs are self-contained; the orchestrator is a composer, not a dispatcher

The orchestrator inlines the hard rules, the targeted work map (`file:line` + callers, pre-resolved), the ACs to turn green, and the gate commands directly into each brief. A well-briefed agent starts working at tool-call one — no exploratory re-reading. The expensive habit in naive agent work is re-orienting; a self-contained brief eliminates it. This is the operational payoff of having a knowledge base in the first place: requirements are addressable, so they can be inlined.

→ Engine: `skills/orchestrator-protocol/LESSONS.md` **L21**, **L22**.

## 12. Provenance everywhere; never leak spec refs to users

Every implemented requirement names its source — a `file:line` citation back to the KB — in the code comment and the commit. But internal requirement IDs **never** appear in a user-facing string, toast, error, or label. Provenance is for the reviewer and the auditor; the user sees plain language. This was a real defect class — guard it deliberately.

→ See `PLAYBOOK.md` §8 (Definition of Done) and §7 (Testing policy).

---

### How to extend this list

Methodology-level lessons — the kind a *new operator* needs to run the method correctly — go here, in the `Rule / Why / cross-ref` shape. Incident-level, engine-tuning lessons (read budgets, profile fields, exact script behaviour) go in `skills/orchestrator-protocol/LESSONS.md` with a numbered `L<N>` and a precise hook. When in doubt: if it changes *how the framework is run*, it is a methodology lesson; if it changes *how the engine is wired*, it is an engine lesson.

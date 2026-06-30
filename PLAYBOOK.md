# PLAYBOOK — From BRD to tested app

The full narrated method, in loop order. Each stage names the kit files that implement it so you can go from "I understand the idea" to "I am running it" without guessing.

> The one-screen version is at the bottom (§9). Read the rest once; keep §9 open while you run.
>
> **See it once, end-to-end:** [`examples/`](examples/) carries one tiny vertical slice (a Room
> Booking feature) through every stage below — mini-corpus → generated KB → filled contract → sample
> tickets (`done/` + `escalated/`) → integration + QA reports. Read it alongside this playbook so each
> stage's prose has a concrete artifact next to it.

---

## 0. Roles, and why this isn't just "spawn a bunch of agents"

Naive parallelism fails in three predictable ways: agents re-read the same source docs until the context window thrashes, they invent requirements no document states, and they edit the same files and clobber each other. This method removes each failure mode with a structural fix, not a prompt:

| Failure mode | Structural fix |
|---|---|
| Context thrash | A **knowledge base** (§1) — one converted, grep-able corpus. Agents fetch by requirement ID, not by re-reading documents. |
| Hallucinated requirements | A **development contract** (§2–3) — every acceptance criterion is copied verbatim from the KB and carries provenance back to a `file:line`. |
| Agents stepping on each other | **Worktree isolation + four append-only seams** (§4). The shared ticket queue is the *only* shared mutable state. |

The cast maps onto a normal software org so the process is legible to anyone who has shipped software:

| Kit role | SDLC analogue | Owns |
|---|---|---|
| Operator (you) | Eng lead / TPM | The mission, approvals, the gates being real |
| Orchestrator (Opus) | Tech lead | Wave planning, brief composition, running gates, the report |
| Discoverer | Senior dev on triage | Files tickets, does NOT fix |
| Fixer-api / Fixer-web | Developers | Drain the queue inside isolated worktrees |
| Re-verifier | QA | Re-runs gates per branch, does NOT integrate |
| Integrator | Release engineer | The one actor that merges and bumps the contract version |
| PR-reviewer (Opus) | Senior reviewer | Pre-merge gate; blocks on any critical/high finding |
| Browser testers (Sonnet) | QA pool | Headless Playwright sessions, browser-only |

The engine for all of this is the vendored **orchestrator-protocol** skill (`skills/orchestrator-protocol/`). This playbook is the BRD-to-app *story*; that skill is the *contract*. When they disagree on a detail, the skill's `PROTOCOL.md` wins.

---

## 1. BRD → an agent-searchable knowledge base

**Goal:** turn a folder of heterogeneous requirement documents into a markdown corpus an agent can navigate by requirement ID with full provenance.

The corpus is messy as a matter of reality: `.docx`, `.pptx`, `.pdf`, `.xlsx`, `.vsdx`, often bilingual (including Arabic), sometimes degraded scans needing OCR. You do **not** let agents parse the originals — you convert once, deterministically, and point every agent at the output.

### The tooling

- **markitdown** (Microsoft, MIT) converts `.docx/.pptx/.pdf/.html → markdown`. Install it isolated and pinned:
  ```bash
  pipx install --python python3.13 'markitdown[docx,pptx,pdf,xlsx,xls]'
  ```
  Pin **Python 3.13** — 3.14 has wheel gaps. The kit verifies version **0.1.6**. `toolkit/ingestion/setup.sh` does this for you.
- **Quirk to handle:** markitdown inlines embedded images as base64 `data:` URIs, which bloat the markdown and poison grep. `toolkit/ingestion/strip_data_uris.py` removes them in post-process.
- **Gaps the kit fills:** markitdown does not read `.vsdx` (Visio) and does not split `.xlsx` per-sheet cleanly. The kit ships custom extractors: `toolkit/ingestion/extractors/vsdx_to_md.py` and `extractors/xlsx_to_md.py`.

Driver: `toolkit/ingestion/ingest.py`. Index generator: `toolkit/ingestion/gen_index.py`. Agent-facing skill: `skills/corpus-ingestion/SKILL.md`. Operator command: `/kit-ingest`.

### The conventions that make it agent-searchable

These are non-negotiable; they are what turn "a pile of markdown" into a source of truth:

1. **Mirror the source tree.** The KB folder layout matches the original folder layout — a human who knew the docs can navigate the KB.
2. **Preserve native requirement IDs verbatim** as headings and grep targets — `ORG-CM-ACA-BR001`, `DC_007`, `FCS-CMD-PRC-1.1`. These become the addressing scheme for the entire build.
3. **Every converted doc opens with a `> Source:` line** back to the original file. Provenance is structural, not optional.
4. **A master `INDEX.md`** (a one-line-per-section map) plus a **per-area `_manifest.md`** recording the conversion method and any quality caveats (e.g. "OCR'd from a degraded scan — verify clinical scoring against the canonical instrument").
5. **Dual-capture process flows:** the ordered step text (logic you build from) *and* a rendered `png`/`pdf` (preserves arrow topology and branches the text loses). Cite both.
6. **Explicit Excluded + dedup rules.** Stale and `-OLD-` documents are listed as excluded; canonical-copy rules resolve duplicates. An agent that cites an excluded doc has cited a requirement that no longer holds.

**Done when:** an agent can run `rg -n "<requirement-id>" <kb>/` and land on the governing text with a source line, and `INDEX.md` routes a human to any area in one hop.

---

## 2. Brainstorm → spec

Take **one vertical slice** at a time — a thin end-to-end capability, not a layer. Begin from the KB, not from a blank page.

1. **Brainstorm the slice** (use `superpowers:brainstorming`): what does this slice do, for whom, governed by which requirement IDs? Cite them from the KB. If the corpus is silent on a behaviour, log an open question and pick a conservative default — never guess statutory or contractual behaviour.
2. **Write the acceptance-criteria ledger** from `toolkit/contract/acceptance-criteria.md.tmpl`. Copy **every criterion verbatim** from the KB. Each gets:
   - a **stable ID** in a per-area family,
   - a **surface tag** — `[backend]` / `[frontend]` / `[both]` / `[contract]`,
   - a **delivery round**,
   - a **verification ref** — a test path for protected-core ACs, else `live-app: <route>`.
   The AC is the unit of "done". Each criterion must map to a **verification** before the slice is
   done (a passing test when it touches the protected core, otherwise live-app — see §7). This ledger
   is the contract between the requirement and the code.
3. **Write the design spec** from `toolkit/contract/design-spec.md.tmpl`: the data model, the state machine if the slice has lifecycle, the contract shapes, the authority/RBAC surface. If your domain has a real data model, this is where the **data-schema** skill (`skills/data-schema/`) plugs in — design the schema *before* you decompose into tickets, and generate the contract layer *from* it rather than hand-mirroring.

**Done when:** the design spec exists, and every AC in the ledger has an ID, a surface, a round, and a one-line "how we'll prove it".

---

## 3. Plan

Two registries plus one plan turn the spec into parallelizable work.

1. **Module ownership registry** — `toolkit/conventions/MODULES.md.tmpl`. A glob-based map of **vertical-slice modules**: each module owns a set of globs, and no two modules' globs overlap. This is what lets agents run in parallel without a coordinator — ownership is declared, not negotiated.
2. **Build plan** — `toolkit/contract/build-plan.md.tmpl`. Decompose the spec into **B-** (backend) and **F-** (frontend) tickets. Every ticket lists, with no placeholders:
   - exact **Files** it will touch (inside its module's globs),
   - the **schemas** it adds or changes,
   - an **endpoint table** (method, path, request/response contract),
   - the **ACs to turn green**,
   - the **gate commands** that prove it.
3. **Tickets.** There is **one ticket schema**, not two. Both templates
   (`toolkit/contract/ticket.todo.md.tmpl` and the engine's
   `skills/orchestrator-protocol/templates/ticket.todo.md.tmpl`) share the same
   `id: w<wave>-<workstream>-<seq>` frontmatter; the build-time form only adds a `## Gate` block (the
   gate commands) and a `## Context` pointer. A planned **B-/F-** ticket from the build plan (e.g.
   `B-CM-1`) is filed into `inbox/` using the runtime frontmatter, **keeping its B-/F- slug in the
   filename** — e.g. `w1-be-01-B-CM-1-case-state-machine.todo.md` — so the plan id and the queue id
   stay linked.

A ticket that can't name its exact files and its ACs is under-specified — fix the plan, don't spawn the agent.

**Done when:** every AC for the round maps to at least one ticket, and every ticket sits inside exactly one module's globs.

---

## 4. Parallel, worktree-isolated build

This is the part that makes or breaks parallelism. The rules below are not style — they are the difference between a clean merge and a day lost to clobbered branches (see `LESSONS.md` L1/L2).

### The four append-only seams

Every module agent owns its globs and appends **exactly one line** to each shared seam, never editing another module's lines. Four seams cover all cross-module coordination:

| # | Seam | The one line you append |
|---|---|---|
| 1 | **DB schema** | Your module's schema file in a multi-file schema dir (a `_base` file holds cross-cutting models). |
| 2 | **API registry** | One module-registry line wiring your routes in. |
| 3 | **Nav registry** | One nav line. A unit test enforces unique keyboard chords across all nav entries. |
| 4 | **Contracts** | One schema file + one index-export line in the contracts package. |

`.gitattributes` with `merge=union` on these append-only docs makes the seams **conflict-free** at merge time. `bootstrap.sh` installs this.

> **CRITICAL:** parallel agents do **not** bump the contracts package version and do **not** regenerate OpenAPI/types. The **integrator** does that **once** at merge (§5). That single rule removes the last shared-file collision — the version bump is a coordination signal, not a free-for-all.

### The per-spawn ritual

For every sub-agent the orchestrator spawns:

1. **Resolve the work map** — pre-resolve the ticket's primary symbol (callers, blast radius) and inline `file:line` targets into the brief so the agent doesn't go exploring.
2. **Compose a self-contained brief** — inline the hard-rules block, the targeted work map, the ACs to turn green, and the gate commands. The agent should not need to re-read the KB to start; it gets the requirement text and its `finding_ref` pointer inline.
3. **Anti-pattern self-check** the draft brief; rewrite before spawning.
4. **Spawn with `isolation: "worktree"`**, `run_in_background: true` for anything over ~60s.

Every sub-agent runs in an **isolated git worktree**. The main tree is **read-only** for sub-agents. Branch names embed the session short-id so concurrent sessions can't collide. Each agent **commits its own branch and NEVER pushes.** Logical-boundary commits — one per ticket closed — each independently green.

### The four-state ticket lifecycle (the only shared state)

Tickets are the single shared mutable surface, and their **lifecycle is encoded by directory, not a status field**:

```
inbox/  →  in-progress/   →  done/        (or)  escalated/
           (+ ## Activity)     (+ ## Resolution:        (+ ## Escalation
                                  commit SHA + gate)        reason)
```

Ticket schema: `<id>-<kebab-slug>.todo.md` with YAML frontmatter — `id` (`w<wave>-<workstream>-<seq>`), `produced_by`, `produced_at`, `consumer_role` (`fixer-api` | `fixer-web` | `re-verifier` | `escalate`), `priority`, `area`, `blocked_by`, `finding_ref`. Rules:

- **Tickets are NEVER deleted.** A mistake becomes a *new* ticket.
- **Producers never edit their own queued tickets.** Discovery and fix are different waves and different agents.
- The **canonical requirement lives in the KB / findings ledger**, referenced by `finding_ref`. The ticket carries pointers, not the full requirement — so it stays small and the source of truth stays single.

### Two orchestrator modes — pick one before you spawn

The wave model runs in one of two modes. They differ only in **where Wave 1's tickets come from**:

1. **Greenfield build-from-spec** — the headline BRD→app path. You have already authored the build
   plan's **B-/F- tickets** (§3) and filed them into `.orchestrator/tasks/inbox/`. Those tickets ARE
   the inbox — **there is NO discovery wave.** Fixers drain the pre-authored queue starting at Wave 1;
   re-verify is the next wave. Nothing is "discovered": the plan already enumerated the work.
2. **Discovery / production-readiness** — audit an existing codebase where the work is unknown. A
   **discovery wave** finds it: Wave 1 producers file `*.todo.md` tickets (they do NOT fix), Wave 2
   fixers drain, Wave 3 re-verifies.

`/kit-orchestrate` branches on this: *if a build plan with B-/F- tickets already populates the inbox,
skip discovery and drain it (greenfield); otherwise run a discovery wave first (audit).*

### The waves

Sequential waves, parallel within a wave. The table is the **discovery-mode** numbering; in
**greenfield mode** there is no discovery row — Wave 1 is the build/drain wave and Wave 2 is re-verify
(this is the numbering the build-plan template's run-plan uses):

| Wave | Who | Does |
|---|---|---|
| **0** | Orchestrator only | Baselines + plan. Capture a baseline keyed by HEAD SHA + a `BASELINE-NOTES` of pre-existing failures. |
| **1** | Discovery producers (audit) **·** OR fixers draining the pre-authored B-/F- queue (greenfield) | Audit: file tickets, **do NOT fix.** Greenfield: drain `inbox/`, no discovery. |
| **2** | Fix/close consumers (audit) **·** OR re-verify (greenfield) | Audit: drain `inbox/` by `consumer_role` + `area`, in isolated worktrees. |
| **3** | Re-verify (audit) | Re-run gates per branch. **Do NOT integrate.** |
| **Phase 3** | Consolidator | Reconcile, report, release the session (prune own worktrees/branches). |

Run `/kit-orchestrate <mission>` to drive this.

**Done when:** every ticket is in `done/` or `escalated/` with its block filled, and every branch is independently green against the baseline.

---

## 5. Integrate — a separate, gated run

Integration is **not** a wave of the build run. It is its own invocation (`/kit-integrate`), because merging N branches has its own order, its own reviewer, and its own atomic-rewrite phase that don't map onto the build wave model.

The gates are **executable and run by the orchestrator** — never trusted from an agent's self-declared "done":

- **Universal gate:** typecheck + lint clean, unit tests green, browser/e2e green (mocked early, real composed stack late), contracts build clean.
- **Baseline-aware:** compared against the Wave-0 baseline so a *pre-existing* red is distinguishable from a *regression*.
- **Every commit independently green.**

Sequence:

1. **Pre-merge PR review** — an Opus `pr-reviewer` pass runs first and **blocks on any critical/high finding** (files new tickets for them).
2. **Merge in documented order**, then **re-emit as atomic conventional commits** via cherry-pick by file-set, so the final history reads as clean per-concern commits, not a merge swamp.
3. **The integrator — and only the integrator — bumps the contracts package version and regenerates OpenAPI/types** (the signal deferred from §4).
4. **Tag a checkpoint BEFORE any protected-core / schema / migration change.** Protected core = state machine, authority/RBAC, audit invariants, temporal/SLA math, scoring.
5. **The run explicitly does NOT push and does NOT open a PR.** Output is a clean local branch for you to review.

**Done when:** the integration branch is green end-to-end, the contract version is bumped once, the history is atomic, and a checkpoint tag precedes every protected-core touch.

---

## 6. Live QA — heavy, parallel, then adversarially verified

Unit-green is necessary, not sufficient. The cross-surface and persistence bugs only show up in a real browser against a composed stack (see `LESSONS.md` L17). The QA pillar is `toolkit/qa/` (`README.md`, `parallel-browser-qa.md`, `remote-qa-launcher.sh`, `tester-brief.md.tmpl`, `mcp.persona.json.tmpl`). Drive it with `/kit-qa`.

### The farm

An Opus orchestrator plus N Sonnet headless browser-tester sessions:

```bash
claude -p "$(cat brief.$P.md)" --model sonnet \
  --mcp-config mcp.$P.json --strict-mcp-config \
  --allowedTools "mcp__playwright" > $P.log 2>&1
```

`--allowedTools "mcp__playwright"` is the **safety boundary**: testers can drive a browser but cannot touch code, DB, or CLI, and cannot write files. Because they can't write files, **each tester emits its complete findings as its FINAL message**, captured from `$P.log`. Canary **one** persona first; cap at **~4 concurrent**; run **two waves**.

### Phase 3 — mandatory adversarial verification (this is what makes the report trustworthy)

The Opus orchestrator does **not** trust Sonnet findings raw. It:

1. **Re-verifies every Critical / RBAC claim** in its own authenticated session — capturing the **POST status** and doing a **hard reload** to prove *persistence* versus an optimistic-UI illusion.
2. **Reconciles severities across personas** into a corroboration matrix.
3. **Then** writes the report.

### The remote-QA truth

In the original project, the "run this farm on a remote box over an SSH tunnel" plumbing was **never committed** — it lived as operator tribal knowledge. This kit fixes that: the **local recipe is canonical**, and `toolkit/qa/remote-qa-launcher.sh` is the reusable artifact the original lacked.

**Data-residency caveat:** a personal remote box is fine for **synthetic seed data only**. For regulated/PII data the heavy-QA box must sit **inside the approved hosting boundary** — never tunnel real data to a personal machine.

**Done when:** every persona wave has run, every Critical/RBAC claim is independently re-verified with POST-status + hard-reload evidence, and the report's severities are corroboration-backed.

---

## 7. Testing policy — verification, opt-in except the protected core

Automated testing is **opt-in**, not a reflex. The unit of "done" is a **verification**; the *kind*
of verification depends on what the AC touches.

- **Protected-core ACs → a passing automated test against a real database is MANDATORY.** Protected
  core is where a regression is *silent* (no type error, no crash) and consequential:
  - the **state machine** / status transitions,
  - **RBAC** read-scope + permission gates,
  - **audit-log** invariants (one row per audited field, append-only),
  - **snapshot / immutability** guarantees,
  - **allocation / capacity / temporal (date) / SLA** math,
  - **scoring** and **merge resolvers**.

  Test the pure function or the route against the real test DB — never a hand-rolled mock Prisma /
  fake harness. Test scaffolding must not be larger than the code under test.
- **Everything else → verify on the live app.** DTO mapping, route wiring, prop passing, UI
  layout/styling/copy, config/env, exploratory code: implement, run `typecheck` + `lint`, and confirm
  the behaviour by exercising the running app. No test step is required — a test-per-AC for every
  surface is unworkably expensive and proves little the type system and a live click do not.

That is why the AC ledger's column is **"Verification ref"**, not "Test ref": a protected-core row
holds a test path; a non-core row holds `live-app: <route>`. The merge gate still requires the
**existing** test suite to pass — opt-in governs writing *new* tests, not skipping the suite. The ORG
preset's `protected-core-checklist.md` enumerates exactly what protected core *is* for a statutory
domain; that is the same opt-in trigger named here.

---

## 8. Definition of done

A slice is done when **all** hold:

1. Every AC in the ledger is **verified** — a passing automated test for protected-core ACs (state
   machine, RBAC, audit, snapshot, temporal/SLA, scoring, merge resolvers), otherwise typecheck +
   lint + live-app verification. The AC is the unit of done.
2. Every implemented requirement carries **provenance** — a `file:line` citation back to the KB in code/commit. No internal spec refs leak into user-facing strings.
3. Every commit is **independently green** against the baseline; no regressions vs `BASELINE-NOTES`.
4. The **contract version** was bumped exactly once, by the integrator.
5. A **checkpoint tag** precedes every protected-core/schema/migration change.
6. The integration branch is green end-to-end; **not pushed, no PR** — left for operator review.
7. Heavy QA ran, and every **Critical/RBAC** finding was **adversarially re-verified** with persistence evidence.
8. Every ticket is in `done/` (with `## Resolution`) or `escalated/` (with `## Escalation reason`).

---

## 9. The operating loop — cheat sheet

```
0.  setup        bash toolkit/ingestion/setup.sh        # markitdown 0.1.6, py3.13 pipx
1.  ingest       /kit-ingest <corpus-dir>               # KB: mirror, IDs, > Source:, INDEX.md
2.  bootstrap    bash bootstrap.sh <target-repo>        # conventions, seams, .gitattributes union
3.  spec         brainstorm slice -> design-spec.md     # cite requirement IDs from the KB
                 + acceptance-criteria.md ledger        # verbatim ACs, IDs, surface tags, rounds
4.  plan         build-plan.md  +  MODULES.md           # B-/F- tickets: Files, schemas, endpoints, ACs, gates
5.  build        /kit-orchestrate <mission>             # waves; worktree-isolated; commit, NEVER push
                  - four seams, append one line each
                  - tickets move by DIRECTORY (inbox -> in-progress -> done|escalated)
                  - integrator alone bumps the contract version
6.  integrate    /kit-integrate                         # SEPARATE gated run; atomic commits; tag-before-touch; no push/PR
7.  qa           /kit-qa                                 # N Sonnet browser testers (mcp__playwright only)
                  - canary 1 persona, cap ~4, two waves
                  - Phase 3: Opus re-verifies every Critical/RBAC claim itself
8.  done         every AC verified (test on protected core, else live-app), provenance, report
```

Reusable engine: `skills/orchestrator-protocol/` (PROTOCOL.md is the contract; LESSONS.md is the numbered engine-level lore). Org specifics: `presets/org/` — fork it for your org. Keep the core generic.

# PROTOCOL.md — orchestrator-protocol

The contract. Every orchestrator run and every sub-agent brief produced by this skill MUST satisfy this document.

---

## 1. Wave model

| Wave | Role | Parallelism |
|---|---|---|
| **0 — Plan** | Orchestrator alone | Single-threaded. Reads context, runs baselines, drafts the plan doc, initialises `.orchestrator/`, optionally invokes `/goal` to decompose the mission. |
| **1 — Discovery** | Producers | Spawn all in parallel. Each producer FILES findings + `.todo.md` tickets; producers do NOT fix product bugs. |
| **2 — Fix / Close** | Consumers | Spawn all in parallel. Each consumer drains the inbox filtered by `consumer_role` and closes (or escalates) tickets. |
| **3 — Re-Verify** | Re-verifier | One agent (or per-domain pair). Re-runs full gates against the fixer branches; files any new red as `.todo.md` with `consumer_role: re-verifier` and `priority: high`. |
| **Phase 3 — Consolidate** | Orchestrator alone | Drains `escalated/` into the final report. Writes the operator-facing summary. NEVER auto-merges branches — surfaces integration order + known conflicts. |

Sequential across waves. **Parallel within a wave is the default — the framework's whole purpose**. Cross-session isolation (§11) and worktree-per-agent (§6) make parallelism safe, not absent. Re-verifier never spawns until every Wave 2 consumer has returned. The Wave-2 fixers and `qa-playwright.yaml` can run in parallel because they share the queue + logging sink (no direct coupling).

### 1.1 Per-spawn ritual (orchestrator runs before each Agent call)

For every sub-agent the orchestrator spawns, in order:

1. **GitNexus pre-resolution** (skip if `code_intelligence: none` in the target profile):
   - `gitnexus_query({query: "<task concept from the ticket>"})` — find candidate execution flows / symbols.
   - `gitnexus_context({name: <primary symbol>})` — full context (file:line, callers, callees, participating processes).
   - `gitnexus_impact({target: <primary symbol>, direction: "upstream"})` — blast-radius confirmation. If HIGH/CRITICAL and the ticket scope was LOW, the orchestrator SPLITS the ticket before spawning.
2. **Compose** — render `templates/subagent-prompt.md.tmpl`, filling `{{TARGETED_WORK_MAP_BLOCK}}` with the GitNexus output, `{{INLINED_FACTS_BLOCK}}` with the global baseline + per-profile `inline_keys:` content, and the other placeholders.
3. **Anti-pattern self-check** — scan the draft brief against `templates/anti-patterns.md`. Any fragment matching a ❌ row must be rewritten to the ✅ shape before spawning. Three rewrites still matching ❌ means the ticket is under-specified — split or defer.
4. **Brief size cap** — if the rendered brief exceeds 500 lines, the orchestrator splits the ticket or drops the inline budget to 300 lines for this spawn. Per-wave cap: 6 agents at full inline; more agents requires shrinking briefs or escalating to a pre-flight discovery wave (out of scope).
5. **Spawn** — `Agent({ subagent_type, prompt, isolation: "worktree", run_in_background: true })`.

Briefs that skip steps 1–3 are protocol violations. The orchestrator's own self-review at session close (Phase 3 consolidation) checks that every spawn in the run had a recorded pre-resolution step. See `templates/anti-patterns.md` for the bad-vs-good fragments and `CONTEXT-INDEX.md` "Inline-key registry" for the named-key → source mapping used in step 2.

---

## 2. Goal decomposition (Phase 0.5, optional)

If the mission is open-ended ("get this production-ready"), invoke `/goal` (or spawn a `goal-planner` sub-agent) to enumerate Wave 1 workstreams **before** writing the orchestrator prompt. The output of `/goal` becomes the workstream list in the prompt template. Skip this step when the mission already names its workstreams.

---

## 3. Shared queue

All tickets live under `.orchestrator/tasks/` in the project:

```
.orchestrator/
├── state.md                     # orchestrator-maintained ledger
└── tasks/
    ├── inbox/                   # open tickets
    ├── in-progress/             # picked up by a consumer
    ├── done/                    # closed (Resolution stamped)
    └── escalated/               # operator-only follow-up
```

`.orchestrator/` is gitignored. Tickets never enter the project's git history.

### Frontmatter (mandatory)

```yaml
---
id: w<wave>-<workstream>-<seq>          # e.g. w1-real-api-03
produced_by: <workstream-id>
produced_at: <ISO timestamp>
consumer_role: fixer-api | fixer-web | re-verifier | escalate | <custom>
priority: critical | high | medium | low
area: backend | web | a11y | perf | infra | docs | <custom>
blocked_by: <space-separated task ids or "none">
finding_ref: <path-to-finding.md#anchor or "n/a">
---
## Title
## Reproduction (bug) OR Steps (chore)
## Acceptance criteria
## Pointers (file:line, BRD/AC IDs, commit SHAs)
```

Filename: `<id>-<kebab-slug>.todo.md` — e.g. `w1-real-api-03-leave-approve-race.todo.md`.

### Pickup / close protocol (consumers)

1. `ls .orchestrator/tasks/inbox/` — read every frontmatter.
2. Filter by `consumer_role` matching your archetype and `area` matching your scope. Honour `blocked_by`.
3. On pickup: move the file from `inbox/` to `in-progress/`. Append `## Activity` with branch + ISO start.
4. On close: append `## Resolution` (what changed, commit SHA, gate result) and move to `done/`.
5. If you can't close, append `## Escalation reason` and move to `escalated/`. Do NOT delete.

### Producer rules

- A `.todo.md` is the dispatch ticket. The canonical finding lives under the project's findings tree (e.g. `tests/qa/findings/by-persona/<persona>.md`) and is referenced by `finding_ref`. Both must exist for product bugs.
- A producer NEVER edits its own queue once written. Mistakes go in a new ticket.

### Orchestrator rules

- After each wave, walk `in-progress/` and `done/` to update `.orchestrator/state.md` (producer/consumer ledger).
- `escalated/` only drains in Phase 3 (consolidation). The orchestrator hoists every escalated ticket into the final report as a blocker row.

---

## 4. Sub-agent contract

Every sub-agent brief is **self-contained**: the orchestrator pre-resolves file:line pointers via GitNexus and inlines all static facts (hard rules, project conventions, infra/auth/today). Sub-agents read the brief and act. They do NOT bootstrap by reading PROTOCOL.md, CLAUDE.md, or other static sources — those are inlined.

Every brief includes:

1. **Role** — producer / consumer / re-verifier / integrator / consolidator.
2. **Targeted work map** — pre-resolved file:line pointers, symbols (with callers/callees from `gitnexus_context`), exact test commands, and forbidden paths. This is the brief's load-bearing section.
3. **Inlined facts** — hard rules (verbatim from §6), today/infra/auth, wave+queue mode, and any per-profile inlined snippets from the profile's `inline_keys:` (e.g., code conventions, palette rules).
4. **Before You Begin** — explicit instruction to STOP and report `Status: NEEDS_CONTEXT` if the brief is unclear, rather than guess.
5. **When You're in Over Your Head** — explicit escalation language; sub-agent reports `Status: BLOCKED` with reason rather than thrashing.
6. **Code intelligence stanza** — when the profile sets `code_intelligence: gitnexus`, the orchestrator injects `templates/gitnexus-stanza.md` verbatim. Empty otherwise.
7. **Inbox scan instructions** (consumers only) — exact `ls` + filter rule.
8. **What to do** — numbered, executable steps. Include gate commands verbatim.
9. **Triage rubric** — test bug / product bug / spec gap / infra flake; what to fix vs file.
10. **Self-review checklist** — four categories (Completeness / Quality / Discipline / Testing), run before reporting back. Per-profile rows come from the profile's `self_review_categories:` field.
11. **Escape hatches** — slim list of TIER-1/TIER-2 pointers for the case where the brief was wrong; never the default read path.
12. **Done when** — a single observable acceptance.
13. **Report-back** — see §5; MUST start with `Status: <one of four>`.

### 4.1 The read-budget contract (post-targeted-brief revision)

The orchestrator-protocol does NOT use eager `must_read:` lists, and TIER-0 reads are NO LONGER mandatory at spawn. The previous shape — every sub-agent re-reads `PROTOCOL.md` + `CONTEXT-INDEX.md` + `CLAUDE.md` headings — burned ~200 lines per spawn for static content that's identical across all agents in a wave. See LESSONS L22.

Replacement contract:

- **Inline-by-default.** The orchestrator's brief composer inlines all static content (hard rules, code conventions, today/infra/auth/wave) into the "Inlined facts" section of the brief. The sub-agent's "TIER-0 reads" become zero in the happy path.
- **Per-profile inlines.** Each profile declares `inline_keys:` — named keys (e.g., `code-conventions`, `palette-rules`, `msw-rules`) that the orchestrator resolves to actual content via the registry in `CONTEXT-INDEX.md`.
- **TIER-1 demoted to escape hatch.** The profile's `index_keys:` is rendered in the brief as "Escape hatches — read ONLY if a TIER-2 trigger fires". Not part of the default boot.
- **TIER-2 trigger-only.** Unchanged from §4.1 pre-revision. The agent reads ONLY when its current sub-task matches a trigger row in `CONTEXT-INDEX.md`.
- **GitNexus pre-resolution by the orchestrator.** Before composing a brief, the orchestrator runs `gitnexus_query` → `gitnexus_context` → `gitnexus_impact` on the ticket's primary symbol(s) and inlines the file:line + callers into the Targeted work map. The sub-agent does NOT re-run these for navigation; it only uses GitNexus for pre-commit `gitnexus_detect_changes` and any new symbols it touches.

The agent's report-back includes `Index keys consumed: ...` — typically "TIER-0 inlined-only" in the happy path. Sustained over-reads (an agent fetching keys not in its profile, or reading `PROTOCOL.md` for "context") get filed as a tuning ticket against either the profile or the brief composer.

### 4.2 Spawning

- Use `Agent` with `subagent_type` matching the archetype's `subagent_type` field in `agent-profiles/`.
- ALWAYS pass `isolation: "worktree"`. Override requires a written reason in the brief.
- ALWAYS pass `run_in_background: true` for any agent expected to take > 60 s.
- Wait for the completion notification — never `tail` the transcript output file.
- BEFORE spawning: run the pre-spawn ritual described in §1.1. Briefs without GitNexus pre-resolution + an anti-patterns self-check are protocol violations.

---

## 5. Report-back contract (every sub-agent)

Every returning agent reports under a strict word limit (default 400 words). The FIRST LINE of the report is the status; the orchestrator's dispatch loop branches on it.

### 5.1 Status line (mandatory, first line)

One of:

| Status | Meaning | Orchestrator's response |
|---|---|---|
| `Status: DONE` | Acceptance criterion met cleanly. | Proceed to wave-2 re-verifier as usual. |
| `Status: DONE_WITH_CONCERNS` | Acceptance met but flagged doubts (e.g., "this file is now 600 LOC", "I had to touch an adjacent symbol"). | Read concerns FIRST. If correctness/scope concerns, address before re-verifier. If observational, note and proceed. |
| `Status: NEEDS_CONTEXT` | Brief was incomplete; agent could not proceed without more info. | Provide missing context and re-dispatch (same model, same brief + addendum). Do NOT swap models. |
| `Status: BLOCKED` | Agent cannot complete. Reason in the report. | Triage: context problem → re-dispatch with more context; reasoning problem → escalate model; too large → split ticket; plan wrong → escalate to operator. |

### 5.2 Body (after the Status line)

```
- Targeted-read accuracy: yes | mostly | no — N extra files opened
- Self-review: <four-category summary; "all yes" or specifics>
- Index keys consumed: <typically "TIER-0 inlined-only"; plus any TIER-2 triggers that fired>
- GitNexus usage: <count of gitnexus_* calls; which symbols you ran gitnexus_impact on>  (omit if code_intelligence: none)
- Tests added: <count + paths>
- Tests fixed: <count + paths>
- Tickets consumed: <count by status: done / escalated>
- Per closed ticket: id, commit SHA, gate result
- Per escalated ticket: id, reason
- New tickets filed: <count + ids>
- Findings filed: <count by severity>
- Worktree path + branch name + tip SHA
- Blockers (if Status is BLOCKED or DONE_WITH_CONCERNS)
```

Producers omit "tickets consumed". Consumers omit "tests added" unless they wrote regression specs.

### 5.3 Targeted-read accuracy — definitions

| Value | Definition |
|---|---|
| `yes` | All edits landed in files listed in the brief's Targeted work map; 0 unlisted files opened beyond glances at sibling files. |
| `mostly` | 1–2 unlisted files opened; primary edits still landed in listed files. |
| `no` | ≥3 unlisted files opened, OR primary edit landed in an unlisted file. |

Wave-level health metric: if the `yes + mostly` rate drops below 70% across a wave, the orchestrator's brief composer is targeting poorly — log to LESSONS.md and pause for operator review before next wave. Two consecutive missions below 60% triggers full design rollback (see spec §7).

---

## 6. Hard rules (copy into every brief verbatim)

### 6.1 Universal (every brief)

- NEVER push, force-push, `--no-verify`, `--no-gpg-sign`, amend, or auto-merge across branches.
- NEVER commit secrets. `.env.local` must stay gitignored.
- NEVER commit binary artefacts (PNGs, JPGs, videos, traces, snapshots). Use `.artifacts/` and `test-results/` (both gitignored).
- Conventional commits only: `feat(api): …`, `fix(web): …`, `test(api): …`, `chore(orch): …`, `docs: …`, `perf(web): …`, etc.
- Branch naming: `<track>/<phase>-<slug>` — e.g. `fe/prod-real-api`, `be/fix-vitest-drift`, `ops/integration-cleanup`.
- TypeScript strict where applicable; no `any`, no `as any`. Zod (or project equivalent) at every boundary.
- Per-agent tool-call budget: **150** (default). Save state + report blockers if hit.
- TIER-0 reads only at spawn; everything else is on-demand via `CONTEXT-INDEX.md`. Never re-read a TIER-0 source mid-run "just to be safe" — note the question in the report instead.

### 6.2 Code intelligence (when `code_intelligence: gitnexus` in your profile)

The full stanza is in `templates/gitnexus-stanza.md` and the orchestrator copies it into your brief. The headline rules:

- `gitnexus_impact` before ANY product-symbol edit. Report direct callers, processes, risk level in the commit body. HIGH/CRITICAL → stop and surface in your report unless the ticket explicitly accepts the risk.
- `gitnexus_query` instead of `grep -rn` for symbol or concept lookups.
- `gitnexus_detect_changes` before EACH commit (not once per session). Unexpected symbols → stop and investigate.
- `gitnexus_rename` for renames; never find-and-replace.
- Index stale → `npx gitnexus analyze` once, note in report.
- No `.gitnexus/` index → grep fallback, note "no gitnexus index" in report.

Role-specific hard rules live in each profile's `hard_rules:` and are appended below the universal block in the brief.

---

## 7. Phase 0 pre-flight (orchestrator, before any spawn)

1. Read every CLAUDE.md / AGENTS.md in the project tree.
2. Run the project's baseline gate suite. Record every result in `.orchestrator/state.md`.
3. **Pre-commit on main:**
   - Append `.orchestrator/` to `.gitignore` (idempotent).
   - Add `.gitattributes` with `merge=union` for known append-only files (`docs/open-questions.md`, `findings/*.md`, equivalent in the project).
   - Single commit: `chore(orch): prepare orchestrator infra`.
4. `scripts/orchctl-init.sh` handles 3a/3b idempotently — call it.
5. Write the plan doc to `docs/<mission>-plan-<DATE>.md`.

---

## 8. Memory-on-opinion (mandatory)

When the user, during a run, expresses any of:

- a preference ("I prefer X over Y"),
- a non-obvious project fact ("this laptop intentionally uses tenant Z"),
- a correction of a recommendation ("Elasticsearch is better here because I already have it"),

the orchestrator (or whichever sub-agent received the message) writes a project-memory file to `~/.claude/projects/<project-slug>/memory/`. Append a one-line pointer to `MEMORY.md`. Use the format from `~/.claude/CLAUDE.md` "auto memory" section.

---

## 9. Verdict over options

The orchestrator and every sub-agent answer "what should we use" questions with **one** recommendation + the trade table that led there. Never present a menu and ask the user to choose, unless the operator has explicitly delegated the choice.

---

## 10. Integration is a separate run

NEVER do a multi-branch integration as a Phase 3 step inside a discovery orchestrator. Use `/integrate` (a separate skill invocation) which uses `templates/integration-report.md.tmpl` and a single careful integrator + reviewers + atomic-rewriter sequence.

---

## 11. Cross-session git isolation (mandatory)

Multiple Claude sessions on the same machine WILL interfere if not isolated. Every orchestrator run obeys these rules:

### 11.1 Session lock

`scripts/orchctl-init.sh` claims `.orchestrator/session.lock` with the current orchestrator's session id, hostname, PID, and ISO timestamp. If a lock already exists and is < 1 hour old, init aborts with:

```
orchctl-init: another orchestrator session (<id>, started <ts>) is active.
Resolve before starting a new run:
  - if that session is stale: rm .orchestrator/session.lock && retry
  - if it is genuinely running: wait for it OR run in a separate worktree
    of this repo (`git worktree add <path> origin/main`).
```

### 11.2 Main working tree is read-only for sub-agents

NO sub-agent ever runs `git checkout` in the main working tree. Sub-agents only operate in the worktrees the harness creates via `isolation: worktree`. The orchestrator MAY run read-only `git` commands (`status`, `log`, `show`, `diff`) on the main tree but NEVER `checkout`, `stash pop`, `merge`, `rebase`, or `restore`.

### 11.3 Session-scoped branch names

Branch names produced by an orchestrator session embed the session id as a suffix:

```
<track>/<phase>-<slug>-s<session-short>      # e.g. fe/prod-real-api-sA7B9
```

This guarantees two concurrent sessions cannot collide on a branch name even if they pursue similar missions. The session-short is the first 5 chars of the orchestrator's UUIDv4, written to `.orchestrator/session.lock`.

### 11.4 Worktree directory namespacing

The harness already keys agent worktrees by internal agent id (e.g. `.claude/worktrees/agent-<hex>`). Do not override this. Never write to `.claude/worktrees/` directly.

### 11.5 Session release

On clean exit the orchestrator runs `scripts/orchctl-session-release.sh`, which:
1. Removes `.orchestrator/session.lock` and writes a final ledger entry to `state.md`.
2. Runs §11.6 artifact cleanup (worktrees + branches).

Phase 3 consolidation is what triggers this — if Phase 3 is skipped, the lock is left to expire (stale after 1 hour) and the artifacts remain on disk.

### 11.6 Session artifact cleanup (mandatory)

Every orchestrator session creates throwaway artifacts: worktrees under `.claude/worktrees/agent-<hex>`, harness-managed `worktree-agent-*` branch refs, and the mission's own `<track>/<phase>-<slug>-s<session-short>` branches. **Sessions are responsible for removing their own artifacts at clean exit** — leaving them is how a project accumulates 25+ locked worktrees and 30+ orphan branch refs over a few days (see L20).

**HARD RULE — never touch unmerged or dirty work.** Cleanup removes ONLY artifacts that pass BOTH gates: (a) fully merged into `$MISSION_REF` AND (b) clean (no uncommitted changes). Anything failing either gate is preserved verbatim and surfaced in the report. The script MUST use `git branch -d` (never `-D` — `-d` refuses to delete unmerged refs and that refusal is a feature, not an error to work around). `git worktree remove --force` is permitted ONLY to bypass the harness lock flag on a worktree that has *already* passed both gates above — it is NOT a way to bypass dirty-tree refusal. Unmerged commits can represent abandoned-but-still-valuable work, an aborted re-verify the operator wants to inspect, or a fixer that exited mid-edit — none of those are the cleanup script's call to discard. If you find yourself wanting to weaken either gate "just for this one case," stop and file a ticket for the operator instead.

The release script (§11.5) performs cleanup with these rules — conservative by default, never destroys work in progress:

1. **Worktrees:** for each `.claude/worktrees/agent-*`:
   - Skip if dirty (`git status --short` non-empty) — emit a "DIRTY-SKIP" line naming the path + branch so the operator can recover the work.
   - Skip if the checked-out branch is **not** merged into `$MISSION_REF` (defaults to `HEAD`).
   - Otherwise `git worktree remove --force <path>`.
2. **Free-standing branches:** for each branch matching `worktree-agent-*` (harness refs) OR `<track>/*-s<session-short>` (this session's named branches):
   - Skip if the branch is currently checked out by any remaining worktree.
   - `git branch -d <name>` — never `-D`. If git refuses (not fully merged), leave it and emit a "UNMERGED-SKIP" line.
3. **External worktrees** (e.g. `/private/tmp/<mission>`, `<repo-parent>/<mission>`): the script does NOT auto-remove these. The orchestrator's final report lists them as "manual cleanup recommended" so the operator decides.
4. The script prints a one-line summary: `cleanup: removed N worktrees, deleted M branches, skipped X dirty + Y unmerged`. The final ledger entry in `state.md` includes this summary.

The mission's own integration / delivery branches survive cleanup by design — they carry the merged result and the operator may want to push / tag them. They are listed in the final report's "branch table" and removed by a later integrator pass or by the operator.

---

## 12. Commit discipline (mandatory for every sub-agent)

The intent is **a clean, reviewable git history** — not a stream of WIP commits squashed at the end.

### 12.1 Logical-boundary commits, not time-boundary commits

Every sub-agent commits at logical boundaries:

- Producer: one commit per filed ticket batch (or per spec file added).
- Fixer: one commit per ticket closed.
- Integrator: one commit per branch merged + one commit per pre-flight infra change.
- Atomic-rewriter: one commit per bucket (see `templates/integration-report.md.tmpl`).

NEVER:

- A single "end of session" mega-commit.
- "WIP" / "checkpoint" / "fixup" commits left in the branch tip.
- Squashing logically distinct concerns into one commit just to keep counts low.

### 12.2 Every commit is independently green

At each commit SHA, the project's `typecheck` and `lint` gates must exit 0. Verify with a temporary worktree checkout if uncertain. The atomic-rewriter MUST enforce this and back up if a commit goes red.

### 12.3 Commit message contract

Conventional commits with explicit scope and the ticket reference in the body:

```
<type>(<scope>): <short imperative summary, ≤ 70 chars>

<one-paragraph body explaining WHY this change exists>

Closes: <ticket-id> [, <ticket-id>...]
Refs: <finding-ref> if applicable
Risk: HIGH | MEDIUM | LOW (from gitnexus_impact)
```

Types: `feat | fix | test | chore | docs | perf | refactor | build | ci`.

### 12.4 Sub-agent commit frequency

- Producer: commit on every spec-file batch (3–5 specs max per commit).
- Fixer: commit per ticket. NEVER pile two tickets into one commit.
- Re-verifier: read-only; should not commit.
- Integrator: commit-per-merge or commit-per-bucket; never both in one commit.

### 12.5 No amending, no force-pushing

Re-stated from §6, but reinforced here: NEVER amend, NEVER force-push, NEVER rebase a branch that exists on `origin/`. The atomic-rewriter is the ONLY agent permitted to rewrite history, and only on a fresh `*-atomic` branch off `origin/main`.

---

## 13. PR review gate (the senior-reviewer pass)

Real SDLC has a senior code reviewer before merge. The framework simulates this via the `pr-reviewer` archetype (`agent-profiles/pr-reviewer.yaml`), which runs on Opus by default (deeper analysis budget) and is invoked at two distinct points:

### 13.1 Mid-fix gate (optional, project-driven)

Spawn `pr-reviewer` as part of Wave 2 if the fixer commits non-trivial changes. The reviewer reads the entire fixer branch diff vs `origin/main`, files quality findings as `.todo.md` with `consumer_role: fixer-{api,web}` for the next pass.

### 13.2 Pre-merge gate (mandatory before integration)

Before `/integrate` rewrites history into atomic commits, `pr-reviewer` produces a full review report at `PR-REVIEW-<MISSION>-<DATE>.md` covering:

- API contract diff (breaking changes, version bumps required, OpenAPI compliance).
- Frontend visual + a11y diff.
- Test coverage delta (lines, branches, files).
- Security regressions (secret scan, RBAC probe diff).
- Performance regressions (compared against the project's BRD §X budgets).
- Risk summary (HIGH/MEDIUM/LOW per change cluster).
- Recommended merge order if multiple feature branches converge.

Findings file as `.todo.md` with `consumer_role: fixer-{api,web}` (priority graded). The integrator MUST drain any `priority: critical` PR-review findings before producing the atomic branch.

### 13.3 Invocation

- `/review-pr <branch-or-mission>` — slash entry point.
- Or as a Wave 2.5 spawn from the orchestrator template.

---

## 14. SDLC simulation mapping

The orchestrator-protocol maps to the real-life SDLC roles:

| SDLC role | orchestrator-protocol archetype |
|---|---|
| Product / TPM (decomposition) | `/goal` invocation in Phase 0.5 |
| Tech leads (discovery, design, ADR) | `discoverer.yaml` (analyst / tester / security-auditor / perf-analyzer subtypes) |
| Backend developers | `fixer-api.yaml` |
| Frontend developers | `fixer-web.yaml` |
| QA (re-verification) | `re-verifier.yaml` |
| Performance engineer | `perf-smoke.yaml` |
| Release engineer (branch integration) | `integrator.yaml` |
| Senior code reviewer (PR gate) | `pr-reviewer.yaml` (Opus model) |
| Engineering manager (consolidation + report) | `consolidator.yaml` |

This mapping is explicit so the operator can adjust depth per stage: drop the PR review for a hot-fix run, double-up on security reviewers for a sensitive sprint, etc.

---

## 15. Logging contract (the bug-channel for the whole framework)

Bugs surfaced by manual testing AND automated QA are NOT filed by the operator. They are emitted as structured log events to the project's logging sink (Elasticsearch by default — see project memory `logging-stack-choice`), then read by a `log-reader-triage` agent that clusters and files `.todo.md` tickets against the standard queue.

### 15.1 Producer obligations (every fixer agent, every QA agent)

Every server/CLI code path written or modified by an orchestrator-spawned agent MUST emit structured log events on error. Required fields:

| Field | Source |
|---|---|
| `timestamp` | ISO 8601 |
| `level` | error / warn / info / debug |
| `source` | api / web-server / web-client / qa-playwright / e2e |
| `request_id` | correlated across the request lifecycle |
| `route` | HTTP path or component name |
| `persona` / `user_id` | authenticated identity (or `anonymous`) |
| `status` | HTTP status, or `n/a` for non-HTTP |
| `duration_ms` | hot-path latency |
| `error.message` | short |
| `error.stack` | full |
| `error.code` | typed enum if available |
| `session_id` | the orchestrator session short-id (`s<5char>`) so log readers can scope a fix run to its originating session |

Secrets are stripped pre-transport (`Authorization`, `*_SECRET`, `password`, `x-*-token`). Healthcheck noise and `2xx < 50 ms` are filtered unless `LOG_NOISY=1`.

Codifies the project memory entry `logging-stack-choice` (Elasticsearch + Kibana for dev-laptop runs unless the project specifies otherwise).

### 15.2 QA-Playwright agent (`qa-playwright.yaml`)

A QA agent runs the project's Playwright suites against the live app (real-stack, not MSW) and emits every test failure as a single structured log event with `source: qa-playwright` plus the standard fields. The same agent also emits `source: e2e` for assertion failures inside test bodies. No `.todo.md` filing from this agent — it produces log events; the log-reader triages.

### 15.3 Log-reader triage agent (`log-reader-triage.yaml`)

After a manual testing session and/or a QA-Playwright run, a log-reader agent queries the sink for the session window, clusters the events by error-message + top-stack-frame, and files `.todo.md` tickets:

- `consumer_role: fixer-api` for backend clusters.
- `consumer_role: fixer-web` for web-client clusters.
- `priority` graded from event count + level + presence of stack.
- `finding_ref` pointing at the saved-search URL in Kibana (or equivalent).

The triage agent then exits. Wave-2 fixer agents drain the queue exactly as in any other orchestrator run.

### 15.4 Session-scoped query

Every log event carries the orchestrator's `session_id`. Triage queries the sink filtered to a session window (start/end bookmarks emitted by `orchctl-init.sh` and `orchctl-session-release.sh`). This is the operator's manual-test scoping: bookmark-start → exercise app + run QA → bookmark-end → spawn `/orchestrate` with the triage agent.

### 15.5 When logging is not yet in place

If the project has no logging sink yet, the orchestrator's first run is to BUILD one. Use the Logging-Revamp orchestrator pattern: stand up Elasticsearch + Kibana on Docker, swap `pino-elasticsearch` into the apps' pino transports, write the redactor, expose `pnpm logs:up` / `session:start` / `session:end` scripts. Subsequent runs reuse the same sink.

### 15.6 Fatal-class client events flush synchronously (codifies L19)

Any client-side logger that emits to a network sink MUST classify each event as `fatal` or `batchable` and flush `fatal` events **synchronously at enqueue time** via `navigator.sendBeacon` (or `fetch({ keepalive: true })` as fallback). A batch timer (e.g. 2 s / 50 events) is fine for `batchable` events (info, warn, web-vitals, axe) but NOT for the page-is-on-fire path.

- The three canonical fatal classes are React `ErrorBoundary.componentDidCatch`, `window.onerror`, and `unhandledrejection`. Projects MAY add more; never remove these.
- The logging verifier suite MUST include a "fatal event arrives within 1 second after a real boundary catch against a hot dev server" check. A synthetic marker that traverses the route handler is NOT sufficient — the organic boundary/onerror/unhandledrejection path must round-trip end-to-end.

### 15.7 Mock/real-API contract-conformance gate (codifies L18)

If the project exposes BOTH a mock backend (MSW or equivalent) and a real backend, it MUST land a static merge-gate test (Vitest / ESLint / `tsc` plugin — implementation detail) asserting every list-endpoint reader uses the project's contract-normalising helper. Net-new code that types an envelope shape directly (`useQuery<{ <plural>: T[] }>`) fails the gate.

- Known existing drift is parked in a `PARKED_OFFENDERS` allowlist; each entry names a ticket id. Removing an allowlist entry without fixing the file goes red (both directions of drift stay visible).
- The discoverer wave runs this gate during its initial scan; each allowlisted file becomes a `medium`-priority rollup ticket for the fixer wave.

---

## 16. Definition of done (the orchestrator's exit criteria)

Default checklist (the orchestrator template instantiates these against the actual mission):

1. Project-defined gates green (typecheck / lint / unit / integration / e2e / a11y).
2. Backend test pass rate ≥ project floor (default 99%, overridable in the mission brief).
3. All `.orchestrator/tasks/inbox/` drained (done OR escalated).
4. No new reds introduced (re-verifier confirms).
5. Operator-facing report at repo root with verdict-per-workstream, RED tracker, branch table, and recommended integration order.
6. Tag `checkpoint/<mission>-<DATE>` ONLY if every workstream is green AND no critical reds remain.
7. Session artifact cleanup (§11.6) has run: stale agent worktrees removed, free-standing harness/session branches pruned (only the fully-merged ones), DIRTY-SKIP and UNMERGED-SKIP lines listed in the final report so nothing was silently dropped.

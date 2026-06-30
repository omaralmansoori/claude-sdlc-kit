---
name: orchestrator-protocol
description: Reproducible parallel-orchestrator framework. Use when the user asks to "spawn an orchestrator", "run waves", "orchestrate <task>", "/orchestrate", "/integrate", or any multi-agent parallel build with a shared ticket queue. Loads PROTOCOL.md, LESSONS.md, and the matching template + agent profiles, then drafts a project-specific orchestrator prompt (does NOT spawn until the user approves). Do NOT use for single-task work or simple research delegation (use Agent directly).
---

# orchestrator-protocol

A project-agnostic skill that turns an open-ended mission ("get this codebase production-ready", "audit the API", "integrate eight feature branches") into a disciplined multi-wave orchestrator with isolated sub-agents, a shared ticket queue, and a fixed report shape.

## When you (Claude) invoke this skill

### Step 1 — TIER-0 eager reads (every invocation)

Three sources, in parallel. Total ~200 lines:

- `CONTEXT-INDEX.md` — the read index. Tells you what else exists and when to fetch it.
- `PROTOCOL.md` §1 (wave model), §4 (sub-agent contract), §5 (report-back), §6 (hard rules). Skip the rest unless an index trigger fires.
- The matching template under `templates/` (one file, picked from the table below).

The agent profiles for the archetypes you plan to spawn — fetch as TIER-1 once you've decided your wave roster, not eagerly.

### Step 1b — TIER-2 on-demand reads (fetched by trigger, never eagerly)

The triggers live in `CONTEXT-INDEX.md`. Examples of when each fires:

- `t2-lessons-L11..L20` — only the specific `L<N>` whose trigger matches the work you're about to do.
- `t2-user-guide` — operator is choosing the tier (light / harness) or onboarding a legacy repo.
- `t2-tooling-assessment` — operator asks about external tool choice (GitNexus / Ruflo / swarm).
- `t2-harness-mode` (`harness-mode/README.md` + protocols) — ONLY for harness-tier missions (BRD-driven multi-week builds with a live dashboard).
- `t2-prior-readiness-report`, `t2-orch-state`, `t2-project-memory`, `t2-adr-context` — fetch only when the named context is needed for the current sub-task.

If no trigger fires, do not read. The previous "lazy reads when the mission calls for them" rule was too permissive — agents fetched everything just in case. The index's per-row trigger is the new contract.

### Step 2 — Bootstrap

Run `scripts/orchctl-init.sh` in the target project. Idempotent: claims session lock (auto-clears > 1 h stale), creates `.orchestrator/`, gitignores it, commits `.gitattributes` with `merge=union` for append-only docs.

### Step 3 — Compose the orchestrator prompt

Use `templates/orchestrator-prompt.md.tmpl`. Fill in: mission, workstreams (invoke `/goal` / the `goal-planner` sub-agent if open-ended), branches, gates, tool budget.

**Per-spawn ritual (post-L22, mandatory for every sub-agent spawn during the run):**

1. **GitNexus pre-resolution** — `gitnexus_query` → `_context` → `_impact` on the ticket's primary symbol. Skip only if the target profile has `code_intelligence: none`. HIGH/CRITICAL blast radius on a ticket scoped LOW → split the ticket before spawning.
2. **Compose** — render `templates/subagent-prompt.md.tmpl`, filling `{{TARGETED_WORK_MAP_BLOCK}}` with the pre-resolution output and `{{INLINED_FACTS_BLOCK}}` with the global baseline + per-profile `inline_keys:` content (registry in `CONTEXT-INDEX.md`).
3. **Anti-pattern self-check** — scan the draft brief against `templates/anti-patterns.md`. Any fragment matching a ❌ row → rewrite to ✅ before spawning. Three rewrites still ❌ → the ticket is under-specified, split or defer.
4. **Brief size cap** — 500 lines per brief, 6 agents per wave at full inline. Beyond that, shrink briefs to 300 lines or escalate to a pre-flight discovery wave.
5. **Spawn** with `isolation: "worktree"`, `run_in_background: true` for any task > 60 s.

See PROTOCOL.md §1.1 for the canonical version and L22 for the rationale.

### Step 4 — Approval gate (mission-size scaled)

- **Small mission (≤ 4 agents in Wave 1, light-tier):** spawn directly. No approval pause. The operator can interrupt or kill the run; pre-approving each one is friction the original "parallel and expedite" intent never wanted.
- **Medium mission (5–8 agents, or any cross-cutting refactor):** show a one-paragraph plan summary (workstreams + branch names + estimated wall-clock) and spawn unless the operator objects within the same turn.
- **Large mission (> 8 agents, harness-tier, or any /integrate):** present the full composed prompt for explicit approval. Do NOT spawn until the operator says "go".

### Step 5 — Execute

Follow PROTOCOL.md. Drain the queue per `queue/README.md` between waves.

## Templates

| User intent | Template |
|---|---|
| "spawn an orchestrator", "/orchestrate <mission>", general parallel build | `templates/orchestrator-prompt.md.tmpl` |
| "/integrate", merge prod branches, atomic-rewrite history | `templates/integration-report.md.tmpl` + the integration variant of the orchestrator template |
| Drafting a single sub-agent brief | `templates/subagent-prompt.md.tmpl` |
| Filing a ticket | `templates/ticket.todo.md.tmpl` |
| Final consolidation | `templates/production-readiness-report.md.tmpl` |

## Hard rules (lifted from PROTOCOL.md — repeat in every spawned brief)

- Every sub-agent uses `isolation: worktree`. Override requires a written reason in the spawn brief.
- Per-agent tool-call budget: **150** (default). Save state and report blockers if hit.
- NEVER push, force-push, `--no-verify`, `--no-gpg-sign`, amend, or auto-merge across branches.
- NEVER commit secrets or binary artefacts. `.artifacts/` and `test-results/` are gitignored.
- Background-agent etiquette: launch with `run_in_background: true`, wait for the completion notification, never `tail` the JSONL transcript file (it overflows context).
- Memory-on-opinion: when the operator expresses a preference, a non-obvious project fact, or corrects a recommendation, write it to `~/.claude/projects/<project>/memory/` immediately. Same rules as the global "auto memory" section in `~/.claude/CLAUDE.md`.
- Verdict over options: when the user asks "what should we use", give a recommendation with rationale, not a menu.
- Read budget: TIER-0 eager, TIER-1 by profile `index_keys`, TIER-2 on trigger only. Sub-agent report-back includes `Index keys consumed:` line. See `CONTEXT-INDEX.md`.
- Code intelligence: every profile with `code_intelligence: gitnexus` gets `templates/gitnexus-stanza.md` injected into its brief verbatim. Symbol lookups go through GitNexus (`gitnexus_query` / `_impact` / `_context` / `_detect_changes` / `_rename`), never grep + Read. `gitnexus_impact` is mandatory before any product-symbol edit; `gitnexus_detect_changes` is mandatory before every commit.

## Out of scope

- Single-file or single-task edits — just do them with `Edit`.
- Simple research delegation — `Agent` directly.
- Project-specific stack rules — those belong in the project's own `CLAUDE.md`, not here.

## Layout

```
~/.claude/skills/orchestrator-protocol/
├── SKILL.md                              # this file
├── PROTOCOL.md                           # the contract
├── CONTEXT-INDEX.md                      # TIER-0 / 1 / 2 read index (replaces eager must-reads)
├── LESSONS.md                            # append-only learnings (seed from this chat)
├── README.md                             # human-readable overview
├── templates/
│   ├── subagent-prompt.md.tmpl           # injects {{INDEX_KEYS_BLOCK}} + {{CODE_INTELLIGENCE_STANZA}}
│   ├── gitnexus-stanza.md                # verbatim block for code_intelligence: gitnexus profiles
│   └── *.md.tmpl
├── agent-profiles/                       # *.yaml — must_read_always + index_keys + code_intelligence
├── queue/README.md                       # .orchestrator/tasks/ layout + ticket frontmatter
└── scripts/                              # orchctl-{init,status,drain}.sh

~/.claude/commands/
├── orchestrate.md                        # /orchestrate <mission>
└── integrate.md                          # /integrate
```

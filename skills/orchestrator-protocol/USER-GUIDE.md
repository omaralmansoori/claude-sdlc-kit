# USER-GUIDE.md — orchestrator-protocol

> **Command names under the plugin:** this guide says `/orchestrate`, `/integrate`, `/review-pr`. Under the `claude-sdlc-kit` plugin those map to **`/kit-orchestrate`**, **`/kit-integrate`** (which folds in the `/review-pr` pass), and **`/kit-qa`**. The bare commands are not registered by the plugin.
>
> **Bring-your-own (harness tier):** the heavy/harness-tier flow below references tooling that is **not shipped in this kit** — the live `Harness Snitch` dashboard, the `pnpm session:start` / `session:end` bookmark scripts, and a logging sink (PROTOCOL §15). Treat all three as **external/optional**: stand up your own equivalents or skip the harness tier and stay light. The kit's `/kit-*` commands cover the light tier end-to-end without them.

How to use this framework in real-life situations. Pick the section that matches your scenario.

The framework has **two tiers**:

| Tier | When to use | State lives in |
|---|---|---|
| **Light tier** (default) | One-shot orchestrator runs ("get this PR production-ready", "audit X") | `.orchestrator/tasks/{inbox,in-progress,done,escalated}/` |
| **Harness tier** (heavy) | Long-running project build with a BRD, multi-week scope, live dashboard, multi-session continuity | `harness/` directory at the project root (see `harness-mode/`) |

You can promote a project from light → harness when scope justifies it. You rarely demote.

---

## Scenario 1 — Building a new app (greenfield) from a BRD

This is the heavy path. The BRD drives task decomposition; tasks feed the orchestrator; the dashboard tracks progress.

### 1a. Day 0 — Source intake

1. Drop the BRD into `docs/` (`.docx`, `.pdf`, whatever).
2. `pandoc docs/<brd>.docx -o docs/BRD.md --wrap=none` — get a greppable markdown.
3. Write `docs/BRD-INDEX.md` mapping every numbered section to a one-line summary.
4. Decompose the BRD into **modules** under `modules/` — one folder per feature area, each with its own README.
5. Write `docs/existing-app-profile.md` ("what's already here, what to NOT touch"). For greenfield this is one line. For brownfield it's a survey.
6. Write 4–6 **ADRs** for stack + architectural decisions you've already made (`docs/adr/0001-*.md` etc.).

### 1b. Day 0.5 — Generate the task manifest

```
/orchestrate decompose the BRD into a task manifest
```

Triggers the `task-architect` agent (`agent-profiles/task-architect.yaml`). It reads BRD-INDEX + modules + existing-app-profile and produces `harness/tasks/MANIFEST.json` (schema in `harness-mode/templates/MANIFEST.schema.json`). Each entry has rich frontmatter: `id`, `title`, `module`, `sd_items`, `domain`, `priority`, `complexity`, `depends_on`, `suggested_agent`, `ui_weight`, `user_surfaces`, `existing_app_touchpoints`, etc.

Operator reviews the MANIFEST. Iterates with `task-architect` until happy.

### 1c. Day 1 — First wave

```
/orchestrate work the first wave from the manifest
```

The orchestrator:
- Reads `MANIFEST.json` filtered to `stage=backlog`.
- Honours `depends_on` — only tasks with all dependencies in `stage=done` are eligible.
- Picks N tasks (default 4–6) for the first wave based on priority + complexity.
- Spawns one sub-agent per task, **in parallel**, each in an isolated worktree, each archetype = `suggested_agent`.
- Each task moves from `backlog/TASK-XXXX.md` → `in-progress/TASK-XXXX.md` on pickup → `review/TASK-XXXX.md` after code-review gate → `polish/TASK-XXXX.md` after UI polish gate → `qa/TASK-XXXX.md` after QA gate → `done/TASK-XXXX.md` when fully closed.

The five stages between in-progress and done are the harness-tier quality gates. The light-tier collapses them into one (`done/`). Project picks the policy in `harness/protocols/lifecycle.md`.

### 1d. Run the live dashboard alongside (optional, bring-your-own)

`Harness Snitch` is an **external, not-shipped** read-only dashboard (any filesystem-polling
status viewer works). Point your own at this project's `harness/` directory:

```
HARNESS_ROOT=/path/to/your/project/harness npm --prefix /path/to/harness-snitch run dev
# → http://127.0.0.1:3200
```

Snitch polls the filesystem every 8 s and shows:
- Overall % complete
- Counts per stage
- Currently in-flight (with age) — **this is where parallelism becomes visible**: the dashboard shows N tasks in `in-progress/` simultaneously
- Last achievement (most recent `checkpoint/*` tag + verdict)
- Up next (top 8 unblocked tasks, ranked by priority then id)
- Recently done
- Blocked

The Harness Snitch was built for serialized work but reads what's on disk, so multiple parallel in-flights show up correctly. The framework supplies the parallelism; the snitch supplies the visualization.

### 1e. Subsequent days

Each day's session is one `/orchestrate` invocation that picks the next eligible wave off the MANIFEST. Sessions are bounded by checkpoints. After each wave the orchestrator tags `checkpoint/wave-<N>-<DATE>` and updates `harness/state/CHECKPOINTS.md`.

---

## Scenario 2 — Editing an existing app that already uses this framework

The easy case. The project has `.orchestrator/`, possibly a `harness/`, a populated MANIFEST.

```
/orchestrate <one-paragraph description of what you want to change>
```

Or if you want to scope to a specific module:
```
/orchestrate work backlog tasks in module 07-resource-capacity
```

Or if you want a single ad-hoc fix without touching the MANIFEST:
```
/orchestrate fix the bug where <X>
```

The third form bypasses the MANIFEST and operates in light-tier mode: files findings as `.todo.md` directly in `.orchestrator/tasks/inbox/`, drains them through Wave 2 fixers, closes in `done/`. No new tasks land in the MANIFEST unless the operator promotes them.

---

## Scenario 3 — Onboarding a preexisting app that did NOT follow this framework

This is the most fragile path. The framework's worktree + parallel-agent pattern assumes a sane git baseline. The onboarder gets you there.

```
/orchestrate onboard this codebase into the framework
```

Triggers the `onboarder` agent (`agent-profiles/onboarder.yaml`). It:

1. **Inventories the repo.** Identifies the stack, build tooling, test runner, package manager. Writes `docs/existing-app-profile.md` end-to-end — every directory's purpose, every running process, every external dep.
2. **Captures invariants.** Reads any existing `CLAUDE.md`, `ORCHESTRATOR.md`, `AGENTS.md`, README, contributing guide. Lists rules the framework must respect.
3. **Runs `orchctl-init.sh`** to prepare `.orchestrator/` and `.gitattributes`.
4. **Writes a project-specific `CLAUDE.md`** at the root (or proposes diffs to the existing one) that anchors the framework: stack pins, code conventions, no-touch list, gate commands.
5. **Optionally promotes to harness-tier.** If the project has a BRD or roadmap document, the onboarder offers to run `task-architect` to decompose it into a `harness/tasks/MANIFEST.json`. Otherwise it stops at light-tier.
6. **Files a single ADR** documenting the framework adoption and the date.

After the onboarder completes, run a small mission to validate:
```
/orchestrate verify the framework adoption — run baselines, file any reds as .todo.md
```

If that returns clean, the project is ready for full use.

### Hazards specific to onboarding

- **Long-lived branches.** If the project has unmerged feature branches older than ~2 weeks, the onboarder lists them as a finding rather than merging. Operator decides.
- **No tests.** The framework's "executable gates" rule has nothing to bite into. The onboarder files a P0 ticket to add a smoke test before any other fix work.
- **Monorepo with mixed tooling.** The onboarder maps each app/package to its own `CLAUDE.md` and writes a workspace-level `AGENTS.md`. Light-tier per package, possibly harness-tier at the root.

---

## Scenario 4 — Testing an app that follows this framework

Two modes — they run in parallel and feed the SAME logging sink (see PROTOCOL.md §15).

### 4a. Operator manual testing

1. `pnpm session:start "manual-<label>"` — writes a bookmark to the log sink and `.orchestrator/last-session.json`.
2. Exercise the app. Don't write bugs down. Every `console.error`, every unhandled rejection, every failed fetch, every axe violation lands in the sink with the orchestrator's `session_id` tag.
3. `pnpm session:end "manual-<label>"` — closes the bookmark.

### 4b. Automated QA in parallel

Spawn the `qa-playwright` agent **during** the bookmark window. It runs the project's Playwright suites against the real stack and emits every failure as a structured log event with `source: qa-playwright`. Same sink, same `session_id`, same field schema.

### 4c. Triage

```
/orchestrate read the last manual+QA session and fix everything
```

Triggers `log-reader-triage` (Wave 1) → `fixer-api` / `fixer-web` / `qa-playwright` (Wave 2, parallel) → `re-verifier` (Wave 3) → `pr-reviewer` (gate before `/integrate`).

Operator never opens a ticket by hand. The logs are the bug channel.

---

## Scenario 5 — Releasing changes

```
/integrate                              # merge feature branches + atomic-commit rewrite
/review-pr <branch-or-mission>          # senior reviewer pass on Opus
```

After `/review-pr` returns green (no critical findings), the operator opens the PR on `origin/`. The framework never pushes or opens PRs itself.

---

## The BRD → tasks pipeline (the heavy tier in detail)

```
docs/<source>.docx
    ↓ pandoc
docs/BRD.md            <- greppable
    ↓ manual
docs/BRD-INDEX.md      <- section index
    ↓ manual + ADRs
modules/<name>/README.md   <- per-feature decomposition (lifted from Project Dashboard)
    ↓ task-architect agent
harness/tasks/MANIFEST.json
    ↓ orchestrator picks waves
harness/tasks/{backlog,in-progress,review,polish,qa,done,blocked}/TASK-XXXX.md
    ↓ closed tasks tag checkpoints
harness/state/CHECKPOINTS.md
    ↓ Harness Snitch polls disk
http://127.0.0.1:3200  <- live dashboard
```

The MANIFEST is generated once (or regenerated when modules change). Individual task files are the working-copy mirrors — they move between stage folders as work progresses. The `task-architect` profile generates both the manifest and the stage-folder seeds.

### Source-doc traceability

Tasks carry `sd_items: [SD-001, SD-042]` references back to the source document. `docs/source-doc-coverage.md` mirrors this as a SD-### → task matrix so nothing in the BRD silently drops on the floor. The orchestrator refuses to declare "done" while any SD-### has zero covering tasks.

### Defaults registry

When the BRD is silent on something ("does the user see costs in summary mode?"), the answer goes in `docs/defaults.md` as `DEF-NNN: <one-line decision>`. Tasks that depend on the decision list `defaults_applied: [DEF-042]`. A future reviewer can audit every decision the framework made on the operator's behalf.

---

## Reporting

### Per-session

- `.orchestrator/state.md` — producer/consumer ledger, regenerated each wave.
- `<MISSION>-READINESS.md` at the repo root — final consolidated report from Phase 3.

### Per-day (harness-tier)

- `harness/state/SESSION_LOG.md` — append-only event log (one line per agent spawn, one line per gate result).
- `harness/state/DASHBOARD.md` — regenerated by `harness/scripts/status.sh` after each wave; same data as Harness Snitch but in markdown.
- `harness/state/CHECKPOINTS.md` — every `checkpoint/*` tag with verdict and date.
- `harness/state/OPEN_QUESTIONS.md` — any halts the orchestrator filed.
- `harness/state/DECISIONS_LOG.md` — every `DEF-*` defaults decision.

### Live (any tier)

- `Harness Snitch` (external/not-shipped — bring your own filesystem-polling viewer) — read-only filesystem polling, ~zero CPU when backgrounded. Point it at any project's `harness/` directory via `HARNESS_ROOT=...`.

---

## Parallelism — best of both worlds

Project Dashboard's harness was serialized (one task in-progress at a time). This framework keeps the harness's MANIFEST + stage folders + dashboard + reporting, but **runs N tasks concurrently** in each wave:

- Multiple `TASK-XXXX.md` files sit in `in-progress/` simultaneously, one per spawned sub-agent.
- Each agent works in an isolated worktree (PROTOCOL.md §6 + §11).
- The Harness Snitch's "Currently in flight" pane already supports listing multiple tasks (it iterates `in-progress/` — it wasn't designed for parallelism but it doesn't fight it).
- A wave is "done" when every spawned task reached `done/` (or `escalated/`). The orchestrator tags `checkpoint/wave-<N>-<DATE>` then.

### Configurable concurrency

`harness/MANIFEST.json` `wave_plan` array can name the parallelism cap per wave:

```json
"wave_plan": [
  { "wave": 1, "priority": "P0", "max_parallel": 4 },
  { "wave": 2, "priority": "P1", "max_parallel": 6 }
]
```

The orchestrator honours `max_parallel` when picking the next wave's tasks. If unset, default is 6.

---

## Quick reference

| Scenario | Entry point | Tier |
|---|---|---|
| Greenfield from BRD | `/orchestrate decompose the BRD` → then `/orchestrate work first wave` | Harness |
| Day-to-day edits | `/orchestrate <change>` | Light or Harness |
| Onboard legacy | `/orchestrate onboard this codebase into the framework` | Light → optionally Harness |
| Manual + automated testing | `pnpm session:start` → exercise → `pnpm session:end` → `/orchestrate read the last session and fix` | Light (uses logging sink) |
| Merge feature branches | `/integrate` | Either |
| Senior PR review | `/review-pr <branch>` | Either |
| Live progress | Harness Snitch on `:3200` | Harness (also works on light if `.orchestrator/tasks/` exists) |

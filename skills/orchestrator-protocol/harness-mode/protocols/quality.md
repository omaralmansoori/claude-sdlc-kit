# quality.md — three review gates

Every harness-tier task passes through up to three quality gates between `in-progress` and `done`. Each gate is a sub-agent run, not a human review.

## Gate 1 — Code review (`review/`)

**Agent:** `agent-profiles/reviewer.yaml` (Sonnet, scoped to the task's domain).

**Checks:**

- Conventional commit message references the task id (`Closes: TASK-NNNN`).
- Risk grade present in commit body (HIGH / MEDIUM / LOW from `gitnexus_impact`).
- No commented-out code, no `console.log`, no `any` types, no TODO without ticket.
- Touched files match `existing_app_touchpoints` in the task frontmatter (no scope creep).
- Acceptance Criteria boxes all ticked.

**Output:** moves the task to `review/`. Files `.todo.md` if it finds issues; the task stays in `in-progress` until those clear.

**Skip rule:** none. Every task passes Code Review.

## Gate 2 — Polish (`polish/`)

**Agent:** project-specific (typically a `ui-polish-engineer` agent under `.claude/agents/`).

**Checks:**

- ORG palette / project palette only (no stray hex tokens).
- Lucide icons only / project icon library only.
- No emojis (unless project allows).
- Responsive: desktop + tablet + mobile snapshots match design.
- a11y: zero `serious`/`critical` axe violations on the user_surfaces of this task.
- HeroUI/component-library tokens used (no inline arbitrary classes).

**Output:** moves the task to `polish/`.

**Skip rule:** if `ui_weight: none` in the task frontmatter, skip Polish entirely — task goes `review/` → `qa/` directly.

## Gate 3 — QA (`qa/`)

**Agent:** `agent-profiles/qa-playwright.yaml` (runs the project's e2e specs against the live stack) + `agent-profiles/re-verifier.yaml` (re-runs unit + integration tests).

**Checks:**

- All Playwright specs that cover the task's `user_surfaces` pass.
- No new console errors on those surfaces.
- No new perf regressions (compared to the prior `checkpoint/*` tag's baseline).
- Smoke tests under `harness/qa/specs/smoke/existing/` still pass (the SACRED set — these can NEVER be loosened).
- Any new specs the task added (under `harness/qa/specs/feature/TASK-NNNN/`) pass.

**Output:** moves the task to `qa/`.

**Skip rule:** none. Every task passes QA before `done/`.

## Failure handling

Any gate failure files a `.todo.md` against `.orchestrator/tasks/inbox/` with:

- `consumer_role: fixer-<domain>`
- `priority`: critical if the gate was QA and a smoke test broke; high otherwise.
- `finding_ref` pointing at the gate's report file under `harness/qa/reports/` or `harness/state/`.

The originating task moves BACK to `in-progress/` (not to `blocked/`) — the fixer ticket and the task share the same originator, so they get closed together.

## Parallelism within a stage

Multiple tasks can sit in `review/`, `polish/`, or `qa/` simultaneously. Gate agents pick up tasks in priority order (P0 first) and operate in parallel across tasks (one gate-agent worktree per task).

The constraint: ONE task per agent worktree. Two reviewers don't share a worktree; each spawns its own.

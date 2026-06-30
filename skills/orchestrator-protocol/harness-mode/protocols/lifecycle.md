# lifecycle.md — harness-tier task state machine

Tasks move through seven stages. Multiple tasks can occupy any non-terminal stage simultaneously (parallel work).

## State machine

```
backlog ──pick──> in-progress ──code-review──> review ──polish──> polish ──qa──> qa ──done──> done
   │                  │                          │           (skip if ui_weight=none)         │
   │                  └──any-blocker──> blocked <──any-stage─┘                                │
   │                                       │                                                  │
   └───────────unblocked──────────────────┘                                                  │
                                                                                              │
   any-stage ──cancelled──> archived/                                          (re-opened tasks reset to backlog and bump suffix .N)
```

| From | To | Transition gate |
|---|---|---|
| `backlog` | `in-progress` | Orchestrator picks the task into a wave + sub-agent claims the worktree + `Activity` block stamped. |
| `in-progress` | `review` | All Acceptance Criteria boxes ticked + commit SHA recorded + project gates green at that SHA. |
| `review` | `polish` (if `ui_weight ≠ none`) | `code-reviewer` agent (`agent-profiles/reviewer.yaml`) approves. |
| `review` | `qa` (if `ui_weight == none`) | Same, but skips polish. |
| `polish` | `qa` | `ui-polish-engineer`-equivalent agent approves visual + a11y. |
| `qa` | `done` | `qa-playwright.yaml` agent's run is clean for this task's `user_surfaces`. |
| any | `blocked` | Agent files `## Blocked reason`. Task waits for unblock. |
| `blocked` | `backlog` | Unblocker resolves; orchestrator re-files into the next wave. |

## Definition of Done

A task is `done/` only when every box ticks:

1. Acceptance Criteria all green.
2. Project gates at the task's commit SHA: typecheck OK, lint OK, relevant unit/integration tests OK, relevant Playwright specs OK, a11y zero serious/critical.
3. `## Resolution` block stamped on the task file (commit SHA, gate matrix, optional checkpoint tag).
4. If `checkpoint_candidate: true` → orchestrator tags `checkpoint/TASK-NNNN-<DATE>` after the move.

## Blocked recovery

`blocked/` tasks list the unblocker in `## Blocked reason`. The orchestrator scans `blocked/` at every wave start; any task whose blocker(s) are now `done/` is moved back to `backlog/` with a `[reopened-<ISO>]` suffix in `## Activity`.

## Halt conditions

The orchestrator halts (writes `harness/state/OPEN_QUESTIONS.md` and stops spawning) when:

- 3 consecutive tasks in the same module fail the same gate.
- `blocked/` exceeds 30% of `task_count` in MANIFEST.json (the project is gridlocked).
- A `task-architect` re-run materially changes the MANIFEST mid-wave (orchestrator waits for operator review).
- Any halt-condition documented in `docs/defaults.md` fires.

## Cancellation

Tasks are NEVER deleted. To cancel: move to `done/` with a `## Resolution` block of `cancelled — <reason>` and `gate: n/a`. The MANIFEST entry's `stage` flips to `done`. Source-doc coverage updates: the `SD-###` items that depended on the cancelled task move to `deferred` or `superseded` in `docs/source-doc-coverage.md`.

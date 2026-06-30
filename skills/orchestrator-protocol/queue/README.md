# Queue layout — `.orchestrator/tasks/`

This document describes the on-disk queue that every orchestrator and sub-agent shares. Read it before writing or consuming a ticket.

## Layout

```
.orchestrator/
├── state.md                     # orchestrator-maintained ledger (Baselines, Producer, Consumer, Run summary)
└── tasks/
    ├── inbox/                   # open tickets — waiting for a consumer
    ├── in-progress/             # picked up by a consumer, not yet closed
    ├── done/                    # closed (Resolution block stamped)
    └── escalated/               # operator-only follow-up (Escalation reason stamped)
```

`.orchestrator/` is gitignored on `main`. Tickets never enter the project's git history. Cross-worktree visibility is fine because worktrees share the index but each working tree resolves `.orchestrator/` from disk independently — once a ticket is moved, every worktree sees the move on its next `ls`.

## Ticket frontmatter

```yaml
---
id: w<wave>-<workstream>-<seq>          # e.g. w1-real-api-03, w2-crud-persist-001
produced_by: <workstream-id>            # the sub-agent id that filed it
produced_at: <ISO timestamp>            # date -Iseconds
consumer_role: <role>                   # fixer-api | fixer-web | re-verifier | escalate | <custom>
priority: <level>                       # critical | high | medium | low
area: <area>                            # backend | web | a11y | perf | infra | docs | <custom>
blocked_by: <ids or "none">             # space-separated ticket ids
finding_ref: <path#anchor or "n/a">     # canonical finding location
---
## Title
## Reproduction (bug) OR Steps (chore)
## Acceptance criteria
## Pointers
```

Filename: `<id>-<kebab-slug>.todo.md` — e.g. `w1-real-api-03-leave-approve-race.todo.md`.

### Required body sections

| Section | Producer writes | Consumer writes |
|---|---|---|
| `## Title` | yes | — |
| `## Reproduction` / `## Steps` | yes | — |
| `## Acceptance criteria` | yes | — |
| `## Pointers` | yes | — |
| `## Activity` | — | on pickup (branch + ISO start) |
| `## Resolution` | — | on close (what changed, commit SHA, gate result) |
| `## Escalation reason` | — | on escalate (why beyond "small + clearly in scope") |

## Standard `consumer_role` values

| Role | Picked up by | Notes |
|---|---|---|
| `fixer-api` | `agent-profiles/fixer-api.yaml` | Backend product fixes. |
| `fixer-web` | `agent-profiles/fixer-web.yaml` | Frontend product fixes. |
| `re-verifier` | `agent-profiles/re-verifier.yaml` | Re-runs gates; files new reds. |
| `escalate` | nobody (operator drains in Phase 3) | Out of agent scope: provisioning, large refactors, deferred features. |

Custom roles are allowed (e.g. `fixer-mobile`) when the project has tracks beyond the standard two. Document any custom role in the project's own `CLAUDE.md`.

## Standard `area` values

`backend`, `web`, `a11y`, `perf`, `infra`, `docs`, `security`, `mobile`. Custom areas are allowed; same documentation rule.

## Standard `priority` values

| Priority | Definition |
|---|---|
| `critical` | Ship blocker; data loss / auth bypass / corruption; CI red on `main`. |
| `high` | Single-feature breakage; perf > 2× over budget; significant flakiness. |
| `medium` | UX friction, schema strictness gap, single edge case. |
| `low` | Copy, polish, deferrable to next sprint. |

## Producer rules

1. A canonical FINDING under the project's findings tree (e.g. `tests/qa/findings/by-persona/<persona>.md`) is the source of truth for product bugs. The `.todo.md` is the dispatch ticket pointing at it via `finding_ref`. Both must exist for product bugs; test-only chores can omit the finding.
2. A producer NEVER edits its own queue once written. Mistakes go in a new ticket.
3. The producer NEVER fixes product bugs (unless its profile explicitly allows it — see `discoverer.yaml`'s "fix test-only drift" exception).

## Consumer rules

1. First action: `ls .orchestrator/tasks/inbox/` and read every frontmatter.
2. Filter by `consumer_role` matching your archetype AND `area` matching your scope.
3. Honour `blocked_by` — never pick up a task whose blockers are still in `inbox/` or `in-progress/`.
4. On pickup: move the file from `inbox/` to `in-progress/`. Append `## Activity` with your branch + ISO start.
5. On close: append `## Resolution` (what changed, commit SHA, gate result). Move to `done/`.
6. On escalate: append `## Escalation reason` (one paragraph). Move to `escalated/`. NEVER delete.

## Orchestrator rules

1. After each wave, walk `in-progress/` and `done/` to update `.orchestrator/state.md`.
2. `escalated/` only drains in Phase 3. Each escalated ticket becomes a row in the operator-facing report's RED tracker.
3. NEVER mutate a ticket already in `done/` or `escalated/` — they're append-only after the consumer's stamp.

## Helper scripts

- `bash ~/.claude/skills/orchestrator-protocol/scripts/orchctl-init.sh` — creates the queue, gitignores it, commits `.gitattributes`.
- `bash ~/.claude/skills/orchestrator-protocol/scripts/orchctl-status.sh` — prints counts per bucket and the inbox table.
- `bash ~/.claude/skills/orchestrator-protocol/scripts/orchctl-drain.sh` — refuses if any `in-progress/` ticket lacks `## Activity`, any `done/` ticket lacks `## Resolution`, or any `escalated/` ticket lacks `## Escalation reason`. Otherwise emits a summary suitable for paste into the operator-facing report.

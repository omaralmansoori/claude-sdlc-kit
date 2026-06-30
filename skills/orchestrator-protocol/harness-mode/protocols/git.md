# git.md — checkpoint + rollback contract for harness-tier projects

## Checkpoint cadence

Tag `checkpoint/<scope>-<DATE>` at every:

- Wave completion (after all spawned tasks reach `done/` or `escalated/`).
- Individual task `done/` if `checkpoint_candidate: true` in MANIFEST.
- Successful gate transition for any P0 task.
- After `/integrate` produces an atomic branch (`checkpoint/integration-<MISSION>-<DATE>`).

Tags are local-only. The framework never pushes tags to `origin/`.

## Tag namespaces

| Prefix | Set by | Meaning |
|---|---|---|
| `checkpoint/wave-<N>-<DATE>` | orchestrator | end of a wave |
| `checkpoint/TASK-NNNN-<DATE>` | release-manager / orchestrator | individual task with `checkpoint_candidate: true` closed |
| `checkpoint/integration-<MISSION>-<DATE>` | integrator | post-merge integration branch |
| `checkpoint/<MISSION>-<DATE>` | release-manager | full release (post PR review + green gates) |

## Rollback

A rollback is `git reset --hard <tag>` plus moving every task whose `## Resolution` SHA is in the rolled-back range back to `in-progress/` (or `backlog/` if the work was substantial and warrants restarting).

The orchestrator never rolls back on its own. Rollbacks require operator approval.

When the operator initiates a rollback:

1. Run `harness/scripts/rollback.sh <tag>` (project provides this; the framework's expectation is `git reset --hard` + `harness/state/CHECKPOINTS.md` annotation).
2. Re-scan `harness/tasks/done/` for task files whose `Resolution.commit` is past the new HEAD. Move them back to the appropriate stage.
3. Append an entry to `harness/state/DECISIONS_LOG.md` with the rollback reason.

## Branch naming (harness extension of PROTOCOL.md §11.3)

Same as light-tier with the session-short suffix, BUT individual task branches also embed the task id:

```
<track>/<phase>-TASK-NNNN-s<5char>      # e.g. be/fix-TASK-0127-sA7B9
```

This guarantees:

- Two concurrent sessions on the same task cannot collide (session-short differs).
- A reviewer reading `git log` sees task ids in branch names.

## Force-push, rebase, amend — forbidden

Same as PROTOCOL.md §6. The atomic-rewriter is the ONLY agent that rewrites history, and only on a fresh `*-atomic` branch off `origin/main`.

## Tag retention

The framework never deletes tags. Stale `checkpoint/*` tags accumulate; operator prunes manually if desired with `git tag -d`. The framework's `harness/state/CHECKPOINTS.md` is the human-readable record — never delete entries from it; mark them `rolled-back` or `superseded` instead.

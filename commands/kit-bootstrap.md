---
description: Scaffold a target repo for an orchestrated multi-agent build (.orchestrator queue + conventions)
argument-hint: [--preset org]
---

Scaffold the current repository so it is ready for an orchestrated, parallel multi-agent build.

Run `bash ${CLAUDE_PLUGIN_ROOT}/bootstrap.sh $ARGUMENTS` from the repo root. It will:

- create the `.orchestrator/` ticket queue (`tasks/{inbox,in-progress,done,escalated}`, `missions/`,
  `state.md`) — the only shared state between parallel agents;
- create `docs/{adr,open-questions.md,orchestrator-log.md}`;
- write a `.gitattributes` with `merge=union` for append-only docs so parallel worktrees never hard-conflict;
- append `.orchestrator/` and `.artifacts/` to `.gitignore`;
- drop the convention templates (`CLAUDE.md`, `AGENTS.md`, the contracts-package conventions, `MODULES.md`)
  for you to fill the `{{PLACEHOLDERS}}`;
- with `--preset org`, also copy the ORG overlay (brand, Entra auth ADR, Arabic/RTL, statutory
  protected-core checklist).

After it runs, fill in the placeholders (project name, stack, DB), then write your stack ADR before any
feature code, and proceed to `/kit-orchestrate`.

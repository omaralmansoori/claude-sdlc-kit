---
description: Run a parallel, worktree-isolated multi-agent build for a mission using the orchestrator protocol
argument-hint: <mission statement>
---

Act as the **orchestrator** for this mission: `$ARGUMENTS`

Load and follow the bundled `orchestrator-protocol` skill
(`${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-protocol/`). In short:

1. **Phase 0 (you, single-threaded):** read the governing knowledge base + the development contract
   (acceptance criteria, MODULES.md, the design spec / build plan), capture an executable baseline keyed
   by HEAD SHA into `.orchestrator/state.md`, and write the wave/branch run-plan.
2. **Pick the mode.** If a build plan with **B-/F- tickets** already populates
   `.orchestrator/tasks/inbox/` → **greenfield build-from-spec:** there is NO discovery wave; the
   pre-authored tickets ARE the inbox, so go straight to draining them (the fixers below become Wave 1,
   re-verify becomes Wave 2). Otherwise → **discovery/audit mode:** run the discovery wave first.
3. **Discovery wave (audit mode only):** spawn producers in parallel; they file `*.todo.md` tickets into
   `.orchestrator/tasks/inbox/`, they do not fix product code.
4. **Fix/close wave:** spawn consumers in parallel; each drains the inbox by `consumer_role` + `area`,
   in its **own git worktree**, owning ONE module's globs and appending one line per shared seam, committing
   its own branch and **never pushing**.
5. **Re-verify wave:** re-run the gates per branch; file new reds as tickets.

Gates are **executable, run by you** — never trust an agent's self-declared "done". Tag a checkpoint before
any protected-core/schema/migration change. Do **not** integrate here — that is a separate run
(`/kit-integrate`). Leave a morning report of what landed, what didn't, and the first thing to do next.

# orchestrator-protocol

> **Under the `claude-sdlc-kit` plugin, the entry points are `/kit-orchestrate`, `/kit-integrate`, and `/kit-qa`** — not the bare `/orchestrate`, `/integrate`, `/review-pr` names this vendored doc uses. The plugin does not register those bare commands. The senior PR-review pass (`/review-pr` below) is **folded inside `/kit-integrate`**. See the kit README's "kit command ↔ skill entry point" table. The rest of this doc is the underlying engine contract and reads the same either way.

Reproducible parallel-orchestrator framework for Claude Code. Project-agnostic.

**Start here:** `USER-GUIDE.md` covers the 5 real-life scenarios (new app from BRD, day-to-day edits, onboarding legacy, testing, release).

## What this is

A skill that takes an open-ended mission — *"get this codebase production-ready"*, *"audit the API surface"*, *"integrate eight feature branches"* — and turns it into a disciplined multi-wave orchestrator with:

- isolated sub-agents (each in its own git worktree),
- a shared `.orchestrator/tasks/` queue with a frontmatter contract,
- a fixed report-back shape per agent,
- a mandatory pre-flight (`.gitignore` + `.gitattributes` commits),
- a final operator-facing report (verdict-per-workstream + RED tracker + integration order).

## SDLC simulation

The framework models real-life SDLC roles. Each archetype maps to a normal software role so the protocol is legible to anyone familiar with normal team process:

| SDLC role | Archetype | Slash entry |
|---|---|---|
| TPM / decomposition | `goal-planner` (Phase 0.5) | inside `/orchestrate` |
| Tech leads (discovery) | `discoverer.yaml` | inside `/orchestrate` Wave 1 |
| Backend devs | `fixer-api.yaml` | inside `/orchestrate` Wave 2 |
| Frontend devs | `fixer-web.yaml` | inside `/orchestrate` Wave 2 |
| QA (automated, Playwright) | `qa-playwright.yaml` | inside `/orchestrate` Wave 2 (parallel with fixers) |
| QA (re-verification) | `re-verifier.yaml` | inside `/orchestrate` Wave 3 |
| Triage engineer (logs → tickets) | `log-reader-triage.yaml` | first stage of a follow-up `/orchestrate` after a bookmarked session |
| Perf engineer | `perf-smoke.yaml` | inside `/orchestrate` Wave 2 |
| Release engineer | `integrator.yaml` | inside `/integrate` |
| Senior reviewer (Opus) | `pr-reviewer.yaml` | `/review-pr` |
| Engineering manager | `consolidator.yaml` | inside `/orchestrate` Phase 3 |

## Three entry points

- `/orchestrate <mission>` — discovery → fix → re-verify → consolidate. **(Plugin: `/kit-orchestrate`.)**
- `/integrate` — merge feature branches + atomic-commit rewrite + reviewer pass. **(Plugin: `/kit-integrate`.)**
- `/review-pr <branch-or-mission>` — senior code reviewer (Opus) on a branch or integration tip. **(Plugin: folded inside `/kit-integrate`; no standalone command.)**

In a standalone (non-plugin) install these slash commands live at `~/.claude/commands/{orchestrate,integrate,review-pr}.md` and all load this skill. **Under the `claude-sdlc-kit` plugin they are not installed — use the `/kit-*` commands instead** (see the banner at the top of this file).

## Files

| File | Purpose |
|---|---|
| `USER-GUIDE.md` | **Read this first.** 5-scenario operator guide. |
| `TOOLING-ASSESSMENT.md` | Which external tools the framework uses (GitNexus yes, Ruflo no). Adopt-or-skip criteria + matrix. |
| `SKILL.md` | Skill descriptor and trigger. |
| `PROTOCOL.md` | The contract. Wave model, queue, frontmatter, hard rules, cross-session isolation, commit discipline, PR review, logging, SDLC mapping. |
| `LESSONS.md` | Append-only learnings. Seeded from a real run; future runs add to it. |
| `templates/` | Markdown templates — orchestrator brief, sub-agent brief, ticket, reports. |
| `agent-profiles/` | YAML defaults per archetype (subagent_type, budget, isolation, branch naming, must-read context). |
| `queue/README.md` | Light-tier ticket queue layout + frontmatter contract. |
| `scripts/` | Idempotent helpers: `orchctl-init.sh`, `orchctl-status.sh`, `orchctl-drain.sh`, `orchctl-session-release.sh`. |
| `harness-mode/` | **Optional heavy tier** for long-running BRD-driven projects: MANIFEST.json schema, lifecycle/quality/git protocols, task template, release-notes template. Point Harness Snitch at this. |

## Out of scope

- Project-specific stack rules (ORG palette, Prisma version, etc.) — those belong in the project's own `CLAUDE.md`.
- Anything that requires the orchestrator to push, merge to main, or open a PR — explicit operator action only.
- Single-task or single-file work — use `Agent` or `Edit` directly.

## Adding a new agent archetype

1. Create `agent-profiles/<archetype>.yaml`.
2. Reference it from `templates/subagent-prompt.md.tmpl` (the `must_read` and hard-rules sections are inherited).
3. If it has a new `consumer_role`, document it in `queue/README.md` and `PROTOCOL.md` §3.

## Updating the protocol

`PROTOCOL.md` is the contract. Changes need a corresponding `LESSONS.md` entry explaining the originating incident. No silent edits.

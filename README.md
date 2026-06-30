# claude-sdlc-kit

**From BRD to tested app.** A Claude Code plugin + methodology for running one operator and a disciplined fleet of Claude agents as a real software team — turning a pile of requirement documents into shipped, tested code, autonomously.

Repo: `github.com/omaralmansoori/claude-sdlc-kit`.

---

## What this is

Most "AI builds your app" demos fall apart at scale for three reasons: the model thrashes its context window re-reading source docs, it hallucinates requirements no document actually states, and parallel agents step on each other's files. This kit removes all three failure modes with a repeatable pipeline:

1. **Ingest** the requirement corpus (any format) into a grep-able, provenance-tagged **knowledge base** — the single source of truth.
2. **Contract** the work: every requirement becomes a verbatim acceptance criterion with a stable ID, owned by exactly one vertical-slice module.
3. **Build** in parallel: worktree-isolated agents each own their globs, append to four conflict-free seams, commit their own branch, and never push.
4. **Integrate** under executable gates: a separate, gated run merges in documented order and re-emits atomic commits.
5. **QA** hard: a fleet of headless browser testers, then a mandatory adversarial verification pass the orchestrator runs in its own session.

The result is a **dev framework, not a one-off**: one operator, a knowledge base, and a development contract, scaled across as many agents as the work needs.

## Who it's for

Engineering leaders and senior operators who want to drive a non-trivial build (a real internal app, a gov/enterprise system, a migration) with Claude Code agents and need **process discipline** — audit trails, gated merges, reproducible QA — not a magic-prompt toy.

---

## What's in the box

The kit is organized as three **toolkit pillars**, a set of **bundled skills**, an org **preset**, and a leadership **deck**.

### Toolkit pillars (`toolkit/`)

| Pillar | Path | What it gives you |
|---|---|---|
| **Ingestion** | `toolkit/ingestion/` | `setup.sh` + `ingest.py` + `strip_data_uris.py` + `gen_index.py` and custom `extractors/` (`vsdx_to_md.py`, `xlsx_to_md.py`) — convert a multi-format corpus into the KB. Wraps **markitdown** and fills its gaps. |
| **Conventions** | `toolkit/conventions/` | The drop-in templates that make a target repo agent-ready: `CLAUDE.md.tmpl`, `AGENTS.md.tmpl`, `contracts-package-CLAUDE.md.tmpl`, `MODULES.md.tmpl`. |
| **Contract** | `toolkit/contract/` | The development-contract artifacts: `acceptance-criteria.md.tmpl`, `design-spec.md.tmpl`, `build-plan.md.tmpl`, `ticket.todo.md.tmpl`. |

Plus `bootstrap.sh` at the repo root and the QA pillar at `toolkit/qa/` (`README.md`, `parallel-browser-qa.md`, `remote-qa-launcher.sh`, `tester-brief.md.tmpl`, `mcp.persona.json.tmpl`).

### Bundled skills (`skills/`)

| Skill | Status | Purpose |
|---|---|---|
| `skills/corpus-ingestion/` | shipped | The agent-facing skill for stage 1 — drives the ingestion toolkit and the KB conventions. |
| `skills/orchestrator-protocol/` | vendored | The parallel-orchestrator engine: wave model, four-state ticket lifecycle, isolated worktrees, executable gates. **Under this plugin you drive it via the `/kit-*` commands** (see the mapping table below), not the bare `/orchestrate` · `/integrate` · `/review-pr` names its own docs use. |
| `skills/data-schema/` | shipped | The data-schema design skill: naming, types, constraints, relationships, ORM/migration safety (expand/contract), indexing, concurrency, append-only PII-free audit, and a constraint-backed model generated *into* the contract layer. SQL Server + TypeORM examples; principles stack-agnostic. |

### Org preset (`presets/org/`)

Everything organization-specific lives **only** here, never in the generic core: brand, Entra/SSO auth ADR template, i18n/RTL guidance, and a protected-core checklist. Fork this folder to make your own preset.

### Worked example, narrative + deck

- `examples/` — one tiny vertical slice (a Room Booking feature) carried through every stage: synthetic mini-corpus → generated KB → filled contract → sample tickets (`done/` + `escalated/`) → integration + QA reports. Start here to see what "done" looks like at each step.
- `PLAYBOOK.md` — the full narrated method, loop-ordered, with the exact rituals.
- `MANIFESTO.md` — why the knowledge base is the foundation of agent-built software.
- `LESSONS.md` — methodology-level hard-won rules (engine-level numbered lessons live in `skills/orchestrator-protocol/LESSONS.md`).
- `deck/claude-sdlc-kit-deck.md` — the leadership presentation.
- `TROUBLESHOOTING.md` · `CONTRIBUTING.md` — first-run recovery (by stage) and how to extend the kit.

---

## Install as a Claude Code plugin

This repo ships `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, so it is a self-contained plugin marketplace. Add it, then install the plugin:

```bash
# 1. add this repo as a plugin marketplace (local clone or git URL)
/plugin marketplace add /path/to/claude-sdlc-kit
#    or:  /plugin marketplace add omaralmansoori/claude-sdlc-kit

# 2. install the plugin
/plugin install claude-sdlc-kit
```

This registers the bundled skills and the `kit-*` commands (`/kit-ingest`, `/kit-bootstrap`, `/kit-orchestrate`, `/kit-integrate`, `/kit-qa`).

> **Local-clone vs git-shorthand:** the `/plugin marketplace add <owner>/<repo>` shorthand resolves once the repo is public; if it doesn't resolve for you yet, use the local-clone form (`/plugin marketplace add /path/to/claude-sdlc-kit`).

---

## Commands

The plugin ships exactly **five** commands. The spec and plan stages (Quickstart steps 3–4) are operator-driven and have **no command** — that gap, between `/kit-bootstrap` and `/kit-orchestrate`, is intentional (it is human design work).

| Command | Argument hint | What it does | Reach for it when |
|---|---|---|---|
| `/kit-ingest` | `<corpus-dir> [output-kb-dir]` | Converts a multi-format BRD/spec corpus into an agent-searchable KB (default output `docs/kb/`). | You have raw requirement docs and need the knowledge base. |
| `/kit-bootstrap` | `[--preset org]` | Scaffolds the current repo: `.orchestrator/` queue, conventions templates, four append-only seams, `.gitattributes merge=union`, the `docs/kb/` location. | Starting a fresh target repo for an orchestrated build. |
| `/kit-orchestrate` | `<mission statement>` | Runs the parallel, worktree-isolated multi-agent build (greenfield drains the build-plan tickets; audit mode discovers first). | You have a build plan (greenfield) or a codebase to get production-ready (audit). |
| `/kit-integrate` | `<branches or mission>` | The **separate** gated merge run: pre-merge Opus PR review → merge in order → atomic-commit rewrite → integrator bumps contracts version once. No push, no PR. | Wave 2 is green and you want a clean reviewed integration branch. |
| `/kit-qa` | `[--remote] <personas>` | Heavy parallel browser QA: Opus orchestrator + Sonnet tester fleet, then mandatory Phase-3 adversarial re-verification. | The app runs and you need a trustworthy QA report. |

### kit command ↔ underlying skill entry point

The vendored `orchestrator-protocol` docs refer to bare `/orchestrate`, `/integrate`, `/review-pr`. Under this plugin those are **not** registered — the `/kit-*` commands are the entry points. The mapping:

| Vendored doc says | Under this plugin, run | Notes |
|---|---|---|
| `/orchestrate <mission>` | `/kit-orchestrate <mission>` | Discovery → fix → re-verify → consolidate. |
| `/integrate` | `/kit-integrate` | Separate gated merge + atomic-commit rewrite. |
| `/review-pr <branch>` | *(no standalone command)* — folded **inside** `/kit-integrate` | The senior Opus `pr-reviewer` pass is step 1 of `/kit-integrate` (it blocks merge on any critical/high finding). Invoke it standalone via the `Agent` tool with the `pr-reviewer` profile if you want a review without integrating. |

---

## Quickstart (6 steps)

> Read `PLAYBOOK.md` for the narrated version of each step. See **[`examples/`](examples/)** for one tiny vertical slice flowing through every stage below (mini-corpus → KB → contract → tickets → integration + QA reports).

| # | Step | Do this |
|---|---|---|
| 1 | **Ingest the corpus** | `bash toolkit/ingestion/setup.sh` (installs markitdown 0.1.6 in a pinned Python 3.13 pipx venv), then `/kit-ingest <corpus-dir> docs/kb` → produces the KB: mirrored folders, native requirement IDs preserved, `> Source:` lines, `INDEX.md` + per-area `_manifest.md`. Verify with `gen_index.py docs/kb --check` before moving on. |
| 2 | **Bootstrap the target repo** | `bash bootstrap.sh <target-repo>` (or `/kit-bootstrap`) drops in the conventions templates, the contracts-package skeleton, the four append-only seams, and `.gitattributes` `merge=union`. |
| 3 | **Brainstorm → spec** | Take one vertical slice; cite its governing requirement IDs from the KB; produce a `design-spec.md` from the template. |
| 4 | **Plan** | Decompose the spec into a `build-plan.md`: B-/F- tickets with exact Files, schemas, an endpoint table, "ACs to turn green", and gate commands. Fill the `acceptance-criteria.md` ledger first — the AC is the unit of done. |
| 5 | **Orchestrate the build** | `/kit-orchestrate <mission>` runs the waves: discovery files tickets, fixers drain the queue in isolated worktrees, re-verify re-runs gates. Each agent commits its own branch and never pushes. |
| 6 | **Integrate + QA** | `/kit-integrate` runs the separate gated merge (atomic commits, tag-before-touch, no push/PR). Then `/kit-qa` runs the parallel browser-tester farm and the mandatory Phase-3 adversarial verification before the report. |

---

## Requirements

- macOS or Linux with `bash`, `git`, `python3` (3.13 for ingestion — 3.14 has wheel gaps), `node`/`pnpm`.
- `pipx` for the isolated markitdown install (the setup script handles it).
- Claude Code with plugin support.

Hit a snag on first run? See **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** — keyed by stage (ingestion, bootstrap/plugin, orchestrate, QA). Extending the kit? See **[`CONTRIBUTING.md`](CONTRIBUTING.md)**.

## License

MIT — see `LICENSE`.

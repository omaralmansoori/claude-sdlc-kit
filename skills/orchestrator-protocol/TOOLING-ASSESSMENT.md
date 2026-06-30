# TOOLING-ASSESSMENT.md

Honest assessment of optional tools the operator already runs in their project repos. Adopt-or-skip decisions for the framework. Criteria, in order:

1. **Speed** — does it make the agent's run materially faster?
2. **Token cost** — does it reduce the prompt + tool-output tokens vs the Claude-native alternative?
3. **Quality** — does it produce better results than Claude grep + Read?
4. **Maintenance cost** — does the operator pay for it in setup, updates, mysterious failures?

Anything that fails (1) AND (2) AND (3) net of (4) is skipped, no matter how popular it is.

---

## GitNexus — **ADOPT**

**What it is:** A code-intelligence indexer. Builds a symbol graph (functions, classes, methods) + call graph + execution-flow clusters. Exposes MCP tools: `gitnexus_impact` (blast radius), `gitnexus_context` (caller/callee/flow context), `gitnexus_query` (concept → execution-flow search), `gitnexus_rename` (call-graph-aware rename), `gitnexus_detect_changes` (post-edit verification).

**Speed:** A `gitnexus_impact({target: "renderSnapshot"})` call returns the call-graph blast radius in < 1 s. The Claude-native equivalent is `grep -rn renderSnapshot | head -20`, read each match, build the graph in head — easily 10× slower.

**Token cost:** Impact analysis output is structured JSON (caller list + risk level + affected processes). ~200–500 tokens. The grep-and-read alternative is 2–5k tokens per symbol, sometimes more.

**Quality:** GitNexus catches transitive callers and execution-flow membership that grep can't. The "warn HIGH/CRITICAL risk before editing" rule in PROTOCOL.md §6 was lifted directly from this tool.

**Maintenance cost:** One command — `npx gitnexus analyze` — per material structural change. The index is incremental on subsequent runs. Failure mode is graceful: the tools emit "index stale" warnings and the agent re-indexes.

**Decision:** **Adopt as the framework's preferred impact-analysis tool.** Agents call `gitnexus_impact` before any product-symbol edit. Fall back to grep + read when the index isn't present in the project (the agent detects absence and reports it in the brief's report-back). The framework's PROTOCOL.md §6 already mentions it; this assessment formalizes it.

**Onboarder behaviour:** `agent-profiles/onboarder.yaml` suggests running `npx gitnexus analyze` once at framework adoption if no `.gitnexus/` exists. Project's `CLAUDE.md` should include the GitNexus block (the one already present in the RP project's CLAUDE.md is a good template).

---

## Ruflo — **SKIP**

**What it is:** A meta-orchestration MCP server with 98 sub-agents, ~50 slash commands, persistent memory, learning daemon, hooks-driven routing. Lives at `~/.ruflo/` and `<project>/.ruflo/`.

**Speed:** Mixed. The hooks-driven routing intercepts every `UserPromptSubmit` and routes through Ruflo's classifier. Adds latency on every prompt. The swarm features (`swarm_init`, `agent_spawn`, `hive-mind_*`) duplicate what Claude Code's native `Agent` tool already does.

**Token cost:** **Net negative for the framework's use case.** Ruflo's 98 agent prompts are kitchen-sink and lift large context blocks per spawn. The `memory_search` / `memory_store` calls are useful but duplicated by the framework's `~/.claude/projects/<slug>/memory/` (which Claude already loads at session start). Running both is double-counted tokens.

**Quality:** The agent definitions are too generic. They lack the SDLC-role specificity the framework's `agent-profiles/` provides. The "learning daemon" is a black box — outputs aren't auditable, which violates PROTOCOL.md §9 ("verdict over options, with rationale").

**Maintenance cost:** High. `ruflo init` adds 98 agents + ~50 commands + 11 hook events to the project. Updates regenerate state. Disabling features once enabled is non-trivial (the hook router stays in place). The Ruflo daemon is opt-in but its absence breaks features silently.

**Decision:** **Skip as a baseline dependency.** The framework's archetypes + queue + slash commands + memory dir cover the same surface with less coupling. Projects that already have Ruflo installed can keep it — the framework doesn't conflict — but `/orchestrate`, `/integrate`, `/review-pr` do NOT depend on Ruflo's tools.

If a future operator finds a single Ruflo feature genuinely irreplaceable, add it to this doc as a targeted dependency (one feature, not all 98 agents). Until then, the framework is Ruflo-free.

### What the framework provides instead of Ruflo

| Ruflo feature | Framework equivalent |
|---|---|
| 98 generic agents | `agent-profiles/*.yaml` — 12 SDLC-mapped archetypes |
| `swarm_init` / parallel spawn | Native `Agent` tool with `isolation: worktree` |
| `memory_store` / `memory_search` | `~/.claude/projects/<slug>/memory/` (already loaded by Claude Code) |
| `hooks_route` (UserPromptSubmit auto-routing) | Slash commands + skill's `description` trigger |
| Learning daemon | `LESSONS.md` (append-only, human-auditable) |
| `claims_claim` (work claiming) | `.orchestrator/tasks/inbox/` → `in-progress/` move |

---

## Claude Code's native tools — **REQUIRED**

| Tool | Why required |
|---|---|
| `Agent` with `isolation: worktree` | Backbone of parallelism (PROTOCOL.md §6, §11). |
| `Edit` / `Write` / `Read` | Default file operations. |
| `Bash` | All shell + git operations. |
| `TodoWrite` | Per-session task tracking (orchestrator turn). |
| Slash commands (`~/.claude/commands/`) | `/orchestrate`, `/integrate`, `/review-pr` entry points. |
| Skills (`~/.claude/skills/`) | This skill itself. |
| Background agents (`run_in_background: true`) | Wave parallelism (PROTOCOL.md §6). |
| Notifications | How background agents return — never poll the transcript file. |
| Memory (`~/.claude/projects/<slug>/memory/`) | Project-specific facts that persist across sessions. |

These are non-negotiable. The framework breaks without them.

---

## MCP servers — case by case

| Server | Decision | Reason |
|---|---|---|
| GitNexus | adopt (preferred) | See above. |
| Playwright MCP | adopt (when needed) | The `qa-playwright.yaml` agent uses it for browser automation. Standard. |
| Atlassian / Jira / Confluence | adopt per project | The `jira-assistant` skill already exists. Use when the project tracks tickets there. |
| Figma | adopt per project | When design-to-code is part of the workflow. |
| Microsoft Learn / Scite | adopt per project | When research-grounded answers matter. |
| Notion / Gamma | adopt per project | For document workflows. |
| Ruflo | skip | See above. |
| claude-flow / claude_ai_Consensus / Lucid / Google Drive / Calendar | case-by-case | Adopt only when the project's mission directly needs them. Don't pull in by default. |

The principle: **the framework prefers Claude-native + GitNexus + Playwright.** Everything else is project-specific, declared in the project's own `CLAUDE.md`, never in the global skill.

---

## How to update this doc

When the operator evaluates a new tool, add a section using the same shape:

```
## <tool> — **ADOPT** | **SKIP** | **DEFER**

**What it is:** ...
**Speed:** ...
**Token cost:** ...
**Quality:** ...
**Maintenance cost:** ...

**Decision:** ...
```

Adopt → mention in PROTOCOL.md. Skip → leave the section as the record of the trade. Defer → revisit on the next major project. Decisions older than 12 months get re-evaluated when a tool's category changes (new versions, new competitors).

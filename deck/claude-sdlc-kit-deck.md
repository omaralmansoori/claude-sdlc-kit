# claude-sdlc-kit: From BRD to Tested App

- A reusable methodology for building a real application with a fleet of Claude Code agents
- One human operator runs the agents as a disciplined SDLC team, not a chatbot
- Ships as a Claude Code plugin + git repo: skills, tools, templates, and a worked example
- Outcome: requirements you can trace, parallel work that does not collide, a QA report you can trust

> Speaker notes: This is a packaged way of working, not a demo. The thesis is that large language models can build production software when they are wrapped in SDLC discipline: a source of truth, a contract, safe parallelism, executable gates, and adversarial verification. Everything that follows is reusable across domains; the only worked example is a sanitized internal tool (the reference project).

---

# The Problem: Naive AI Coding Does Not Scale

- Context thrash: the model re-reads the whole tree every turn and still loses the thread
- Hallucinated requirements: confident code for a spec that was never in the document
- Agents colliding: parallel sessions edit the same files and overwrite each other
- "Done" is self-declared: no executable proof a change actually works
- QA theater: a single optimistic pass that confirms what the UI shows, not what persisted

> Speaker notes: Every team that has tried to scale AI coding hits the same five walls. They are not model-capability problems; they are process problems. The kit exists because each wall has a concrete, repeatable countermeasure. Frame the rest of the deck as five answers to these five failures.

---

# The Idea: One Operator, a Fleet of Disciplined Agents

- The operator is the orchestrator, not the typist: they set the mission and run the gates
- Agents are specialized roles: ingesters, planners, module builders, integrator, QA testers
- Every agent works from a shared source of truth and a versioned contract, never from memory
- Parallelism is the default; isolation and append-only seams make it safe
- The kit encodes the discipline so the result is reproducible, not a lucky run

> Speaker notes: Think of it as a software team where the engineers happen to be Claude sessions. The human stays in the high-leverage seat: defining the slice, approving the plan, and running the gates that decide what is real. The agents do the volume work in parallel. The kit is the operating manual that keeps that team coordinated.

---

# The Loop: BRD to Tested App

- BRD corpus  ->  Knowledge Base  ->  Spec  ->  Plan  ->  Parallel Build  ->  Integrate  ->  QA
- Knowledge Base: the requirements, made agent-searchable and provenance-tagged
- Spec: acceptance criteria + modules + design + build plan (the development contract)
- Parallel Build: worktree-isolated module agents working append-only seams
- Integrate: a separate, gated merge run; QA: heavy browser testing with adversarial re-verify

> Speaker notes: This single line is the spine of the whole methodology. Each stage is deterministic and hands a typed artifact to the next, so a later stage never has to re-derive an earlier one. Read it left to right: documents become knowledge, knowledge becomes a contract, the contract becomes parallel work, and gates plus QA decide what ships.

---

# What a Knowledge Base Is, and Why It Is the Foundation

- A searchable markdown mirror of the original BRD corpus, built once, reused by every agent
- Agent-searchable: an agent greps one ID instead of re-reading hundreds of pages of source
- Provenance-tagged: every converted doc opens with a "> Source:" line back to the original file
- Native requirement IDs are first-class: ORG-CM-ACA-BR001, DC_007, FCS-CMD-PRC-1.1 kept verbatim as headings and grep targets
- Excluded/stale (-OLD-) and dedup canonical-copy rules are explicit, so no agent cites the wrong version

> Speaker notes: This is the centerpiece. The knowledge base is what kills context thrash and hallucinated requirements at the root. Because native IDs survive verbatim, an agent can grep one identifier and land on exactly the governing paragraph, then cite it back with a file and line. Provenance plus an explicit excluded list means the model can never quietly build from a superseded document. Everything downstream cites the KB; if the KB is wrong, everything is wrong, so we invest here first.

---

# How We Build the Knowledge Base

- markitdown (Microsoft, MIT) converts .docx/.pptx/.pdf/.html to markdown; pinned to a Python 3.13 pipx venv (3.14 has wheel gaps)
- Quirk handled: markitdown inlines embedded images as base64 data URIs, so we strip them in post-process
- Custom extractors fill the gaps markitdown leaves: .vsdx (Visio) and per-sheet .xlsx splitting
- Bilingual + degraded scans: Arabic and OCR sources flagged with a quality caveat in each area manifest
- Conventions baked in: mirror the folder tree, a master INDEX.md section map, per-area _manifest.md, dual-capture flows (ordered step text AND a rendered png/pdf)

> Speaker notes: The ingestion pipeline is deterministic and shipped as scripts, not hand work. markitdown does the heavy lifting on Office and PDF formats; we ship extractors for the two things it cannot do well, Visio diagrams and multi-sheet workbooks. Process flows are captured twice on purpose: ordered step text is what an agent builds logic from, but the rendered diagram preserves branch and arrow topology the text loses. The manifests record method and caveats so a reader knows when OCR output needs verification against the canonical instrument.

---

# The Development Contract

- A deterministic funnel turns prose into testable units: BRD.docx -> BRD.md -> BRD-INDEX.md -> per-section slices
- Acceptance-criteria ledger: every criterion copied verbatim, given a stable ID, tagged surface [backend]/[frontend]/[both]/[contract] and a delivery round
- The acceptance criterion is the unit of "done": each one must map to a verification (testing is opt-in — a passing test for the protected core, else live-app)
- MODULES.md: a glob-based ownership registry of vertical-slice modules
- Per-module design spec, then a build plan decomposed into B-/F- tickets with exact Files, schemas, an endpoint table, "ACs to turn green", and gate commands

> Speaker notes: This is how a requirement becomes something an agent can finish and a gate can check. The acceptance-criteria ledger is the contract: nothing is "done" until its AC is verified. Testing is opt-in — protected-core ACs (state machine, RBAC, audit, temporal/SLA, scoring) demand a passing automated test against a real DB; everything else is verified on the live app. Modules are defined by file globs so ownership is unambiguous, and each build ticket names the exact files, endpoints, and the specific ACs it must turn green. By the time an agent starts coding, there is no ambiguity left to hallucinate into.

---

# Safe Parallelism: Owned Globs + Four Append-Only Seams

- Each module agent owns its globs and only appends one line to each shared seam, never editing another module's lines
- Seam 1: a per-module schema file in a multi-file DB schema dir (a _base file holds cross-cutting models)
- Seam 2: an API module registry line; Seam 3: a nav registry line (a unit test enforces unique keyboard chords)
- Seam 4: a contracts schema file + one index export line
- The contracts package VERSION BUMP is the only BE<->FE coordination signal; agents never bump it — the integrator does that once at merge

> Speaker notes: This is the mechanism that lets many agents build at once without overwriting each other. Instead of editing shared files, every module appends a single line to four well-known seams, and a .gitattributes merge=union rule makes those appends conflict-free. The one shared file that cannot be append-only, the contracts package version, is deliberately left untouched by builders and bumped exactly once by the integrator. That removes the last collision point.

---

# The Orchestrator Protocol: Waves, Worktrees, and a Ticket Queue

- Sequential waves, parallel within a wave: Wave 0 baselines/plan; Wave 1 discovery (file tickets, do NOT fix); Wave 2 fix/close; Wave 3 re-verify
- Every sub-agent runs in an isolated git worktree; the main tree is read-only; agents commit their own branch and NEVER push
- Branch names embed a session short id so concurrent sessions cannot collide
- Tickets: <id>-<slug>.todo.md with YAML frontmatter; lifecycle is the DIRECTORY (inbox -> in-progress -> done/escalated), not a status field
- Tickets are never deleted; producers never edit their own queued tickets — mistakes become new tickets

> Speaker notes: Waves separate discovery from fixing so a producer never races a consumer. Worktree isolation is the hard boundary: a sub-agent literally cannot touch the main tree or another agent's branch, and it never pushes, so the operator stays in control of what merges. The ticket queue is an append-only audit trail; lifecycle is encoded by which folder a ticket lives in, which means the queue state is always greppable and never silently overwritten.

---

# Integration: A Separate, Gated Run

- Integration is its own run, never trusted from an agent's self-declared "done"
- Gates are EXECUTABLE: typecheck + lint clean, unit tests green, browser/e2e green, contracts build clean
- Baseline keyed by HEAD SHA + BASELINE-NOTES of pre-existing failures, so a real regression is distinguishable
- Merge in documented order, then re-emit as atomic conventional commits via cherry-pick by file-set
- Tag a checkpoint BEFORE any protected-core/schema/migration change; a pre-merge Opus pr-reviewer gate runs first; the run does NOT push or open a PR

> Speaker notes: "Done" means a gate passed, not that an agent said so. The orchestrator runs the gates itself and compares against a recorded baseline so it can tell a new regression from a pre-existing failure. Integration rewrites the merge into clean atomic commits so the history reads like a careful human did it, and it tags before any risky schema change so a rollback point always exists. Crucially it stops short of pushing — the operator reviews the clean branch.

---

# Heavy QA: Orchestrator + Browser-Tester Fleet + Adversarial Verification

- An Opus orchestrator drives N Sonnet headless browser-testers via claude -p, each confined to browser-only Playwright MCP
- --allowedTools "mcp__playwright" is the safety boundary: testers cannot touch code, DB, or CLI, and cannot write files, so each emits findings as its final message
- Canary one persona first, cap ~4 concurrent, run in two waves
- MANDATORY Phase 3: the orchestrator re-verifies every Critical/RBAC claim in its own authenticated session — capture POST status + hard-reload to prove persistence vs optimistic UI
- Reconcile severities across personas into a corroboration matrix, then write the report; the kit ships a remote-qa-launcher script the original project never committed

> Speaker notes: The tester fleet finds issues fast and in parallel, but raw model findings are not trustworthy on their own. Phase 3 is what makes the report credible: the orchestrator re-checks every critical and access-control claim itself, confirming the server actually persisted the change with a POST status and a hard reload rather than believing an optimistic UI. One data-residency caveat: a personal remote box is fine for synthetic seed data only — regulated or PII data must stay inside the approved hosting boundary.

---

# Hard-Won Lessons (Top 5)

- A knowledge base beats a bigger context window: grep one native ID, cite file:line, never re-read the corpus
- Append-only seams + owned globs are the difference between parallel agents and parallel corruption
- The contract version bump is the one coordination signal — let exactly one role own it
- Never trust self-reported "done": only an executable gate against a recorded baseline counts
- Adversarial Phase-3 re-verification is what turns AI QA from theater into evidence

> Speaker notes: These five are the distilled payoff of the whole exercise. If a team adopts nothing else, these are the load-bearing ideas. Note that each maps directly back to one of the five failure modes from slide two — the kit is the disciplined inverse of naive AI coding.

---

# What Is in the Box

- A Claude Code plugin: skills (corpus-ingestion, orchestrator-protocol, data-schema), slash commands (kit-ingest, kit-bootstrap, kit-orchestrate, kit-integrate, kit-qa)
- Ingestion toolkit: setup.sh, ingest.py, strip_data_uris.py, gen_index.py, and custom .vsdx/.xlsx extractors
- Conventions + contract templates: CLAUDE.md/AGENTS.md, MODULES.md, acceptance-criteria, design-spec, build-plan, ticket templates
- QA toolkit: parallel-browser-qa recipe, tester-brief + MCP persona templates, the remote-qa-launcher script
- Docs: README, PLAYBOOK, LESSONS, MANIFESTO; install by adding the marketplace and enabling the plugin

> Speaker notes: The kit is self-contained and runnable on macOS or Linux with bash, git, python3, and node. Install is the standard Claude Code plugin flow: add the marketplace entry, enable the plugin, and the skills and slash commands appear in any session. Everything an operator needs to run the full loop — from ingestion scripts to QA briefs — ships in the repo.

---

# Worked Example and Call to Action

- The reference project, a Next.js / Fastify / Prisma / SQL Server internal tool, went BRD-to-tested this way
- Outcomes: traceable requirements (every AC cites a source), parallel module builds with no cross-module collisions
- Gated integration produced a clean atomic-commit history; heavy QA produced a corroborated, re-verified report
- Core kit is fully domain-agnostic; an optional ORG preset adds Entra SSO, Arabic/RTL, and statutory audit guidance
- Call to action: adopt the loop on one slice, prove the gates, then scale the fleet

> Speaker notes: the reference project is the sanitized reference — we share the shape and the outcomes, not infrastructure details. The lesson is that the methodology, not any one stack, is what carried it from requirements to a tested app. The core is generic on purpose so any team can adopt it; organization-specific concerns live only in the preset. Start small: run the loop on a single vertical slice, prove the gates work, and grow the agent fleet from there.

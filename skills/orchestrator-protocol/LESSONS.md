# LESSONS.md — append-only learnings from orchestrator runs

Format: one entry per learning. Lead with the rule. `Why:` is the originating incident. `How to apply:` is the precise hook so a future run knows exactly when to invoke it.

---

## 2026-05-22 — Production-Readiness run (reference project)

### L1 — Every sub-agent uses `isolation: worktree`

**Why:** First-wave sub-agents shared a single working tree. W3 errored mid-task ("API Error: Overloaded" after 73 tool uses). W5 and W6 both reported HEAD swaps mid-edit as other agents `git checkout`-ed. W6's commits leaked onto W5's branch. W2's `.gitignore` append was clobbered by another agent's checkout, so its tickets briefly disappeared. W1 unilaterally created its own worktree partway through and avoided all of this. Wave 2 and W3-retry uniformly used `isolation: worktree` — zero interleaving incidents.

**How to apply:** Default `isolation: "worktree"` on every `Agent` call. Override only with a written reason in the brief (e.g. read-only consolidators). This is non-negotiable; the protocol enforces it.

---

### L2 — Pre-commit `.gitignore` + `.gitattributes` on main BEFORE Wave 1

**Why:** During the prior run, two collisions cost real time:
1. `.orchestrator/` was not in `.gitignore`. The W7 sub-agent's commit accidentally tracked five `.todo.md` files — when other agents `git checkout`-ed to other branches, the tickets vanished from the working tree (because the files were on a different branch). Recovery required `git show <branch>:<path>` for each ticket.
2. Two agents both appended to `docs/open-questions.md` and `tests/qa/findings/by-persona/admin.md`. The integration merge hit a content conflict in pure append regions — a `merge=union` driver would have resolved it automatically.

**How to apply:** `scripts/orchctl-init.sh` runs both steps idempotently. The orchestrator calls it before spawning anything. Skipping this is a protocol violation.

---

### L3 — Per-agent tool-call budget (default 150) with save-state-on-overrun

**Why:** W3-original ran 73 tool uses and errored on API Overload mid-task. It left an uncommitted spec stub in the working tree that confused the next agents. Had it been budgeted with a "save state, report blockers, exit cleanly" rule at, say, 150 calls, the retry could have started from a known state.

**How to apply:** Every sub-agent brief includes "Limit yourself to 150 tool calls. If you hit the limit, save state, file blockers as .todo.md tickets, and report — do NOT keep running." Profile overrides allow heavier archetypes (integrator: 300).

---

### L4 — Surface conflicts, do NOT auto-merge across branches

**Why:** The Phase 3 consolidator attempted a multi-branch integration merge and was denied by the auto-mode classifier (correctly — the brief said don't auto-merge). The bigger insight: multi-branch integration is a **distinct** orchestrator run with its own waves, reviewers, and atomic-rewrite phase. Mixing it into Phase 3 of a discovery run muddles both.

**How to apply:** Discovery orchestrator (`/orchestrate`) ends at the operator-facing report. Integration is a separate invocation (`/integrate`) using `templates/integration-report.md.tmpl`. The protocol's Phase 3 is consolidation + reporting only, never merging.

---

### L5 — Background agent etiquette: notifications, not polling

**Why:** Two near-misses where the temptation was to read the background agent's output file directly. Those files are the full JSONL transcript and overflow the orchestrator's context if read.

**How to apply:** `run_in_background: true` for anything > ~60 s. Wait for the system completion notification. Never `tail` or `Read` the transcript output file. Inspect tooling output only via the project's own log files (e.g. `.artifacts/<agent>.log`) that the agent writes deliberately.

---

### L6 — Memory-on-opinion is mandatory

**Why:** Operator twice corrected the orchestrator mid-run — first that a non-default Azure tenant was an intentional dev tenant (not a critical Azure-tenant mismatch), then that Elasticsearch was preferable to Loki because the operator queries it daily and the image was cached locally. Both belonged in project memory the moment they were said. Writing them mid-stream worked, but should be a hard rule so the next session never re-litigates either.

**How to apply:** Every orchestrator and sub-agent that receives an opinion / preference / correction from the operator MUST write a project-memory entry under `~/.claude/projects/<slug>/memory/` and update `MEMORY.md` before continuing. The memory file format is the one in `~/.claude/CLAUDE.md` "auto memory" section.

---

### L7 — Verdict over options menu

**Why:** Same conversation, twice in a row, the operator said variants of "don't follow my opinion, give me a verdict." The orchestrator's first instinct was to enumerate alternatives and defer the choice. The operator wanted a decision with rationale.

**How to apply:** When asked "what should we use" or "what's the best approach", the orchestrator and every sub-agent return **one** recommendation + the trade table that led there. Never present a menu and ask the operator to pick unless they've explicitly delegated.

---

### L8 — Standardized report shape per sub-agent

**Why:** Every sub-agent brief in the first run reinvented its own report-back format. Comparing reports across agents was harder than necessary.

**How to apply:** The protocol §5 fixes the report shape. The orchestrator template includes the shape verbatim in every spawn brief.

---

### L9 — Each closed ticket gets a `## Resolution` block before moving to done/

**Why:** The orchestrator had to reconstruct closure rationale from commit messages and agent reports. The ticket files themselves were silent about which commit closed them and which gate confirmed it.

**How to apply:** Consumer protocol (§3) makes a `## Resolution` block mandatory. The consolidator script (`scripts/orchctl-drain.sh`) refuses to count a ticket as "done" without one.

---

### L10 — Integration is a separate orchestrator (`/integrate`)

**Why:** See L4. Plus: the integration workflow has its own waves (merge → review → atomic rewrite) that don't map onto the discovery wave model.

**How to apply:** Two slash-command entry points: `/orchestrate <mission>` for discovery+fix+re-verify, `/integrate` for branch consolidation + atomic-commit rewrite. Don't mix.

---

### L11 — Cross-session git interference is real; isolate explicitly

**Why:** Operator reports that concurrent Claude sessions on the same machine interfere with each other through the shared git working tree. The first orchestrator run also saw intra-session interference (W3 vs W5 vs W6 swapping HEAD on the shared working tree). Both classes have the same root cause: agents share a working tree they don't own.

**How to apply:** Three reinforcing rules:
1. `scripts/orchctl-init.sh` claims `.orchestrator/session.lock`. A second session can't start without explicit override (stale-lock detection at 1 h).
2. Branch names embed the orchestrator's session short-id as a suffix (`-s<5char>`), so two concurrent sessions on similar missions cannot collide on branch names.
3. The main working tree is read-only for sub-agents. Sub-agents only operate in their `isolation: worktree` worktree. The orchestrator's `git` calls on the main tree are limited to `status/log/show/diff` — never `checkout/merge/rebase/stash pop`.

See PROTOCOL.md §11.

---

### L12 — Commit discipline: logical-boundary commits, never WIP-then-squash

**Why:** Operator wants a clean reviewable git history. The first run produced a mix: W7 committed cleanly per concern; F2 leaked onto the wrong branch with mixed commits; W3-original left uncommitted work. A reviewer reading the eventual PR can't easily map commits to tickets when the history is uneven.

**How to apply:** Every sub-agent commits at logical boundaries (one commit per ticket closed, per spec batch added, per migration). No "end-of-session" mega-commits. No "WIP" / "fixup" commits in the branch tip. Every commit independently typechecks and lints clean. Conventional commit messages include `Closes: <ticket-id>`, `Risk: HIGH|MEDIUM|LOW`, and a one-paragraph WHY body. See PROTOCOL.md §12.

---

### L13 — Senior PR review pass on Opus before integration

**Why:** Real SDLC has a senior code reviewer who sees the whole PR diff and gates merge. Without it, integration runs end with merged history that no second eye has examined. Putting the reviewer on Opus (vs the working agents on Sonnet) buys deeper analysis where it matters most.

**How to apply:** `agent-profiles/pr-reviewer.yaml` (model: opus, budget: 300). Invoked via `/review-pr <branch-or-mission>` or as a Wave 2.5 spawn inside `/orchestrate`. Produces `PR-REVIEW-<MISSION>-<DATE>.md` at the repo root, files `.todo.md` for blocking findings, refuses to approve a branch with any `priority=critical` or `priority=high` finding open. See PROTOCOL.md §13.

---

### L14 — SDLC simulation framing

**Why:** Operator's ultimate goal is to simulate real-life SDLC inside Claude using the orchestrator + sub-agent pattern. Naming each archetype against its SDLC role makes the framework legible to anyone familiar with normal software process.

**How to apply:** The PROTOCOL.md §14 mapping (`/goal` = TPM, `discoverer` = tech lead, `fixer-{api,web}` = devs, `re-verifier` = QA, `perf-smoke` = perf engineer, `integrator` = release engineer, `pr-reviewer` = senior reviewer, `consolidator` = engineering manager) is explicit and stable. Operators tailoring a mission can drop or double up roles per stage with that mapping in mind.

---

### L15 — Logs are the bug channel; operators do not file tickets by hand

**Why:** Operator's flow is: bookmark a session, exercise the app manually + let a Playwright QA agent run alongside, then close the session. Bugs surface as structured log events in the project's logging sink (Elasticsearch + Kibana for dev laptops per memory entry `logging-stack-choice`). A subsequent orchestrator run reads the bookmarked window, clusters events, and files `.todo.md` tickets for the Wave-2 fixers.

**How to apply:**
- Every fixer agent that writes server code MUST emit structured log events on error (PROTOCOL.md §15.1).
- The `qa-playwright.yaml` agent runs Playwright suites against the real stack and emits every failure as a log event — does NOT file `.todo.md`.
- The `log-reader-triage.yaml` agent queries the sink for the orchestrator's session window, clusters by `error.message + top-stack-frame + route`, and files one `.todo.md` per cluster.
- Manual testing and automated QA share the SAME logging channel and the SAME triage agent. Operator never opens tickets by hand.
- Every event carries the orchestrator's `session_id` so concurrent sessions don't cross-pollute.

---

### L16 — Tooling assessment: GitNexus in, Ruflo out

**Why:** Operator asked to assess GitNexus and Ruflo for inclusion. Honest evaluation against speed / token cost / quality / maintenance found:

- **GitNexus** materially reduces tokens per impact-analysis call (~200–500 tokens vs 2–5k for grep+read), catches transitive callers grep misses, and the failure mode (stale index) is graceful. **Adopt as preferred.**
- **Ruflo** duplicates surfaces the framework already covers (memory dir, parallel agents, slash commands), adds latency via UserPromptSubmit routing, and its agent prompts are kitchen-sink (token-heavy). The "learning daemon" is opaque, which violates the "verdict over options with rationale" rule (L7). **Skip as baseline dependency.**

**How to apply:** PROTOCOL.md §6 names `gitnexus_impact` as the preferred impact-analysis tool with a `grep -rn` fallback. The `onboarder.yaml` profile offers to run `npx gitnexus analyze` at framework adoption. The framework's `/orchestrate`, `/integrate`, `/review-pr` do NOT depend on Ruflo's tools. Projects that already have Ruflo installed can keep it but the framework treats it as project-local. See `TOOLING-ASSESSMENT.md` for the full evaluation matrix.

---

### L17 — Cross-surface session tests are mandatory; isolated specs miss shared-cache bugs

**Why:** 2026-05-23 incident on the Resource Planning project. Operator opened the app for "barely any manual testing" and within minutes hit `assignments.map is not a function`. Root cause: two React Query consumers (`ActivityDrawer` and `QuickActionsModal.AssignSection`) shared a queryKey but disagreed on the unwrap shape. First-writer-wins on the cache; second reader gets a non-array. The qa-sweep suite was 93/103 passing, the API vitest pack was 99.78%, a11y was 10/10 — and none of those caught it because **every spec opened a single surface in isolation**. Component tests mocked `queryFn` directly so the contract drift never saw a real response. Real-API E2E was parked behind an unrelated escalation. The class of bug — shared-cache contract drift — only manifests when ≥ 2 surfaces touch the same entity in one session.

**How to apply:**
1. Every QA wave produces at least one **cross-surface session spec** per feature area, defined as: open route A → exercise the shared-state read → navigate to route B that reads the same cache key → assert no `ErrorBoundary` fallback, no `pageerror`, no `console.error`. Reference implementation: `apps/web/tests/e2e/qa-sweep/16-cross-surface-cache.spec.ts` in the reference project.
2. The cross-surface spec uses a Page-Error tracker (`page.on("pageerror")` + filtered `page.on("console")`) and fails the test on any uncaught error during the session window — not just the asserted state.
3. The `qa-playwright.yaml` profile names cross-surface as a `must_cover` axis, not an optional one. A re-verifier wave that produced zero cross-surface specs is incomplete by definition.
4. When the operator reports a manual-test crash that QA missed, the consolidator MUST identify which surface combination was untested and file a cross-surface spec as part of the resolution. The reverification gate is "spec exists AND fails before fix AND passes after."

---

### L18 — Mock/real-API contract conformance must be a merge-gate test, not a hope

**Why:** Same 2026-05-23 incident. MSW handlers in `apps/web/src/mocks/handlers/` returned the new `{ data: [...] }` envelope to match the real API. The web code had two consumer styles for list endpoints — `apiList` (correct, unwraps both shapes) and `apiFetch<{ <plural>: T[] }>` (legacy, reads a key that hasn't existed for months). The legacy path silently returns empty arrays against either backend AND collides when sharing a queryKey with an `apiList` consumer. **Twelve such offenders had survived in main**; a static scan added during the incident response found them in one pass. The MSW/real-API parity assumption was correct; the **client-side reader pattern** was where the drift hid.

**How to apply:**
1. Every project that exposes both a mock and real backend lands a static gate (Vitest, ESLint, or `tsc` plugin — implementation detail) that asserts every list-endpoint reader uses the project's contract-normalising helper (`apiList` in the reference project, equivalent elsewhere). Net-new code that introduces an envelope-shape `useQuery<{ ... }>` fails the merge gate. Reference: `apps/web/src/lib/query/__tests__/list-query-shapes.test.ts`.
2. The gate has a `PARKED_OFFENDERS` allowlist for known existing drift; each entry names a ticket id so the rollup work is tracked, and removing an entry without fixing the file goes red (forces both directions of drift to be visible).
3. The discoverer wave runs the gate during its initial scan. Any entry that lands in the allowlist becomes a `medium`-priority rollup ticket for the fixer wave.
4. PROTOCOL.md §15.7 codifies the contract-conformance gate as a required deliverable in Wave 1 of any production-readiness orchestrator that touches a project with both mock and real backends.

---

### L19 — Fatal client events flush synchronously; never trust a batch timer for the page-is-on-fire path

**Why:** Same 2026-05-23 incident, third root cause. The web `clientLogger` batched events on a 2-second timer. ErrorBoundary catches, `window.onerror`, and `unhandledrejection` all enqueued and waited for the timer. A user staring at "Something went wrong." typically clicks "Try again" or navigates within 1 second — well under the timer — so the buffer disappeared before the flush fired. Synthetic markers from the gated smoke test landed in ES because they had time to flush; **organic browser errors never did**. The operator pasted the stack trace by hand. The logger pipeline can be 100% wired and still be effectively blind to the exact errors it exists to capture.

**How to apply:**
1. Any client-side logger that emits to a network sink MUST classify events as `fatal` vs `batchable` and flush `fatal` events synchronously via `navigator.sendBeacon` (or `fetch({ keepalive: true })` as fallback) at enqueue time. The 2s/50-event policy is fine for `batchable` (info, warn, web-vitals, axe).
2. The three canonical fatal classes are: React `ErrorBoundary.componentDidCatch`, `window.onerror`, `unhandledrejection`. Future projects MAY add more; never remove these.
3. Verifier suites for logging stacks MUST include a "fatal event arrives within 1 second after a real boundary catch" check, exercised against a hot dev server (not a unit-test seam). The reference project's `pnpm logs:verify` had 8 PASS checks while the live path was dark — the smoke deliberately bypassed the route handler.
4. PROTOCOL.md §15.6 codifies the fatal-class definition + synchronous-flush + verifier requirement.

---

### L20 — Orchestrators clean up their own worktrees and branches at session close

**Rule:** Phase 3 consolidation runs `scripts/orchctl-session-release.sh`, which prunes the session's own artifacts (PROTOCOL.md §11.6) under a **strict two-gate test**: (a) fully merged into `$MISSION_REF` (default `HEAD`) AND (b) clean. Anything failing either gate is preserved and listed in the report as DIRTY-SKIP or UNMERGED-SKIP — **the cleanup script never deletes unmerged work, period**. It uses `git branch -d` (never `-D`); `--force` on `git worktree remove` is permitted only to bypass the harness lock flag after both gates have already passed. External worktrees (`/private/tmp/*`, `<repo-parent>/<mission>`) are NOT auto-removed regardless of merge state — the final report calls them out for manual disposition.

**Why (reference project, 2026-05-24):** After two days of orchestrator runs the operator's repo had **86 local branches, 29 worktrees, and 25 locked agent worktrees in `.claude/worktrees/`**, of which 33 branches and 1 worktree were fully merged into the current mission head and just sitting there. Manual cleanup took a guided AskUserQuestion round-trip and several minutes of `git branch -d` iteration. The sessions that produced those branches had Phase 3 reports but their release script only cleared `session.lock` — nothing pruned the worktrees or the harness-created `worktree-agent-<hex>` branch refs. This is the predictable tax of "make the session leave it where it lay." The fix has to be in the release path (not a manual sweep) because operators forget, and because the orchestrator is the only actor that knows which artifacts belonged to which mission.

**How to apply:**
1. Every orchestrator session ends by running `scripts/orchctl-session-release.sh`. Phase 3 of the protocol calls it. If Phase 3 is skipped, the cleanup is skipped — that's a known cost of bailing out early; the §16 DoD requires Phase 3 to run.
2. The script is conservative by default: it uses `git branch -d` (never `-D`) and `git merge-base --is-ancestor` against `$MISSION_REF`. It WILL refuse anything not fully merged or anything dirty. Override only by hand, never automate the force-delete path.
3. The final operator-facing report includes the cleanup summary line + the DIRTY-SKIP / UNMERGED-SKIP lists so the operator can act on the survivors. §16 DoD item 7 makes this a release gate.
4. If a project keeps mission-specific external worktrees (the reference project uses `/private/tmp/<mission>` for integration scratch), the consolidator lists them under "manual cleanup recommended" in the report. The script doesn't touch them.

---

### L21 — Replace eager must-reads with an on-demand context index; wire GitNexus into every fixer/reviewer brief

**Rule:** Sub-agent briefs read TIER-0 only (CONTEXT-INDEX.md + PROTOCOL.md §1/§4/§5/§6 + project CLAUDE.md Architecture/Conventions headings — ~200 lines total). Everything else is TIER-1 (keyed by the profile's `index_keys:`, 3-5 entries) or TIER-2 (on-demand by trigger, e.g. "I'm touching MSW" → fetch L18). Symbol-shaped lookups (callers, blast radius, processes) go through GitNexus tools (`gitnexus_query`, `gitnexus_impact`, `gitnexus_context`, `gitnexus_detect_changes`, `gitnexus_rename`), never `grep -rn` + `Read`. Every profile that touches product code sets `code_intelligence: gitnexus`, which causes the orchestrator to inject `templates/gitnexus-stanza.md` verbatim into the brief.

**Why (reference project, 2026-05-24):** Sample sub-agent ran 175s + 17 tool calls to read 11 files and write a single findings doc. The latency-diag agent measured the cost: 6-8 files / ~700 lines were eagerly read before ANY useful action, even by read-only producers. Phase 0 baselines re-ran 7 gates every session including two known-red pre-existing ones, with no caching. Hard-rules block (12 universal + L17/L18/L19 must-cover) was injected verbatim into briefs for agents whose entire allowed_actions list was "file `.todo.md`". And the agent had no idea GitNexus existed despite the project's `CLAUDE.md` mandating `gitnexus_impact` before edits — the orchestrator-protocol mentioned it once inside the 50-line hard-rules wall and trusted agents to remember. They did not. The operator's verdict: "optimize the reading pattern across the board, and use GitNexus."

**How to apply:**
1. `~/.claude/skills/orchestrator-protocol/CONTEXT-INDEX.md` is the only entry point. Sub-agents read it as part of TIER-0 and use its trigger table to decide what else to fetch.
2. Agent profiles replace flat `must_read:` lists with `must_read_always:` (0-2 entries) + `index_keys:` (3-5 TIER-1 keys) + `code_intelligence: gitnexus | none`.
3. `templates/subagent-prompt.md.tmpl` exposes `{{INDEX_KEYS_BLOCK}}` and `{{CODE_INTELLIGENCE_STANZA}}` placeholders. The orchestrator fills both at compose time.
4. Report-back contract gains `Index keys consumed:` + `GitNexus usage:` lines so the operator can audit the actual read budget per run.
5. The previous "everyone reads everything" shape is now a protocol violation; PROTOCOL.md §4 + §6 codify the new contract.

---

### L22 — Inline-by-default brief composition + four-state status protocol + self-contained briefs

**Symptom (pre-L22):** even after L21 demoted eager `must_read:` to TIER-0 (~200 lines paid once per spawn), every sub-agent in a wave still paid that tax for static content (PROTOCOL §4/5/6, CLAUDE.md headings) that's identical across the wave. Additional waste: sub-agents did exploratory `grep + Read` to find the file they were supposed to edit, because the brief told them what but not where. Eight wave-1 fixers × ~400 lines of bootstrap each = 3200 lines of pure waste per wave.

**Decision:** the orchestrator becomes a *brief composer with code-intel*, not a *dispatcher*. Before each spawn:
1. Run `gitnexus_query` → `_context` → `_impact` on the ticket's primary symbol. Inline file:line + callers into a new "Targeted work map" section.
2. Inline static content (hard rules, today/infra/auth, wave/queue, and per-profile `inline_keys:`) into a new "Inlined facts" section. TIER-0 reads become zero in the happy path.
3. Anti-pattern self-check the draft against `templates/anti-patterns.md`. Rewrite ❌ → ✅ before spawning.

**Imports from superpowers (consumed, not duplicated):**
- Self-contained-briefs principle (`superpowers:dispatching-parallel-agents`).
- Controller-provides-full-text rule (`superpowers:subagent-driven-development`).
- Four-state status protocol — `DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED` (`superpowers:subagent-driven-development`).
- "Before You Begin" + "When You're in Over Your Head" + self-review checklist (`superpowers/subagent-driven-development/implementer-prompt.md`).
- No-placeholders rule for briefs (`superpowers:writing-plans`).
- Bad-vs-good Common Mistakes table (`superpowers:dispatching-parallel-agents`).

**Inventions on top of superpowers (candidates for upstream contribution after ~5 missions):**
- `Targeted-read accuracy: yes/mostly/no` self-reported metric — a per-task targeting-quality feedback loop that superpowers does not have.
- TIER fallback tiers — graceful degradation for cases where full-inlining is impractical (huge ADR trees, project-specific lesson tails).
- Pre-spawn code-intel ritual (`gitnexus_query → _context → _impact`) as a load-bearing step before brief composition.

**Mechanism:** PROTOCOL §1.1 (per-spawn ritual), §4 (sub-agent contract — self-contained briefs), §5 (report-back with mandatory `Status:` first line). Template at `templates/subagent-prompt.md.tmpl` restructured. Profiles gain `inline_keys:` + `self_review_categories:`. New reference file `templates/anti-patterns.md`. CONTEXT-INDEX.md grows an "Inline-key registry" and demotes TIER-0 from "always" to "fallback only".

**Health metric:** wave-level `Targeted-read accuracy` (yes + mostly rate). Below 70% across a wave → pause for review. Below 60% across two consecutive missions → roll back to the L21 shape. The rollback restores the `.bak` files written during the L22 implementation.

**Spec:** `docs/superpowers/specs/2026-05-24-orchestrator-targeted-brief-design.md`
**Plan:** `docs/superpowers/plans/2026-05-24-orchestrator-targeted-brief.md`

---

## How to add a new lesson

After each orchestrator run, the consolidator (the human or the agent) appends one entry per non-trivial learning. Keep the `Rule / Why / How to apply` shape — the `Why` is what future-you needs to judge edge cases; the `Rule` alone rots without context. Number new lessons in sequence and keep them in numeric order.

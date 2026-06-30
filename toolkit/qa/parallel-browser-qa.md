# Parallel Browser QA — the canonical local recipe

This is the heart of the kit's QA layer: a fleet of headless Claude Code browser-testers
exploring the running app per persona, supervised by one Opus orchestrator that does NOT
trust their findings raw. It is the **exploratory depth** layer — it complements, never
replaces, the deterministic regression suite that guards the merge gate (see `README.md`).

> Hard truth carried over from the original project: the "run this farm on a remote box
> over an SSH tunnel" plumbing was never committed — it lived as operator tribal knowledge.
> This file is the canonical **local** recipe. The reusable remote artifact the original
> lacked ships alongside it as `remote-qa-launcher.sh`.

---

## 1. Roles

| Role | Model | Count | Tools | Job |
|------|-------|-------|-------|-----|
| Orchestrator | Opus | 1 | full toolset, authenticated browser of its own | Plans personas, launches testers, captures logs, **re-verifies every Critical/RBAC claim itself**, reconciles severities, writes the report |
| Browser-tester | Sonnet | N (cap ~4 concurrent) | `mcp__playwright` ONLY | Drives the app as one persona, walks assigned surfaces, emits findings as its final message |

The asymmetry is deliberate. Sonnet testers are cheap, parallel, and good at breadth —
clicking everything, noticing console noise, trying RBAC boundaries. They are also prone to
**optimistic-UI false positives** (a toast said "Saved" so they call it saved) and to
**over-claiming severity**. Opus is the expensive adversarial reviewer that converts a pile
of unreliable persona logs into a trustworthy report. Never ship a tester's raw findings as
the result.

---

## 2. The exact invocation

Each tester is a one-shot headless `claude -p` session, confined to the Playwright MCP:

```bash
claude -p "$(cat brief.$P.md)" \
  --model sonnet \
  --mcp-config mcp.$P.json \
  --strict-mcp-config \
  --allowedTools "mcp__playwright" \
  > "$P.log" 2>&1
```

Where `$P` is the persona id (e.g. `caseworker`, `supervisor`, `readonly`, `admin`).

| Flag | Why it exists |
|------|---------------|
| `-p "$(cat brief.$P.md)"` | One-shot prompt = the persona brief (template: `tester-brief.md.tmpl`). |
| `--model sonnet` | Breadth workers are cheap; Opus is reserved for orchestration + verification. |
| `--mcp-config mcp.$P.json` | Pins exactly one MCP server — Playwright — with a per-persona screenshot dir (template: `mcp.persona.json.tmpl`). |
| `--strict-mcp-config` | Ignore any ambient/user MCP config. The tester gets ONLY what this file declares — no surprise tools. |
| `--allowedTools "mcp__playwright"` | **The safety boundary.** See below. |
| `> "$P.log" 2>&1` | The log is the only output channel. The tester's final message is captured from here. |

### Why `--allowedTools "mcp__playwright"` is the safety boundary

The tester can drive a browser and nothing else. It **cannot** run Bash, edit code, touch
the database, call the filesystem, or reach any other MCP. Three consequences you are
relying on:

1. **Blast radius is zero.** A confused tester cannot `rm`, cannot mutate the repo, cannot
   run a migration. The worst it can do is click the wrong button in a browser pointed at a
   synthetic-data environment.
2. **No write tools means no findings file.** This is a feature, not a limitation — it forces
   the next discipline.
3. **Reproducible confinement.** Combined with `--strict-mcp-config`, the tester's capability
   set is fully described by two files you can read and diff.

### The "testers cannot write files, so they emit findings as their final message" pattern

Because a browser-only tester has no Write/Bash tool, it physically cannot save a report.
So the brief instructs it to **end its run by printing a complete, self-contained markdown
findings document as its final assistant message**. That message lands at the tail of
`$P.log`. The orchestrator harvests it from there.

This is why the brief is strict about the final message being self-contained (no "see above",
no references to scratch state) and grouped by severity under a `# QA Findings - {{PERSONA}}`
heading. The log tail IS the deliverable.

---

## 3. Rollout discipline: canary one → cap 4 → two waves

Do not launch all personas at once. Stage it:

1. **Canary one persona first.** Run a single tester (usually the lowest-privilege real user)
   end-to-end. Confirm: it logged in, it actually exercised surfaces, and its final message is
   a well-formed findings block. This catches a broken brief, a wrong `BASE_URL`, an auth
   failure, or a Playwright/MCP misconfig **before** you pay for a full fan-out.
2. **Cap concurrency at ~4.** More than ~4 concurrent headless browser sessions tends to
   starve a dev box (CPU, memory, and the app's own request capacity), which produces
   *timeout* findings that are artifacts of the test rig, not bugs. Four is the empirical
   sweet spot; tune to the host.
3. **Run two waves.** Personas split across two sequential waves (e.g. wave A:
   caseworker + supervisor; wave B: readonly + admin). Two waves give you (a) concurrency
   under the cap and (b) a natural checkpoint to sanity-check wave A's logs before spending
   on wave B. It also surfaces flakiness: a finding that appears in wave A but not a wave-B
   re-run of the same surface is suspect.

---

## 4. The MANDATORY Phase-3 adversarial verification

**This is the step that makes the report trustworthy.** Sonnet findings are raw material,
not conclusions. After all logs are collected, the Opus orchestrator re-opens the app in its
**own authenticated session** and independently re-verifies.

### What gets re-verified, and how

- **Every Critical and every RBAC claim — no exceptions.** Lower-severity items may be
  spot-checked; Critical/RBAC are always re-driven by Opus itself.
- **Prove persistence, not optimism.** The classic false positive is "it saved" because the
  UI showed success. To verify a mutation actually persisted:
  1. Capture the **POST/PUT/PATCH status code** from the network panel (a 2xx is necessary
     but not sufficient).
  2. **Hard-reload** the page (or re-fetch via a fresh navigation) and confirm the change is
     still there. Optimistic UI that reverts on reload is a *bug*, not a pass.
- **RBAC claims cut both ways.** "Persona X could do Y they shouldn't" → Opus reproduces the
  action and checks the server actually performed it (status + reload), not just that a button
  was visible. "Persona X was blocked from Y" → confirm it's a real authorization block
  (e.g. 403) and not a transient/render glitch.

### The corroboration matrix

Opus reconciles the same surface across personas and assigns each candidate finding one
status. This both **upgrades trust** (independent personas hitting the same wall) and
**downgrades noise** (one tester's flake).

| Status | Meaning | Lands in report as |
|--------|---------|--------------------|
| **VERIFIED** | Opus independently reproduced it in its own session (status code + hard-reload evidence). | Confirmed finding, full confidence. |
| **CORROBORATED** | Two or more personas independently reported the same issue, consistent with Opus's read. | Confirmed finding, high confidence. |
| **SINGLE** | One persona reported it; not yet independently reproduced. | Reported, flagged "single-source — needs reproduction." |
| **DOWNGRADED** | Opus could NOT reproduce it, or proved it was optimistic-UI / test-rig noise / a severity inflation. | Severity lowered or dropped, with the reason recorded. |

Only after the matrix is filled does Opus write the report. The report states, per finding,
its matrix status and the evidence (POST status, reload result, which personas saw it). A
reader can trust a VERIFIED Critical because the path to it is auditable.

### Why this discipline exists

Without Phase 3 you are publishing the unreviewed output of a cheap model that is known to
optimistic-pass and severity-inflate. The whole value proposition — "an autonomous QA fleet
you can trust at leadership level" — rests on an adversarial Opus pass that treats every
Sonnet claim as a hypothesis until it has POST-status-plus-reload evidence.

---

## 5. Where findings go next

The report is not the end. Confirmed findings (VERIFIED / CORROBORATED, and triaged SINGLEs)
become tickets in the orchestrator queue and a human-readable `bugs/NNN-slug.md` trio
(AUDIT / DUPLICATES / PRIORITY). Routing is by `consumer_role` (`fixer-api` / `fixer-web` /
`re-verifier` / `escalate`). See `README.md` §"From findings to fixes" for the exact flow.
DOWNGRADED items are recorded too — a documented non-bug saves the next session from
re-chasing it.

---

## 6. Copy-pasteable orchestrator checklist

```text
PARALLEL BROWSER QA — ORCHESTRATOR RUN CHECKLIST

PRECONDITIONS
[ ] App is running and reachable at BASE_URL (local compose stack or tunneled origin).
[ ] Environment is seeded with SYNTHETIC data only (never regulated/PII on a dev/personal box).
[ ] Each persona has working credentials (LOGIN) verified by hand once.
[ ] .artifacts/screenshots/ exists; .artifacts/ is gitignored.

PER-PERSONA SETUP
[ ] Render mcp.$P.json from mcp.persona.json.tmpl (absolute --output-dir per persona).
[ ] Render brief.$P.md from tester-brief.md.tmpl ({{PERSONA}}/{{LOGIN}}/{{BASE_URL}} + surfaces).
[ ] --strict-mcp-config and --allowedTools "mcp__playwright" present in the launch line.

ROLLOUT
[ ] CANARY: launch ONE persona. Confirm login, real surface coverage, well-formed final
    "# QA Findings - <persona>" block at the tail of its log. Fix the rig if not.
[ ] WAVE A: launch up to 4 concurrent. Wait for all logs.
[ ] WAVE B: launch the remaining personas (<=4 concurrent). Wait for all logs.
[ ] Harvest each persona's final message from $P.log.

PHASE 3 — ADVERSARIAL VERIFICATION (MANDATORY)
[ ] Open the app in your OWN authenticated session.
[ ] Re-verify EVERY Critical and EVERY RBAC claim:
      - capture POST/PUT/PATCH status code, AND
      - hard-reload to prove persistence (not optimistic UI).
[ ] Build the corroboration matrix: VERIFIED / CORROBORATED / SINGLE / DOWNGRADED.
[ ] Reconcile severities across personas; record the reason for every DOWNGRADE.

REPORT + HANDOFF
[ ] Write the report: per finding -> matrix status + evidence + repro steps.
[ ] File confirmed findings as orchestrator tickets (consumer_role routing).
[ ] Emit bugs/NNN-slug.md trio (AUDIT / DUPLICATES / PRIORITY).
[ ] Do NOT push, do NOT open a PR — QA emits findings; integration is a separate run.
```

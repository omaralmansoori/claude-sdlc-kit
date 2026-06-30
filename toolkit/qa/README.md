# Heavy QA — the three-layer model

QA in this kit is not one thing. It is three layers with different jobs, different trust
models, and different places in the lifecycle. Conflating them is how teams ship a green
unit suite over a broken app — or drown in a flaky LLM's false positives.

| Layer | What it is | Trust model | Role in the lifecycle |
|-------|-----------|-------------|-----------------------|
| **1. Exploratory LLM fleet** | A farm of Sonnet `claude -p` browser-testers, one per persona, supervised by an Opus orchestrator. | **Untrusted until verified.** Sonnet output is raw material; Opus re-verifies every Critical/RBAC claim (POST status + hard-reload) and builds a corroboration matrix. | **Depth.** Finds the bugs a deterministic suite never thought to assert — RBAC leaks, optimistic-UI lies, console/network noise, broken flows. Run on demand, not at every commit. |
| **2. Deterministic regression suite** | The project's own typecheck + lint + unit + e2e (mocked early, real composed stack late) + contracts build. | **Trusted, executable, reproducible.** Same input, same result. | **The merge gate.** Run by the orchestrator/integrator on every branch and every commit, keyed to a baseline. A regression here BLOCKS integration. |
| **3. Log -> triage bug channel** | The triage pass that reads warn+ logs from a bookmarked session window, clusters them, and files one ticket per cluster. | **Trusted signal, triaged for routing.** | **The bug-to-ticket bridge.** Turns runtime evidence (from layers 1 and 2, plus production logs) into queued, routed work. |

Layer 1 is documented in **`parallel-browser-qa.md`** (the canonical local recipe) with its
supporting templates. Layer 2 lives in the project's gate commands (see the integration
docs). Layer 3 is described below in "From findings to fixes."

---

## Files in this directory

| File | Purpose |
|------|---------|
| `parallel-browser-qa.md` | Canonical local recipe: roles, exact `claude -p` invocation, the `--allowedTools "mcp__playwright"` safety boundary, canary→cap-4→two-waves rollout, and the MANDATORY Phase-3 adversarial verification + corroboration matrix. Includes a copy-pasteable orchestrator checklist. |
| `tester-brief.md.tmpl` | Per-persona brief template (`{{PERSONA}}`/`{{LOGIN}}`/`{{BASE_URL}}`). Instructs the tester to stay browser-only, walk specific surfaces, capture console errors + non-2xx network, probe RBAC, and EMIT a self-contained `# QA Findings - {{PERSONA}}` block as its final message. |
| `mcp.persona.json.tmpl` | MCP config pinning ONLY the Playwright server, with a per-persona absolute screenshot `--output-dir`. |
| `remote-qa-launcher.sh` | The reusable remote artifact the original project never committed: opens an SSH tunnel to a remote prod-shape QA box, fans out N capped testers against the tunneled origin, collects logs. Env-driven, defensive trap, loud data-residency warning. |

---

## Run it: local vs remote

### Local (canonical)

Use this when the app runs on your machine or a local compose stack. Follow
`parallel-browser-qa.md` end to end:

1. Bring up the app with **synthetic seed data**; confirm `BASE_URL` is reachable.
2. Render `mcp.<persona>.json` and `brief.<persona>.md` from the templates (one per persona).
3. **Canary one persona**, confirm the rig works, then run **two waves** at **≤4 concurrent**:
   ```bash
   claude -p "$(cat brief.$P.md)" --model sonnet \
     --mcp-config mcp.$P.json --strict-mcp-config \
     --allowedTools "mcp__playwright" > "$P.log" 2>&1
   ```
4. Harvest each `$P.log` tail; run **Phase-3 adversarial verification** in your Opus session.

### Remote (when the app lives on a remote prod-shape QA box)

Use `remote-qa-launcher.sh`. It tunnels and fans out for you:

```bash
REMOTE_HOST=<a remote prod-shape QA box> \
REMOTE_USER=<ssh-user> \
REMOTE_WEB_PORT=3000 \
PERSONAS="caseworker supervisor readonly admin" \
CONCURRENCY=4 \
./remote-qa-launcher.sh
```

The script still leaves you the **same Phase-3 step** — it collects logs; it does not, and
must not, replace the Opus verification pass.

> **Data residency, non-negotiable.** A personal/out-of-boundary remote box is acceptable for
> **synthetic** seed data ONLY. For regulated or PII data the heavy-QA box MUST sit inside the
> approved hosting boundary (same residency perimeter as production). The launcher prints this
> warning on every run.

---

## From findings to fixes

A QA report is not the deliverable — **routed, queued work** is. Once Phase-3 produces the
corroboration matrix, confirmed findings flow back into the orchestrator's ticket queue and a
parallel human-readable bug record.

### 1. Into the `.orchestrator` ticket queue (machine channel)

Each confirmed finding becomes a ticket (`<id>-<kebab-slug>.todo.md`) dropped in
`.orchestrator/tasks/inbox/`. Routing is by **`consumer_role`**, set from the matrix status
and the surface:

| Finding shape | `consumer_role` | Drained by |
|---------------|-----------------|------------|
| Backend/API defect (5xx, bad validation, RBAC enforced server-side) | `fixer-api` | Wave-2 API fixer agents |
| Frontend defect (broken UI, optimistic-UI revert, client routing) | `fixer-web` | Wave-2 web fixer agents |
| Needs reproduction before fixing (SINGLE-source, ambiguous) | `re-verifier` | Wave-3 re-verify pass |
| Statutory/protected-core or scope decision | `escalate` | Human / orchestrator owner |

The ticket carries **pointers, not the full requirement**: `finding_ref` points at the
canonical finding in the report. Tickets are never deleted; they move by directory
(`inbox/` → `in-progress/` → `done/` or `escalated/`). DOWNGRADED items can still be filed
(low priority) so the next session does not re-chase a known non-bug.

### 2. The human-readable `bugs/NNN-slug.md` trio

Alongside the queue, emit a human-facing record per bug as three concerns so a reviewer can
reason about the batch:

| Doc | Answers |
|-----|---------|
| **AUDIT** | What is the bug, how is it reproduced, what is the evidence (POST status, reload result, screenshots), and its matrix status (VERIFIED / CORROBORATED / SINGLE / DOWNGRADED)? |
| **DUPLICATES** | Which other persona reports / prior tickets describe the same underlying defect? (Collapse the corroboration set so one bug is fixed once.) |
| **PRIORITY** | Severity after reconciliation, blast radius, and suggested wave/owner — the ordering signal for the fixers. |

### Boundaries

- QA **emits findings and files tickets**. It does **not** fix, merge, push, or open PRs —
  that is the integrator's separate run.
- The Phase-3 Opus verification is what makes the whole channel trustworthy: only VERIFIED
  and CORROBORATED findings should be filed as confident fix tickets; SINGLE findings route to
  `re-verifier`; DOWNGRADED findings are recorded with their reason.

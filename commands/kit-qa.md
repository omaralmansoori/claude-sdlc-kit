---
description: Run heavy parallel browser QA (Opus orchestrator + Sonnet tester fleet) with adversarial verification
argument-hint: [--remote] <personas>
---

Run heavy QA against the running app for these personas: `$ARGUMENTS`

Follow `${CLAUDE_PLUGIN_ROOT}/toolkit/qa/parallel-browser-qa.md`. The shape:

1. **You are the Opus orchestrator.** For each persona, write a tester brief (from
   `toolkit/qa/tester-brief.md.tmpl`) and an MCP config (from `toolkit/qa/mcp.persona.json.tmpl`).
2. **Canary one persona first**, confirm login + scoped API calls, then fan out the rest — Sonnet
   `claude -p` sessions confined to browser-only Playwright MCP tools
   (`--allowedTools "mcp__playwright" --strict-mcp-config`). Cap ~4 concurrent; run two waves.
   Testers cannot write files, so each **emits its findings as its final message**, which you capture.
3. **Phase 3 — adversarial verification (mandatory):** do NOT pass Sonnet findings through raw. Re-verify
   every Critical and every RBAC/security claim in your own authenticated session (capture POST status +
   hard-reload to prove persistence vs optimistic UI), reconcile severities across personas into a
   corroboration matrix, then write the report.
4. **File bugs back into the queue:** real defects become `.orchestrator/tasks/inbox/*.todo.md` tickets
   (routed by `consumer_role`) and/or human-readable `bugs/NNN-slug.md` tickets.

With `--remote`, drive a remote prod-shape box via `${CLAUDE_PLUGIN_ROOT}/toolkit/qa/remote-qa-launcher.sh`
(set its env vars). **Data-residency rule:** a remote box is fine for synthetic seed data only — never run
regulated/PII data outside the approved hosting boundary.

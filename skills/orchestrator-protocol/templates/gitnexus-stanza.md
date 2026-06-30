# GitNexus stanza — inject into briefs whose profile has `code_intelligence: gitnexus`

The orchestrator copies this block verbatim into the sub-agent brief under the **Pre-context** section. Keep it tight (≤ 25 lines in the brief) — the index is the place for verbosity, the brief is the place for actionable rules.

---

## Code intelligence — GitNexus (mandatory before product-symbol edits)

Before editing or commenting on any function / class / method / route:

1. `gitnexus_query({query: "<scope you care about>"})` — find the relevant execution flows ranked by relevance. **Use this instead of `grep -rn`** for symbol or concept lookups.
2. `gitnexus_impact({target: "<symbol>", direction: "upstream"})` — get the blast radius. Report direct callers, affected processes, and risk level in the commit body.
3. For HIGH or CRITICAL impact: stop, surface the risk in your report, and proceed only if the ticket explicitly accepts the risk.
4. `gitnexus_context({name: "<symbol>"})` — full callers + callees + processes view, only when impact analysis is not enough.

Before committing:

5. `gitnexus_detect_changes()` — confirms your change-set affects only the symbols you intended. If unexpected symbols show up, stop and investigate.

For renames / extract / split:

6. `gitnexus_rename` — never find-and-replace symbols. The call graph is what knows what to update.

If `gitnexus_query` warns the index is stale:

- Run `npx gitnexus analyze` once in the worktree root.
- Note the staleness in your report-back ("GitNexus index was stale at brief acknowledgement; re-analysed; proceeding").

If the project has no `.gitnexus/` index at all (some greenfield repos):

- Fall back to `grep -rn` + `Read`.
- Note "no gitnexus index — used grep fallback" in your report-back so the operator can decide whether to onboard the repo.

---

## Why this exists

The orchestrator-protocol used to tell sub-agents to "use gitnexus_impact before any product-symbol edit" inside a 50-line hard-rules wall and then trust them to remember. They did not. This stanza is short, lives near the top of the brief, and the report-back forces an acknowledgement.

If your sub-agent commits a product-symbol change without an impact entry in the commit body OR a "no gitnexus index" note in the report, the re-verifier flags it as a protocol violation.

# Anti-patterns: bad-vs-good brief fragments

The orchestrator consults this table when composing every sub-agent brief. If any fragment in the draft brief matches a ❌ row, rewrite to the ✅ shape before spawning.

Source: superpowers:dispatching-parallel-agents "Common Mistakes" + superpowers:subagent-driven-development "Red Flags". Adapted for our wave/queue context.

| ❌ Bad brief fragment | ✅ Good brief fragment |
|---|---|
| "Fix the activity status bug." | "Fix `transitionActivityStatus()` at `apps/api/src/services/activity.ts:142`. Failing test: `apps/api/src/services/activity.test.ts:88` (`should return EXEC when current=PLANNED, target=EXEC`). Test currently asserts `EXEC`; actual is `null`. Do NOT modify the state-machine config in `state-machine.ts` — only the transition function." |
| "Read `PROTOCOL.md §4` for the sub-agent contract." | [§4 inlined verbatim in the brief, ~15 lines] |
| "Explore the codebase to find where X is implemented." | "X is implemented at `apps/web/src/components/X.tsx:120-180`. Callers: `Y.tsx:45`, `Z.tsx:88` (orchestrator pre-resolved via `gitnexus_context({name: 'X'})`)." |
| "Return when done." | "Return with `Status: DONE \| DONE_WITH_CONCERNS \| BLOCKED \| NEEDS_CONTEXT`, the `Targeted-read accuracy` field, and the per-closed-ticket lines." |
| "Don't break anything." | "Forbidden paths: `packages/contracts/*` (would force a version bump out of scope). `apps/api/migrations/*` (sprint freeze)." |
| "Add appropriate error handling." | "Wrap the fetch at `client.ts:88` with a try/catch that maps `NetworkError` to a `Status: BLOCKED` report-back. Do NOT introduce a global error boundary." |
| "Similar to the previous ticket." | [Paste the actual pattern/code from the previous ticket; never reference by id.] |

## How the orchestrator uses this file

1. After composing a draft brief, scan its fragments against this table.
2. If a fragment matches ❌, rewrite to the ✅ shape and re-check.
3. If three rewrites still match an ❌, the ticket is under-specified — split it or defer until pre-resolution surfaces the missing pointers.

This file is reference-only. It does NOT get inlined into briefs. The orchestrator reads it; the sub-agent never sees it.

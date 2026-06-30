---
description: Merge feature branches via a separate, gated integration run with atomic conventional commits
argument-hint: <branches or mission>
---

Run the **integration** as a deliberate, separate pass (never inside a build/discovery run): `$ARGUMENTS`

Follow the integration discipline from the bundled `orchestrator-protocol` skill and the kit conventions:

1. **Pre-merge review gate:** run a senior (Opus) `pr-reviewer` over the candidate branches first; its
   `critical` findings must be filed as tickets and drained before any history is rewritten.
2. **Baseline + tag:** capture the gate baseline; `git tag` a checkpoint before touching anything.
3. **Merge in documented order** with `.gitattributes merge=union` pre-resolving append-only-doc conflicts.
4. **Re-emit as atomic commits:** cherry-pick by file-set onto a fresh `*-atomic` branch off the main line,
   each commit independently **green** (typecheck + lint exit 0), conventional messages with `Closes:` and
   `Risk:`.
5. **Regenerate shared artifacts ONCE:** bump the contracts package version and regenerate OpenAPI + types
   here (parallel agents never did this) — the version bump is the only cross-track coordination signal.
6. **Gate the whole thing:** typecheck + lint clean, unit tests green, browser/e2e green on the real composed
   stack, contracts build clean. Produce an INTEGRATION-REPORT (input branches, conflicts, atomic-commit plan,
   gate results, recommended merge order).

Do **not** push or open a PR — the output is a clean, reviewed branch for the operator.

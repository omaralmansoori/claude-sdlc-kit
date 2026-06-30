# TROUBLESHOOTING

First-run failures, keyed by stage. Each entry is **symptom → cause → fix**. If your problem isn't
here, check the relevant `README.md`/`PLAYBOOK.md` section before filing an issue.

---

## Stage 1 — Ingestion (`/kit-ingest`, `toolkit/ingestion/`)

### `setup.sh` exits: `'python3.13' not found`
- **Cause:** the ingestion toolchain pins **Python 3.13** (3.14 has wheel gaps for some transitive deps).
- **Fix:** install it (`brew install python@3.13`, or `pyenv install 3.13`), or point the script at an
  existing interpreter: `PY313=/path/to/python3.13 bash toolkit/ingestion/setup.sh`.

### `setup.sh` exits: `pipx not found`
- **Cause:** markitdown is installed isolated via `pipx`.
- **Fix:** `python3 -m pip install --user pipx && python3 -m pipx ensurepath`, re-open the shell, re-run `setup.sh`.

### Verify shows `markitdown: WARN (check PATH / 'pipx ensurepath')`
- **Cause:** pipx's bin dir isn't on `PATH`, so the `markitdown` shim isn't found.
- **Fix:** `pipx ensurepath` and re-open the shell. Or pass the binary explicitly:
  `ingest.py CORPUS docs/kb --markitdown-bin "$(pipx environment --value PIPX_BIN_DIR)/markitdown"`.

### `.xlsx` / `.vsdx` files silently show up as `error` rows in `INGEST-MANIFEST.tsv`
- **Cause:** you ran `ingest.py` with a **bare `python3`**. The `.xlsx`/`.vsdx` extractors import
  `openpyxl`/`vsdx`, which live ONLY in the setup-created venv at `toolkit/ingestion/.venv`.
- **Fix:** invoke the venv interpreter:
  `toolkit/ingestion/.venv/bin/python toolkit/ingestion/ingest.py CORPUS docs/kb`. (The `/kit-ingest`
  command already does this.)

### Converted markdown is bloated and grep is noisy with `data:image/...;base64,...`
- **Cause:** markitdown inlines embedded images as base64 `data:` URIs.
- **Fix:** the router strips them automatically; if you converted with raw `markitdown` instead of
  `ingest.py`, run the output through `toolkit/ingestion/strip_data_uris.py` (or just re-run via `ingest.py`).

### `gen_index.py --check` fails: `FAILED — N file(s) missing a > Source: line`
- **Cause:** the KB has docs that didn't go through `ingest.py` (hand-dropped, or a converter wrote
  raw output).
- **Fix:** re-run `ingest.py` (don't hand-author KB files). Do NOT proceed to `/kit-bootstrap` on a
  malformed KB — the `file:line` provenance chain depends on the `> Source:` line.

---

## Stage 2 — Bootstrap & plugin (`/kit-bootstrap`, `bootstrap.sh`)

### After `/plugin marketplace add …` the plugin / `/kit-*` commands don't appear
- **Cause:** the git-shorthand `add <owner>/<repo>` only resolves for a public repo; a wrong path
  fails silently.
- **Fix:** use the local-clone form: `/plugin marketplace add /absolute/path/to/claude-sdlc-kit`, then
  `/plugin install claude-sdlc-kit`. Confirm `.claude-plugin/plugin.json` and `marketplace.json` parse
  (`python3 -m json.tool .claude-plugin/plugin.json`).

### Agents behave generically — placeholders never filled
- **Cause:** `bootstrap.sh` drops `CLAUDE.md` / `AGENTS.md` / `MODULES.md` with `{{PLACEHOLDERS}}` for
  you to fill; it only auto-fills `{{KB_DIR}}` → `docs/kb`.
- **Fix:** fill the stack/DB/pkg-mgr/seam-path placeholders before any feature code. Grep for leftover
  `{{` : `grep -rn '{{' CLAUDE.md AGENTS.md MODULES.md`.

### `--preset org` copied files but agents don't read them
- **Cause:** old behaviour didn't wire the preset in. Current `bootstrap.sh` appends a
  `> **Preset applied:** org …` line to `CLAUDE.md`/`AGENTS.md`.
- **Fix:** confirm the line exists (`grep -n "Preset applied" CLAUDE.md AGENTS.md`); if you copied the
  preset manually, add it yourself (see `presets/org/README.md` Option B). The files live under
  `docs/presets/<preset>/`.

---

## Stage 3 — Orchestrate / build (`/kit-orchestrate`)

### `orchctl-init: another orchestrator session is active`
- **Cause:** a `.orchestrator/session.lock` from a previous run (or a genuinely concurrent session).
- **Fix:** if stale (> 1 h, or you know the session died): `rm .orchestrator/session.lock` and retry.
  If genuinely running: wait, or start in a separate worktree of the repo
  (`git worktree add ../<mission> <base-branch>`).

### A sub-agent fails with `worktree … already in use` or a `SingletonLock` / browser-lock error
- **Cause:** a stale agent worktree or lock left by a crashed session.
- **Fix:** `git worktree prune`, then remove the stale dir if it survives
  (`git worktree remove --force <path>` — only after confirming it's merged/clean). Never delete an
  **unmerged** worktree; surface it instead. For a browser SingletonLock during QA see Stage 4.

### Gates are red — is it my regression or a pre-existing failure?
- **Cause:** you didn't (or can't find) the Wave-0 baseline.
- **Fix:** the orchestrator records a baseline keyed by HEAD SHA + `BASELINE-NOTES` in
  `.orchestrator/state.md`. A red that's listed there is **inherited**, not your regression — say so in
  the ticket's `## Resolution`. If no baseline was captured, capture one before fixing.

### Mode confusion — should I run a discovery wave or feed the build plan straight to fixers?
- **Cause:** the two orchestrator modes (PLAYBOOK §4).
- **Fix:** if the build plan's **B-/F- tickets already populate** `.orchestrator/tasks/inbox/` →
  greenfield, **no discovery wave** (fixers drain from Wave 1). If the inbox is empty and the work is
  unknown → audit, run discovery first.

---

## Stage 4 — Heavy QA (`/kit-qa`, `toolkit/qa/`)

### `Browser is already in use` / Playwright `SingletonLock`
- **Cause:** a stale Chrome/Playwright MCP process holding the user-data-dir lock.
- **Fix:** kill the stale browser process and remove the `SingletonLock` in the MCP user-data-dir, then
  relaunch. Don't spin-wait. Cap concurrency at ~4 testers and run in two waves to avoid contention.

### A `claude -p` tester session exits non-zero immediately (auth / quota / rate-limit)
- **Cause:** usually an **expired OAuth token (401)**, sometimes a real **429** rate-limit — they look
  similar.
- **Fix:** distinguish first: a 401 means re-authenticate (`claude setup-token` / re-login); a 429
  means back off and lower `CONCURRENCY`. Canary **one** persona before fanning out, so an auth problem
  surfaces on one session, not all of them.

### The tester brief still contains a literal `{{BASE_URL}}`
- **Cause:** `{{double-brace}}` placeholders are not shell vars — `envsubst` can't resolve them.
- **Fix:** `remote-qa-launcher.sh` now `sed`-substitutes `{{BASE_URL}}` to the tunnel origin at launch.
  If you render briefs by hand, replace `{{BASE_URL}}`/`{{PERSONA}}`/`{{LOGIN}}` yourself before passing
  the brief to `claude -p`.

### Data-residency stop
- **Rule, not a bug:** `remote-qa-launcher.sh` and any out-of-boundary remote box are for **synthetic
  seed data only**. Regulated/PII data must stay inside the approved hosting boundary — never tunnel it
  to a personal machine.

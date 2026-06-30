# CONTRIBUTING

How to extend `claude-sdlc-kit`. The kit is a Claude Code plugin + methodology; most contributions are
a new command, a new ingestion extractor, a new preset, or a protocol/lesson update.

## Repo layout

| Path | What lives here |
|---|---|
| `.claude-plugin/` | `plugin.json` + `marketplace.json` — the plugin manifest. Bump `version` here on a release. |
| `commands/` | The five `/kit-*` slash commands (`*.md` with frontmatter). |
| `toolkit/ingestion/` | The corpus → KB pipeline (`setup.sh`, `ingest.py`, `gen_index.py`, `strip_data_uris.py`, `extractors/`). |
| `toolkit/conventions/` · `toolkit/contract/` · `toolkit/qa/` | Drop-in templates for a target repo. |
| `skills/` | `corpus-ingestion`, `orchestrator-protocol` (vendored engine), `data-schema`. |
| `presets/` | Optional org overlays. |
| `examples/` | One worked end-to-end slice — keep it in sync if you change template shapes. |
| `PLAYBOOK.md` · `MANIFESTO.md` · `LESSONS.md` · `deck/` | Narrative + leadership docs. |

## Add a kit command

1. Create `commands/kit-<name>.md` with frontmatter `description:` and `argument-hint:`.
   Reference plugin files via `${CLAUDE_PLUGIN_ROOT}/…`.
2. Add a row to the README **Commands** table (name / argument-hint / what / when).
3. If it drives the orchestrator engine, reconcile naming in the README "kit command ↔ skill entry
   point" table.

## Add an ingestion extractor (new source format)

1. Add `toolkit/ingestion/extractors/<fmt>_to_md.py` — a script that reads one file path (argv) and
   writes markdown to stdout (no `> Source:` line; the router prepends it). Follow the `xlsx_to_md.py`
   / `vsdx_to_md.py` shape.
2. Wire it into the router: add the extension set + a `convert_<fmt>` dispatch in
   `toolkit/ingestion/ingest.py` (`classify()` + `process()`), invoking the extractor via
   `sys.executable` so it runs under the same venv.
3. Add any new dependency to `toolkit/ingestion/requirements.txt` (it installs into the extractor venv).
4. Update `gen_index.py`'s `manifest_stub()` conversion-method table and the
   `skills/corpus-ingestion/SKILL.md` format-to-tool map.

## Add or fork a preset

Copy `presets/org/` to `presets/<name>/`, edit the policy docs, and keep it **out of core**
(`toolkit/`, `skills/`, `bootstrap.sh` must stay domain-agnostic). `bootstrap.sh --preset <name>` copies
it to `docs/presets/<name>/` and wires a reference line into the generated `CLAUDE.md`/`AGENTS.md`.

## Update the orchestrator protocol or lessons

`skills/orchestrator-protocol/PROTOCOL.md` is the contract. **No silent edits** — a protocol change
needs a matching `LESSONS.md` entry explaining the originating incident (keep the `Rule / Why / How to
apply` shape and the numeric order). New `consumer_role`s are documented in `queue/README.md` and
PROTOCOL §3. New agent archetypes get a `agent-profiles/<archetype>.yaml`.

## Versioning

The contract/plugin version is the coordination signal. On a release, bump `version` in **both**
`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` together.

## Before you open a PR

- `python3 -m json.tool .claude-plugin/plugin.json && python3 -m json.tool .claude-plugin/marketplace.json` — manifests parse.
- `python3 toolkit/ingestion/gen_index.py examples/walkthrough/01-kb --check` — the worked example still verifies.
- Keep the public kit free of project-specific residue (no real tenant IDs, hostnames, npm scopes, or
  org names — use `<placeholders>` and "the reference project").
- No emojis in shipped templates/strings; follow the kit's own conventions.

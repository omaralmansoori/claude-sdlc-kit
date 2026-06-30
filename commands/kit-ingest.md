---
description: Convert a multi-format BRD/spec corpus into an agent-searchable markdown knowledge base
argument-hint: <corpus-dir> [output-kb-dir]
---

Convert the source corpus at `$1` into an agent-searchable markdown knowledge base.
Write it to `$2` if given, otherwise to the project default **`docs/kb/`** (the location
`/kit-bootstrap` records in the generated `CLAUDE.md`). Use the claude-sdlc-kit
corpus-ingestion methodology.

Use the extractor venv's interpreter — `VENV="${CLAUDE_PLUGIN_ROOT}/toolkit/ingestion/.venv/bin/python"` —
for every script below. The `.xlsx`/`.vsdx` extractors import `openpyxl`/`vsdx`, which live ONLY in
that venv; invoking the scripts with a bare `python3` silently fails those two formats.

Do this:

1. **Set up the toolchain (once):** run `bash ${CLAUDE_PLUGIN_ROOT}/toolkit/ingestion/setup.sh`.
   It pins `markitdown` on Python 3.13 (Python 3.14 has wheel gaps) and creates the local venv for
   the custom extractors.
2. **Run the router:** `"$VENV" ${CLAUDE_PLUGIN_ROOT}/toolkit/ingestion/ingest.py --help` first to see
   the exact flags, then run `"$VENV" ${CLAUDE_PLUGIN_ROOT}/toolkit/ingestion/ingest.py "$1" "${2:-docs/kb}"`.
   It dispatches `.docx/.pptx/.pdf` to markitdown, `.xlsx` and `.vsdx` to the custom extractors,
   mirrors the folder tree, strips markitdown's base64 image blobs, and prepends a `> Source:`
   provenance line to every output file.
3. **Build the index:** run `"$VENV" ${CLAUDE_PLUGIN_ROOT}/toolkit/ingestion/gen_index.py "${2:-docs/kb}" --write-manifests`
   against the output KB to scaffold `INDEX.md` and per-area `_manifest.md` files.
4. **Review caveats:** for any OCR'd or degraded-scan source, fill the quality caveat in its area's
   `_manifest.md` — never trust degraded-OCR scoring without verifying the canonical instrument.
5. **Verify before handoff (the stage-1 → stage-2 gate):** run
   `"$VENV" ${CLAUDE_PLUGIN_ROOT}/toolkit/ingestion/gen_index.py "${2:-docs/kb}" --check`.
   It asserts every converted `.md` has a `> Source:` line (hard fail), reports files with no
   detected requirement-ID family, and flags unfilled `_manifest.md` stubs. Do NOT proceed to
   `/kit-bootstrap` until this exits clean.

Honor the KB conventions in the `corpus-ingestion` skill: preserve native requirement IDs verbatim as
grep targets, keep the `> Source:` provenance, dual-capture process flows (step text **and** the
rendered diagram), and record the Excluded / dedup-canonical rules so no one cites a stale requirement.

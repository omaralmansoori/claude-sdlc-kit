---
name: corpus-ingestion
description: Convert a multi-format BRD/FRD/spec corpus (.docx/.pptx/.pdf/.xlsx/.vsdx, often bilingual or scanned) into an agent-searchable markdown knowledge base. Use at the start of a "from BRD to tested app" build, when the requirements arrive as Office documents and you need a grep-able, provenance-tagged KB that downstream agents can cite. Also use when adding a new source document to an existing KB. Do NOT use for ordinary code or single-file conversions.
---

# corpus-ingestion

The first pillar of the kit. A build can only be as good as the requirements
agents can actually read. This skill turns a pile of binary Office documents
into a **mirrored tree of grep-able markdown** that any sub-agent can search by
native requirement ID and cite with `file:line` provenance — the substrate the
whole "BRD to tested app" methodology stands on.

The tooling lives in `../../toolkit/ingestion/`. This skill is the *method*; the
scripts are the *implementation*. Don't reimplement them inline — invoke them.

## When you (Claude) invoke this skill

You have a directory of source requirements (`.docx`, `.pptx`, `.pdf`, `.xlsx`,
`.vsdx`, maybe `.html`), and the next step in the build needs agents to read and
cite those requirements. Produce the KB first, then proceed to bootstrapping the
development contract.

## The format-to-tool map (why a router, not one tool)

No single tool reads everything. The router (`toolkit/ingestion/ingest.py`)
dispatches each file by extension:

| Source | Tool | Notes |
| --- | --- | --- |
| `.docx` `.pptx` `.pdf` `.html` | **markitdown** | Pinned `0.1.6` on Python 3.13 (3.14 has wheel gaps). Inlines images as base64 `data:` URIs — the router strips them automatically. |
| `.xlsx` `.xls` | `extractors/xlsx_to_md.py` | markitdown does not split workbooks per-sheet cleanly. One markdown table per sheet. |
| `.vsdx` | `extractors/vsdx_to_md.py` | markitdown cannot read Visio. Recovers shape text + an edge list. |
| `.md` `.txt` | passthrough | e.g. flow step text. |
| images | copied as-is | dual-capture renders kept beside their `.md`. |

## The procedure

Invoke every script with the extractor venv's interpreter
(`toolkit/ingestion/.venv/bin/python`), NOT a bare `python3`: the `.xlsx`/`.vsdx`
extractors import `openpyxl`/`vsdx`, which are installed only into that venv.
The default KB location is **`docs/kb/`** (the path `/kit-bootstrap` records in the
generated `CLAUDE.md`).

1. **Set up once.** Run `toolkit/ingestion/setup.sh`. It installs markitdown
   into an isolated pipx venv (pinned, Python 3.13) and builds a local venv for
   the `openpyxl`/`vsdx` extractors.
2. **Convert.** Run `.venv/bin/python ingest.py CORPUS docs/kb/`. It mirrors the
   corpus tree, dispatches each file, writes a `> Source:` provenance line atop
   every generated `.md`, strips base64 image blobs from markitdown output, and
   logs a one-line-per-file manifest plus an `INGEST-MANIFEST.tsv`. It is
   idempotent and incremental (`--force` to rebuild, `--dry-run` to preview).
3. **Index.** Run `.venv/bin/python gen_index.py docs/kb/ --write-manifests`. It
   scaffolds `INDEX.md` (one row per document, with detected requirement-ID
   families) and a per-area `_manifest.md` stub (conversion method + a
   quality-caveats checklist).
4. **Curate by hand** what tooling cannot decide: confirm the Excluded/dedup
   choices, and fill in each `_manifest.md` quality caveat (degraded OCR,
   bilingual/RTL).
5. **Verify (the stage-1 → stage-2 gate).** Run
   `.venv/bin/python gen_index.py docs/kb/ --check`. It hard-fails on any `.md`
   missing a `> Source:` line and warns on docs with no detected requirement-ID
   family and on `_manifest.md` stubs still unfilled. Do not move on to the
   development contract until it exits clean.

## The conventions that make a KB agent-searchable

These are non-negotiable — they are what let a later sub-agent find and cite a
requirement with no human relaying context:

- **Mirror the source tree** so a corpus path maps cleanly to a KB path.
- **Preserve native requirement IDs verbatim** (`ORG-CM-ACA-BR001`, `DC_007`,
  `FCS-CMD-PRC-1.1`) as headings and grep targets. Never rename or normalise.
- **`> Source:` line** atop every generated `.md` — the provenance anchor.
- **`INDEX.md` + per-area `_manifest.md`** — the section map and the conversion
  record with quality caveats.
- **Dual-capture process flows**: keep the ordered step text + edge list AND the
  rendered `.png`/`.pdf` (which preserves branch topology the text loses). Cite
  both.
- **Excluded / dedup**: skip stale or superseded originals (`*-OLD*`,
  `*Old.docx`); when a document appears twice, pick one canonical copy and record
  the choice. Never cite excluded or stale material.

## Caveats to flag, never to silently trust

- **OCR'd scans** mangle numbers and non-Latin scripts. Treat any OCR'd numeric
  or clinical value as "verify against the canonical source," and note it in the
  area `_manifest.md`.
- **Bilingual / RTL** content: confirm text order survived conversion before
  relying on it.

## Adding one document later

Drop it into the corpus, re-run `ingest.py` (only the new/changed file is
converted), then re-run `gen_index.py` to refresh `INDEX.md`. Update the area
`_manifest.md` if the new document carries a caveat.

## Hand-off

When the KB exists with `INDEX.md`, `_manifest.md` stubs filled, and native IDs
grep-able, ingestion is done. The build moves to the **development contract**
(acceptance-criteria ledger, modules registry, design specs, build plan) — see
`toolkit/conventions/` and `toolkit/contract/`.

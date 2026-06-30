# Ingestion pillar — corpus to agent-searchable knowledge base

A real build starts from a real BRD/FRD corpus: dozens of `.docx`, `.pptx`,
`.pdf`, `.xlsx`, and `.vsdx` files, often bilingual, sometimes degraded scans
that need OCR. Agents cannot reason over binary Office files. This pillar turns
that corpus into a **mirrored tree of grep-able markdown** that any Claude Code
agent can search by native requirement ID and cite with provenance.

```
CORPUS/ (read-only originals)        kb/ (generated, version-controlled)
  area-a/spec.docx          ──▶        area-a/spec.md      (> Source: ...)
  area-a/catalog.xlsx       ──▶        area-a/catalog.md
  area-b/flow.vsdx          ──▶        area-b/flow.md  (+ keep flow.png alongside)
  ...                                  INDEX.md            (section map)
                                       area-a/_manifest.md (method + caveats)
```

## What's here

| File | Role |
| --- | --- |
| `setup.sh` | Installs markitdown (pinned) + a local extractor venv. |
| `requirements.txt` | Extractor deps (`openpyxl`, `vsdx`). markitdown is NOT here. |
| `ingest.py` | The router: walks the corpus, dispatches by extension, mirrors the tree, writes provenance. |
| `strip_data_uris.py` | Removes markitdown's inline base64 image blobs. CLI + importable. |
| `extractors/xlsx_to_md.py` | Excel -> one markdown table per sheet (openpyxl). |
| `extractors/vsdx_to_md.py` | Visio -> shape text + edge list (vsdx package, stdlib fallback). |
| `gen_index.py` | Builds `INDEX.md` + per-area `_manifest.md` stubs. |

## Run it end to end

```bash
# 0. one-time setup (pins markitdown, builds .venv for the extractors)
bash toolkit/ingestion/setup.sh

# 1. convert the corpus -> kb/ (use the extractor venv's python so the
#    xlsx/vsdx extractor subprocesses can import openpyxl/vsdx)
toolkit/ingestion/.venv/bin/python toolkit/ingestion/ingest.py ./CORPUS ./kb

# 2. build the navigation index + manifest stubs
toolkit/ingestion/.venv/bin/python toolkit/ingestion/gen_index.py ./kb --write-manifests

# 3. read kb/INDEX.md; fill in each _manifest.md "quality caveats" section
```

Both `ingest.py` and `gen_index.py` are idempotent. `ingest.py` is also
incremental: it re-converts a file only when the source is newer than the
output (force a full rebuild with `--force`). Preview without writing using
`--dry-run`.

`ingest.py` writes a one-line-per-file manifest to stdout and an
`INGEST-MANIFEST.tsv` at the KB root (status, handler, source, output, notes).

## markitdown: the pin and the quirk

| Concern | Detail |
| --- | --- |
| **Version** | `markitdown[docx,pptx,pdf,xlsx,xls]==0.1.6`, verified working. |
| **Interpreter pin** | Install on **Python 3.13**. Python 3.14 has wheel gaps for some transitive deps — pin the interpreter, not just the package. `setup.sh` does this via pipx. |
| **Isolation** | markitdown lives in its own pipx venv; the router shells out to the `markitdown` CLI, so it stays out of the extractor venv and out of conflicts. |
| **The base64 quirk** | markitdown inlines embedded images as base64 `data:` URIs, e.g. `![logo](data:image/png;base64,iVBOR...)`. These bloat the KB and defeat grep. `ingest.py` runs `strip_data_uris` on markitdown output automatically, replacing each blob with `[image]`. |

markitdown does **not** read `.vsdx` (Visio) and does not split `.xlsx`
per-sheet cleanly — which is why this pillar ships its own extractors for those
two formats.

## KB conventions (what makes it agent-searchable)

These conventions are the contract. Keep them, and any agent can find and cite
a requirement without you in the loop.

| Convention | Rule |
| --- | --- |
| **Mirror the tree** | The KB folder structure mirrors the corpus exactly, so a path in one maps to a path in the other. |
| **Preserve native IDs verbatim** | Requirement IDs (e.g. `ORG-CM-ACA-BR001`, `DC_007`, `FCS-CMD-PRC-1.1`) are kept exactly as written, so `rg -n "ORG-CM-ACA-BR001" kb/` is a precise grep target. Never rename or normalise them. |
| **`> Source:` provenance** | Every generated `.md` opens with `> Source: <relative original path>` so every citation traces back to a real document. `ingest.py` writes this line for you. |
| **`INDEX.md` + `_manifest.md`** | A master `INDEX.md` maps sections and which ID families live where; each area has a `_manifest.md` recording the conversion method and quality caveats (degraded OCR, bilingual/RTL). `gen_index.py` scaffolds both. |
| **Dual-capture flows** | A process flow is captured twice: the ordered **step text + edge list** (for logic you build from) *and* the rendered **`.png`/`.pdf`** (which preserves branch/merge topology the text loses). Keep both side by side; cite both. The vsdx extractor reminds you of this in its output. |
| **Excluded / dedup** | Stale or superseded originals (`*-OLD*`, `*Old.docx`) are excluded from conversion (default `--exclude` patterns). When a document appears more than once, pick one canonical copy and note the choice in the area `_manifest.md`. Never cite excluded or stale material. |

## OCR and bilingual caveats

Some sources are scans that were OCR'd; OCR mangles numbers and non-Latin
scripts. Treat any OCR'd numeric or clinical value as **"verify against the
canonical source,"** not as ground truth, and record that caveat in the area
`_manifest.md`. For bilingual content (e.g. Arabic / RTL), confirm text order
survived the conversion before relying on it.

## Why an agent-searchable KB at all

The whole development methodology downstream of this pillar is **inline-by-
default agent briefs**: a sub-agent is handed a requirement and expected to
implement it without a human relaying context. That only works if the
requirement is (a) findable by a stable, grep-able native ID and (b) traceable
to its source via a `> Source:` line. Grep-able IDs + provenance are what let an
agent locate exactly the governing requirement, quote it, and cite `file:line`
in its code, commit, and PR — turning a pile of Office documents into a
substrate agents can build against autonomously.

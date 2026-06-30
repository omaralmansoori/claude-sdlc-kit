#!/usr/bin/env python3
"""Ingestion router: a multi-format BRD/spec corpus -> an agent-searchable KB.

Walks an input corpus directory, mirrors its folder tree into an output
knowledge-base directory, and dispatches each file to the right converter by
extension:

    .docx .pptx .pdf .html .htm   ->  markitdown  (subprocess)
    .xlsx .xls                    ->  extractors/xlsx_to_md.py
    .vsdx                         ->  extractors/vsdx_to_md.py
    .md  .txt                     ->  passthrough text (e.g. flow step text)
    .png .jpg .jpeg .gif .svg ...  ->  copied as-is (dual-capture renders)
    (anything else)               ->  skipped

Every generated markdown file opens with a provenance line:

    > Source: <relative path of the original>

markitdown output is run through the base64 ``data:`` strip before writing.

The router is deliberately dependency-light: markitdown and the heavy
extractors are invoked as subprocesses, so a missing extractor dependency
fails one file, not the whole run. It is idempotent / incremental: a file is
re-converted only when the source is newer than the output (override with
``--force``).

    ingest.py CORPUS_DIR KB_DIR [options]
"""
from __future__ import annotations

import argparse
import fnmatch
import shutil
import subprocess
import sys
from pathlib import Path

# Make sibling modules importable when run as a script.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from strip_data_uris import strip_data_uris  # noqa: E402

HERE = Path(__file__).resolve().parent
EXTRACTORS = HERE / "extractors"

MARKITDOWN_EXTS = {".docx", ".pptx", ".pdf", ".html", ".htm"}
XLSX_EXTS = {".xlsx", ".xls"}
VSDX_EXTS = {".vsdx"}
TEXT_EXTS = {".md", ".txt"}
ASSET_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".bmp", ".tiff"}

DEFAULT_EXCLUDES = ["*-OLD*", "*Old.docx", "~$*", ".DS_Store"]

SOURCE_PREFIX = "> Source: "


# ---------------------------------------------------------------------------
# Converters (each returns a markdown body WITHOUT the Source line)
# ---------------------------------------------------------------------------


def _run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"{cmd[0]} failed (exit {proc.returncode}): {err}")
    return proc.stdout.decode("utf-8", errors="replace")


def convert_markitdown(src: Path, markitdown_bin: str) -> str:
    try:
        body = _run([markitdown_bin, str(src)])
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"'{markitdown_bin}' not found on PATH. Run setup.sh, or pass "
            f"--markitdown-bin. See README.md."
        ) from exc
    cleaned, _n = strip_data_uris(body)
    return cleaned


def convert_xlsx(src: Path) -> str:
    return _run([sys.executable, str(EXTRACTORS / "xlsx_to_md.py"), str(src)])


def convert_vsdx(src: Path) -> str:
    return _run([sys.executable, str(EXTRACTORS / "vsdx_to_md.py"), str(src)])


def convert_text(src: Path) -> str:
    return src.read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------


def classify(src: Path) -> str:
    ext = src.suffix.lower()
    if ext in MARKITDOWN_EXTS:
        return "markitdown"
    if ext in XLSX_EXTS:
        return "xlsx"
    if ext in VSDX_EXTS:
        return "vsdx"
    if ext in TEXT_EXTS:
        return "text"
    if ext in ASSET_EXTS:
        return "asset"
    return "skip"


def is_excluded(src: Path, patterns: list[str]) -> bool:
    name = src.name
    return any(fnmatch.fnmatch(name, pat) for pat in patterns)


def out_path_for(src: Path, in_root: Path, out_root: Path, handler: str) -> Path:
    rel = src.relative_to(in_root)
    if handler == "asset":
        return out_root / rel
    return out_root / rel.parent / (rel.stem + ".md")


def newer_than(src: Path, dst: Path) -> bool:
    """True if src is newer than dst (or dst is missing)."""
    if not dst.exists():
        return True
    return src.stat().st_mtime > dst.stat().st_mtime


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def process(args: argparse.Namespace) -> int:
    in_root: Path = args.input.resolve()
    out_root: Path = args.output.resolve()
    if not in_root.is_dir():
        print(f"error: input is not a directory: {in_root}", file=sys.stderr)
        return 2

    excludes = list(DEFAULT_EXCLUDES)
    excludes.extend(args.exclude or [])

    out_root.mkdir(parents=True, exist_ok=True)
    manifest_path = out_root / "INGEST-MANIFEST.tsv"
    manifest_rows: list[str] = ["status\thandler\tsource\toutput\tnotes"]

    counts = {"ok": 0, "skip-excluded": 0, "skip-unchanged": 0,
              "skip-type": 0, "error": 0}

    for src in sorted(p for p in in_root.rglob("*") if p.is_file()):
        if src.resolve() == manifest_path:
            continue
        rel = src.relative_to(in_root).as_posix()
        handler = classify(src)

        if is_excluded(src, excludes):
            counts["skip-excluded"] += 1
            print(f"SKIP   excluded   {rel}")
            manifest_rows.append(f"skip-excluded\t{handler}\t{rel}\t\texcluded by pattern")
            continue

        if handler == "skip":
            counts["skip-type"] += 1
            print(f"SKIP   type       {rel}")
            manifest_rows.append(f"skip-type\t-\t{rel}\t\tunhandled extension")
            continue

        dst = out_path_for(src, in_root, out_root, handler)
        rel_out = dst.relative_to(out_root).as_posix()

        if not args.force and not newer_than(src, dst):
            counts["skip-unchanged"] += 1
            print(f"SKIP   unchanged  {rel}")
            manifest_rows.append(f"skip-unchanged\t{handler}\t{rel}\t{rel_out}\tup to date")
            continue

        if args.dry_run:
            print(f"PLAN   {handler:<10} {rel}  ->  {rel_out}")
            manifest_rows.append(f"plan\t{handler}\t{rel}\t{rel_out}\t")
            continue

        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            if handler == "asset":
                shutil.copy2(src, dst)
                counts["ok"] += 1
                print(f"COPY   {handler:<10} {rel}  ->  {rel_out}")
                manifest_rows.append(f"ok\t{handler}\t{rel}\t{rel_out}\tcopied")
                continue

            if handler == "markitdown":
                body = convert_markitdown(src, args.markitdown_bin)
            elif handler == "xlsx":
                body = convert_xlsx(src)
            elif handler == "vsdx":
                body = convert_vsdx(src)
            else:  # text
                body = convert_text(src)

            content = f"{SOURCE_PREFIX}{rel}\n\n" + body.rstrip() + "\n"
            dst.write_text(content, encoding="utf-8")
            counts["ok"] += 1
            print(f"OK     {handler:<10} {rel}  ->  {rel_out}")
            manifest_rows.append(f"ok\t{handler}\t{rel}\t{rel_out}\t")
        except Exception as exc:  # noqa: BLE001 — one bad file must not abort the run
            counts["error"] += 1
            msg = str(exc).replace("\t", " ").replace("\n", " ")
            print(f"ERROR  {handler:<10} {rel}: {msg}", file=sys.stderr)
            manifest_rows.append(f"error\t{handler}\t{rel}\t{rel_out}\t{msg}")

    if not args.dry_run:
        manifest_path.write_text("\n".join(manifest_rows) + "\n", encoding="utf-8")

    summary = "  ".join(f"{k}={v}" for k, v in counts.items())
    print(f"\nsummary: {summary}", file=sys.stderr)
    if not args.dry_run:
        print(f"manifest: {manifest_path}", file=sys.stderr)
        print("next: run gen_index.py to build INDEX.md + _manifest stubs.",
              file=sys.stderr)
    return 1 if counts["error"] else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="ingest.py",
        description="Convert a multi-format BRD/spec corpus into an agent-searchable markdown KB.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  ingest.py ./BRD-SST ./kb\n"
            "  ingest.py ./BRD-SST ./kb --dry-run\n"
            "  ingest.py ./BRD-SST ./kb --exclude '*-DRAFT*' --force\n"
        ),
    )
    parser.add_argument("input", type=Path, help="Input corpus directory (read-only).")
    parser.add_argument("output", type=Path, help="Output knowledge-base directory.")
    parser.add_argument(
        "--exclude",
        action="append",
        metavar="GLOB",
        help=(
            "Filename glob to exclude (repeatable). Added on top of defaults: "
            + ", ".join(DEFAULT_EXCLUDES)
        ),
    )
    parser.add_argument(
        "--markitdown-bin",
        default="markitdown",
        help="markitdown executable (default: markitdown on PATH).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-convert even when the output is newer than the source.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the plan without writing anything.",
    )
    args = parser.parse_args(argv)
    return process(args)


if __name__ == "__main__":
    raise SystemExit(main())

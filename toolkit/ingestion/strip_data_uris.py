#!/usr/bin/env python3
"""Strip inline base64 ``data:`` image blobs from markdown.

markitdown inlines embedded images as base64 ``data:`` URIs, e.g.

    ![logo](data:image/png;base64,iVBORw0KGgoAAAA...thousands-of-chars...)

These blobs bloat the knowledge base, defeat grep, and carry no requirement
text. This module replaces each with a terse ``[image]`` placeholder.

Usable two ways:

  * As a function   ->  ``from strip_data_uris import strip_data_uris``
  * As a CLI        ->  ``strip_data_uris.py FILE...  [--in-place]``
                        ``cat doc.md | strip_data_uris.py`` (stdin -> stdout)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PLACEHOLDER = "[image]"

# 1) Markdown image embeds: ![alt](data:...) — base64 never contains ')'.
_MD_IMAGE_DATA_URI = re.compile(
    r"!\[[^\]]*\]\(\s*data:[^)]*\)",
    re.IGNORECASE,
)

# 2) HTML <img src="data:..."> (and single-quoted variants).
_HTML_IMG_DATA_URI = re.compile(
    r"""<img\b[^>]*\bsrc\s*=\s*["']data:[^"']*["'][^>]*>""",
    re.IGNORECASE,
)

# 3) Reference-style link definitions whose target is a data: URI.
#    [ref]: data:image/png;base64,....
_REF_DEF_DATA_URI = re.compile(
    r"^[ \t]*\[[^\]]+\]:[ \t]*data:\S+[ \t]*$",
    re.IGNORECASE | re.MULTILINE,
)


def strip_data_uris(text: str) -> tuple[str, int]:
    """Return ``(cleaned_text, num_blobs_removed)``.

    Pure function, no I/O. Idempotent: running it twice removes nothing the
    second time.
    """
    count = 0

    def _sub_placeholder(_match: "re.Match[str]") -> str:
        nonlocal count
        count += 1
        return PLACEHOLDER

    text = _MD_IMAGE_DATA_URI.sub(_sub_placeholder, text)
    text = _HTML_IMG_DATA_URI.sub(_sub_placeholder, text)
    # Reference definitions are removed outright (drop the whole line).
    text, n_refs = _REF_DEF_DATA_URI.subn("", text)
    count += n_refs
    return text, count


def _process_file(path: Path, in_place: bool) -> int:
    raw = path.read_text(encoding="utf-8", errors="replace")
    cleaned, n = strip_data_uris(raw)
    if in_place:
        if n:
            path.write_text(cleaned, encoding="utf-8")
        print(f"{path}: removed {n} data-URI blob(s)", file=sys.stderr)
    else:
        sys.stdout.write(cleaned)
    return n


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="strip_data_uris.py",
        description="Replace inline base64 data: image blobs with a [image] placeholder.",
    )
    parser.add_argument(
        "files",
        nargs="*",
        type=Path,
        help="Markdown files to clean. Omit to read stdin and write stdout.",
    )
    parser.add_argument(
        "-i",
        "--in-place",
        action="store_true",
        help="Rewrite each file in place (default: write to stdout).",
    )
    args = parser.parse_args(argv)

    if not args.files:
        raw = sys.stdin.read()
        cleaned, n = strip_data_uris(raw)
        sys.stdout.write(cleaned)
        print(f"stdin: removed {n} data-URI blob(s)", file=sys.stderr)
        return 0

    total = 0
    for path in args.files:
        if not path.is_file():
            print(f"skip (not a file): {path}", file=sys.stderr)
            continue
        total += _process_file(path, args.in_place)
    if args.in_place:
        print(f"done: removed {total} data-URI blob(s) across {len(args.files)} file(s)",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

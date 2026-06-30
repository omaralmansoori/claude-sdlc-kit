#!/usr/bin/env python3
"""Convert a Visio diagram (.vsdx) to markdown — shape text + an edge list.

markitdown cannot read .vsdx. Process flows in spec corpora are often Visio,
and a flow carries two kinds of information the knowledge base must keep:

  * the *step text* (what each box says), and
  * the *topology* (which step leads to which — branches, loops).

DUAL-CAPTURE NOTE: a flat extractor like this one recovers the step text and a
best-effort edge list, but a complex flow's true branch/merge topology is
easiest to read from the rendered picture. Always keep a rendered ``.png`` /
``.pdf`` of the diagram *alongside* this markdown in the knowledge base, and
cite both. This file is the grep-able half of the pair, not a replacement for
the render.

Two strategies, tried in order:
  1. the ``vsdx`` PyPI package, if importable (richer shape/connector model);
  2. a stdlib fallback (``zipfile`` + ``xml.etree``) that reads
     ``visio/pages/*.xml`` directly — no third-party dependency at all.

Output goes to stdout by default (the ingest router captures it and prepends
the ``> Source:`` line), or to a file with ``-o``.
"""
from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# ---------------------------------------------------------------------------
# Shared markdown rendering
# ---------------------------------------------------------------------------


def _render_markdown(title: str, pages: list[dict]) -> str:
    """``pages`` is a list of {name, steps: [str], edges: [(from, to)]}."""
    out: list[str] = [f"# {title}\n"]
    if not pages:
        out.append("_(no pages found)_\n")
        return "\n".join(out)

    for page in pages:
        out.append(f"## {page['name']}\n")

        steps = [s for s in page["steps"] if s.strip()]
        if steps:
            out.append("### Steps (document order)\n")
            for i, step in enumerate(steps, 1):
                out.append(f"{i}. {step}")
            out.append("")
        else:
            out.append("_(no shape text on this page)_\n")

        edges = page["edges"]
        if edges:
            out.append("### Edges\n")
            for src, dst in edges:
                out.append(f"- {src or '?'} -> {dst or '?'}")
            out.append("")
    return "\n".join(out).rstrip() + "\n"


# ---------------------------------------------------------------------------
# Strategy 1: the vsdx PyPI package
# ---------------------------------------------------------------------------


def _extract_with_package(path: Path) -> list[dict]:
    """Use the ``vsdx`` package. Raises ImportError if it is not installed."""
    from vsdx import VisioFile  # noqa: PLC0415 — lazy/optional import

    pages: list[dict] = []
    with VisioFile(str(path)) as visio:
        for page in visio.pages:
            steps: list[str] = []

            def _walk(shape) -> None:
                text = (getattr(shape, "text", "") or "").strip()
                if text:
                    steps.append(text)
                for child in getattr(shape, "child_shapes", []) or []:
                    _walk(child)

            for shape in getattr(page, "child_shapes", []) or []:
                _walk(shape)

            edges: list[tuple[str, str]] = []
            id_to_text: dict[str, str] = {}
            for shape in page.all_shapes if hasattr(page, "all_shapes") else []:
                sid = getattr(shape, "ID", None) or getattr(shape, "id", None)
                if sid is not None:
                    id_to_text[str(sid)] = (getattr(shape, "text", "") or "").strip()
            for conn in getattr(page, "connects", []) or []:
                frm = id_to_text.get(str(getattr(conn, "from_id", "")), "")
                to = id_to_text.get(str(getattr(conn, "to_id", "")), "")
                if frm or to:
                    edges.append((frm, to))

            pages.append(
                {"name": getattr(page, "name", f"Page {len(pages) + 1}"),
                 "steps": steps, "edges": edges}
            )
    return pages


# ---------------------------------------------------------------------------
# Strategy 2: stdlib zipfile + xml.etree (no third-party dependency)
# ---------------------------------------------------------------------------


def _local(tag: str) -> str:
    """Strip an XML namespace: '{ns}Shape' -> 'Shape'."""
    return tag.rsplit("}", 1)[-1]


def _attr(elem: ET.Element, name: str) -> str | None:
    """Get an attribute by local name, ignoring namespace prefixes."""
    val = elem.get(name)
    if val is not None:
        return val
    for key, value in elem.attrib.items():
        if _local(key) == name:
            return value
    return None


def _page_names(zf: zipfile.ZipFile) -> dict[str, str]:
    """Best-effort map of 'visio/pages/pageN.xml' -> human page name."""
    names: dict[str, str] = {}
    try:
        rels_xml = zf.read("visio/pages/_rels/pages.xml.rels")
        rels_root = ET.fromstring(rels_xml)
        rid_to_target: dict[str, str] = {}
        for rel in rels_root:
            rid = _attr(rel, "Id")
            target = _attr(rel, "Target")
            if rid and target:
                rid_to_target[rid] = "visio/pages/" + target.split("/")[-1]

        pages_xml = zf.read("visio/pages/pages.xml")
        pages_root = ET.fromstring(pages_xml)
        for page in pages_root:
            if _local(page.tag) != "Page":
                continue
            name = _attr(page, "Name") or _attr(page, "NameU")
            rid = None
            for child in page:
                if _local(child.tag) == "Rel":
                    rid = _attr(child, "id")
                    break
            if name and rid and rid in rid_to_target:
                names[rid_to_target[rid]] = name
    except (KeyError, ET.ParseError):
        pass
    return names


def _parse_page(xml_bytes: bytes) -> tuple[list[str], dict[str, str], list[tuple[str, str]]]:
    """Return (ordered_step_texts, id->text, edges) for one page XML."""
    root = ET.fromstring(xml_bytes)
    id_to_text: dict[str, str] = {}
    ordered: list[str] = []

    # Shapes (may be nested under <Shapes>).
    for shape in root.iter():
        if _local(shape.tag) != "Shape":
            continue
        sid = _attr(shape, "ID")
        text_parts: list[str] = []
        for child in shape:
            if _local(child.tag) == "Text":
                text_parts.append("".join(child.itertext()))
        text = " ".join(t.strip() for t in text_parts if t.strip()).strip()
        if sid is not None:
            id_to_text[sid] = text
        if text:
            ordered.append(text)

    # Connects: each <Connect> links a connector shape (FromSheet) to a node
    # (ToSheet) at its begin or end (FromCell = BeginX/EndX). Group by
    # connector to recover from->to edges.
    begin: dict[str, str] = {}
    end: dict[str, str] = {}
    for connect in root.iter():
        if _local(connect.tag) != "Connect":
            continue
        connector = _attr(connect, "FromSheet")
        node = _attr(connect, "ToSheet")
        cell = (_attr(connect, "FromCell") or "")
        if connector is None or node is None:
            continue
        if cell.lower().startswith("begin"):
            begin[connector] = node
        elif cell.lower().startswith("end"):
            end[connector] = node

    edges: list[tuple[str, str]] = []
    for connector in set(begin) | set(end):
        src_id = begin.get(connector)
        dst_id = end.get(connector)
        src = id_to_text.get(src_id, src_id or "") if src_id else ""
        dst = id_to_text.get(dst_id, dst_id or "") if dst_id else ""
        if src or dst:
            edges.append((src, dst))

    return ordered, id_to_text, edges


def _extract_with_zipfile(path: Path) -> list[dict]:
    pages: list[dict] = []
    with zipfile.ZipFile(str(path)) as zf:
        names = _page_names(zf)
        page_files = sorted(
            n
            for n in zf.namelist()
            if n.startswith("visio/pages/")
            and n.endswith(".xml")
            and "/_rels/" not in n
            and not n.endswith("pages.xml")
        )
        for idx, page_file in enumerate(page_files, 1):
            steps, _id_map, edges = _parse_page(zf.read(page_file))
            pages.append(
                {
                    "name": names.get(page_file, f"Page {idx}"),
                    "steps": steps,
                    "edges": edges,
                }
            )
    return pages


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def vsdx_to_markdown(path: Path) -> str:
    """Convert a .vsdx to markdown, preferring the vsdx package, else stdlib."""
    try:
        pages = _extract_with_package(path)
        method = "vsdx package"
    except ImportError:
        pages = _extract_with_zipfile(path)
        method = "stdlib zipfile/xml fallback"
    except Exception as exc:  # noqa: BLE001 — package parse failure -> fall back
        print(f"note: vsdx package failed ({exc!r}); using stdlib fallback",
              file=sys.stderr)
        pages = _extract_with_zipfile(path)
        method = "stdlib zipfile/xml fallback"

    print(f"note: extracted {path.name} via {method}", file=sys.stderr)
    body = _render_markdown(path.stem, pages)
    note = ("\n> Extracted from Visio; topology is best-effort. Keep the rendered "
            "diagram (.png/.pdf) alongside this file and cite both.\n")
    return body.rstrip() + "\n" + note


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="vsdx_to_md.py",
        description="Convert a Visio .vsdx diagram to markdown (shape text + edge list).",
    )
    parser.add_argument("input", type=Path, help="Path to the .vsdx file.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Write markdown here (default: stdout).",
    )
    args = parser.parse_args(argv)

    if not args.input.is_file():
        print(f"error: not a file: {args.input}", file=sys.stderr)
        return 2

    markdown = vsdx_to_markdown(args.input)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(markdown, encoding="utf-8")
    else:
        sys.stdout.write(markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

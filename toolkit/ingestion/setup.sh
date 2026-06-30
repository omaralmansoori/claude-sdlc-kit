#!/usr/bin/env bash
# Set up the ingestion pillar: markitdown (pinned, via pipx on Python 3.13)
# plus a local venv for the openpyxl/vsdx extractors.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- pins ------------------------------------------------------------------
# markitdown 0.1.6 is verified against Python 3.13. Python 3.14 has wheel gaps
# for some transitive deps, so we pin the interpreter, not just the package.
PY313="${PY313:-python3.13}"
MARKITDOWN_SPEC="markitdown[docx,pptx,pdf,xlsx,xls]==0.1.6"

echo "==> ingestion pillar setup"

# --- 1. interpreter check --------------------------------------------------
if ! command -v "$PY313" >/dev/null 2>&1; then
  echo "ERROR: '$PY313' not found." >&2
  echo "       Install Python 3.13 (e.g. 'brew install python@3.13' or pyenv)." >&2
  echo "       Override the interpreter with PY313=/path/to/python3.13 $0" >&2
  exit 1
fi
echo "    using interpreter: $("$PY313" --version 2>&1) ($(command -v "$PY313"))"

# --- 2. markitdown via pipx (isolated) -------------------------------------
if ! command -v pipx >/dev/null 2>&1; then
  echo "ERROR: pipx not found. Install it: 'python3 -m pip install --user pipx'" >&2
  echo "       then 'python3 -m pipx ensurepath' and re-open your shell." >&2
  exit 1
fi

echo "==> installing markitdown (pinned) into an isolated pipx venv"
if pipx list 2>/dev/null | grep -qi "markitdown"; then
  echo "    markitdown already present; reinstalling to enforce the pin"
  pipx install --python "$PY313" --force "$MARKITDOWN_SPEC"
else
  pipx install --python "$PY313" "$MARKITDOWN_SPEC"
fi

# --- 3. local venv for the extractors --------------------------------------
VENV="$HERE/.venv"
echo "==> creating extractor venv at $VENV"
"$PY313" -m venv "$VENV"
# shellcheck disable=SC1091
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet -r "$HERE/requirements.txt"
echo "    installed: $("$VENV/bin/python" -m pip list 2>/dev/null | grep -iE 'openpyxl|vsdx' | tr '\n' ' ')"

# --- 4. verify -------------------------------------------------------------
echo "==> verifying"
markitdown --help >/dev/null 2>&1 && echo "    markitdown: OK" || echo "    markitdown: WARN (check PATH / 'pipx ensurepath')"
"$VENV/bin/python" -c "import openpyxl, vsdx" 2>/dev/null && echo "    extractors: OK" || echo "    extractors: WARN"

cat <<EOF

==> done. next steps:

  1. Convert a corpus into a knowledge base (use the extractor venv's python so
     openpyxl/vsdx are importable by the extractor subprocesses):

       "$VENV/bin/python" "$HERE/ingest.py" /path/to/CORPUS /path/to/kb

  2. Build the navigation index + per-area manifest stubs:

       "$VENV/bin/python" "$HERE/gen_index.py" /path/to/kb --write-manifests

  3. Review /path/to/kb/INDEX.md and fill in each _manifest.md quality caveat.

See README.md for the KB conventions (native-ID preservation, > Source: lines,
dual-capture flows, Excluded/dedup rules).
EOF

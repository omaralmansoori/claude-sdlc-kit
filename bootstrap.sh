#!/usr/bin/env bash
#
# bootstrap.sh — scaffold a TARGET repo for the claude-sdlc-kit development-contract method.
#
# Creates the orchestrator queue, docs scaffolding, conflict-free append seams (.gitattributes
# merge=union), gitignore entries, and drops the conventions templates into place. Idempotent:
# re-running never clobbers files you've started editing.
#
# Usage:
#   bootstrap.sh [TARGET_DIR] [--preset org]
#
#   TARGET_DIR    repo to scaffold (default: current directory)
#   --preset org  also copy presets/org/ into TARGET/docs/presets/org/ as references
#
set -euo pipefail

# --- resolve paths ----------------------------------------------------------
# KIT_ROOT = directory containing this script (works when run from anywhere, incl. as a plugin).
SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SRC" ]; do
  DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [[ "$SCRIPT_SRC" != /* ]] && SCRIPT_SRC="$DIR/$SCRIPT_SRC"
done
KIT_ROOT="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"

TARGET="."
PRESET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --preset) PRESET="${2:-}"; shift 2 ;;
    --preset=*) PRESET="${1#*=}"; shift ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    -*) echo "bootstrap: unknown flag: $1" >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

TARGET="$(cd "$TARGET" 2>/dev/null && pwd || { echo "bootstrap: TARGET_DIR not found: $TARGET" >&2; exit 1; })"
CONV="$KIT_ROOT/toolkit/conventions"

# --- helpers ----------------------------------------------------------------
log()  { printf '  %s\n' "$*"; }
skip() { printf '  - skip (exists): %s\n' "$*"; }
made() { printf '  + %s\n' "$*"; }

ensure_dir() { [ -d "$1" ] || { mkdir -p "$1"; made "${1#$TARGET/}/"; }; }

# write_if_absent <path> <<'EOF' ... EOF  — never clobbers an existing file
write_if_absent() {
  local path="$1"
  if [ -e "$path" ]; then skip "${path#$TARGET/}"; cat >/dev/null; return 0; fi
  cat > "$path"
  made "${path#$TARGET/}"
}

# copy_tmpl <src.tmpl> <dest>  — strips .tmpl, prepends a "fill placeholders" banner, idempotent
copy_tmpl() {
  local src="$1" dest="$2"
  if [ ! -f "$src" ]; then log "WARN: template missing: $src"; return 0; fi
  if [ -e "$dest" ]; then skip "${dest#$TARGET/}"; return 0; fi
  {
    printf '<!-- Scaffolded by claude-sdlc-kit bootstrap.sh. Fill every {{PLACEHOLDER}} before shipping feature code. -->\n\n'
    cat "$src"
  } > "$dest"
  made "${dest#$TARGET/}"
}

# append_line <file> <line>  — appends only if the exact line is not already present
append_line() {
  local file="$1" line="$2"
  [ -f "$file" ] || : > "$file"
  if grep -qxF "$line" "$file" 2>/dev/null; then return 0; fi
  printf '%s\n' "$line" >> "$file"
}

printf '\nclaude-sdlc-kit bootstrap\n  kit:    %s\n  target: %s\n\n' "$KIT_ROOT" "$TARGET"

# --- 1. orchestrator queue + docs scaffolding -------------------------------
printf 'Scaffolding directories...\n'
ensure_dir "$TARGET/.orchestrator/tasks/inbox"
ensure_dir "$TARGET/.orchestrator/tasks/in-progress"
ensure_dir "$TARGET/.orchestrator/tasks/done"
ensure_dir "$TARGET/.orchestrator/tasks/escalated"
ensure_dir "$TARGET/.orchestrator/missions"
ensure_dir "$TARGET/docs/adr"
[ -f "$TARGET/docs/adr/.gitkeep" ] || : > "$TARGET/docs/adr/.gitkeep"
# KB location — the stage-1 (/kit-ingest) -> stage-2 (/kit-bootstrap) handoff convention.
ensure_dir "$TARGET/docs/kb"
write_if_absent "$TARGET/docs/kb/README.md" <<'EOF'
# Knowledge base (KB)

> The agent-searchable, provenance-tagged corpus is the single source of truth for requirements.
> Generate it here with `/kit-ingest <corpus-dir> docs/kb` (or
> `toolkit/ingestion/ingest.py <corpus-dir> docs/kb`), then `gen_index.py docs/kb --write-manifests`
> and `gen_index.py docs/kb --check`. Every converted doc carries a `> Source:` line; native
> requirement IDs are preserved verbatim as grep targets. Cite the KB by `file:line` — never
> re-parse the original corpus. This path is wired into `CLAUDE.md` (`{{KB_DIR}}` → `docs/kb`).
EOF

printf '\nScaffolding files...\n'
write_if_absent "$TARGET/.orchestrator/state.md" <<'EOF'
# Orchestrator state

> Live snapshot of the current run. The orchestrator updates this; sub-agents read it.

- Session short id: (set per run, e.g. sA7B9)
- Current wave: 0 (baseline + plan)
- Baseline SHA: (HEAD at start of run)

## Active branches

| Branch | Ticket | Agent | Status |
|--------|--------|-------|--------|

## Baseline notes

(Pre-existing failures captured at baseline so regressions are distinguishable. Keyed by HEAD SHA.)
EOF

write_if_absent "$TARGET/docs/open-questions.md" <<'EOF'
# Open questions

> When the corpus is silent or ambiguous, log it here with the **conservative default** you chose
> and tested against. Never guess statutory/financial/rights-bearing behaviour silently.

| # | Question | Requirement gap (file:line) | Conservative default chosen | Status |
|---|----------|-----------------------------|-----------------------------|--------|
| 1 |          |                             |                             | open   |
EOF

write_if_absent "$TARGET/docs/orchestrator-log.md" <<'EOF'
# Orchestrator log

> Append-only decision/run log. One entry per wave boundary, integration, checkpoint, or rollback.

| When (ISO) | Event | Detail | SHA / tag |
|------------|-------|--------|-----------|
EOF

# --- 2. .gitattributes — conflict-free append seams (merge=union) ------------
printf '\nConfiguring conflict-free append seams (.gitattributes merge=union)...\n'
GA="$TARGET/.gitattributes"
if ! grep -q 'claude-sdlc-kit: append-only seams' "$GA" 2>/dev/null; then
  cat >> "$GA" <<'EOF'

# --- claude-sdlc-kit: append-only seams (merge=union keeps concurrent appends) ---
MODULES.md                 merge=union
docs/open-questions.md     merge=union
docs/orchestrator-log.md   merge=union
.orchestrator/**/*.md      merge=union
# Tune these to YOUR project's real seam paths (see CLAUDE.md "four append-only seams"):
#   <schema-dir>/*.<ext>     merge=union   # per-module schema files (NOT the _base file)
#   <api-registry-file>      merge=union   # one router registration line per module
#   <nav-registry-file>      merge=union   # one nav entry per module
#   <contracts>/src/index.ts merge=union   # one `export *` line per module
EOF
  made ".gitattributes (append-only seams block)"
else
  skip ".gitattributes (already has seams block)"
fi

# --- 3. .gitignore ----------------------------------------------------------
printf '\nUpdating .gitignore...\n'
append_line "$TARGET/.gitignore" ".orchestrator/"
append_line "$TARGET/.gitignore" ".artifacts/"
made ".gitignore (.orchestrator/, .artifacts/)"

# --- 4. conventions templates into place ------------------------------------
printf '\nDropping conventions templates into place (strip .tmpl)...\n'
copy_tmpl "$CONV/CLAUDE.md.tmpl"  "$TARGET/CLAUDE.md"
copy_tmpl "$CONV/AGENTS.md.tmpl"  "$TARGET/AGENTS.md"
copy_tmpl "$CONV/MODULES.md.tmpl" "$TARGET/MODULES.md"
# contracts-package CLAUDE goes into the contracts package once it exists; stage it under docs/.
copy_tmpl "$CONV/contracts-package-CLAUDE.md.tmpl" "$TARGET/docs/contracts-package-CLAUDE.md"

# Wire the KB-location convention into the generated CLAUDE.md so the ingest->bootstrap
# handoff is explicit (the one placeholder the provenance chain depends on).
if [ -f "$TARGET/CLAUDE.md" ] && grep -q '{{KB_DIR}}' "$TARGET/CLAUDE.md" 2>/dev/null; then
  perl -0pi -e 's{\{\{KB_DIR\}\}}{docs/kb}g' "$TARGET/CLAUDE.md"
  log "wired KB_DIR -> docs/kb in CLAUDE.md"
fi

# --- 5. optional preset -----------------------------------------------------
if [ -n "$PRESET" ]; then
  printf '\nApplying preset: %s\n' "$PRESET"
  SRC_PRESET="$KIT_ROOT/presets/$PRESET"
  if [ -d "$SRC_PRESET" ]; then
    ensure_dir "$TARGET/docs/presets/$PRESET"
    cp -R "$SRC_PRESET/." "$TARGET/docs/presets/$PRESET/"
    made "docs/presets/$PRESET/ (copied from kit presets/$PRESET/)"
    # Wire the preset into CLAUDE.md / AGENTS.md so every agent session reads it as project law.
    PRESET_REF="> **Preset applied:** ${PRESET}. Read \`docs/presets/${PRESET}/*\` and the auth ADR before any feature work."
    for f in "$TARGET/CLAUDE.md" "$TARGET/AGENTS.md"; do
      if [ -f "$f" ] && ! grep -qF "Preset applied:" "$f" 2>/dev/null; then
        printf '\n%s\n' "$PRESET_REF" >> "$f"
        log "referenced preset in ${f#$TARGET/}"
      fi
    done
  else
    log "WARN: preset not found in kit: presets/$PRESET — skipping"
  fi
fi

# --- footer -----------------------------------------------------------------
cat <<EOF

Done. Next steps:

  1. Ingest the corpus into the KB (if not already): /kit-ingest <corpus-dir> docs/kb
       (CLAUDE.md's KB path is already wired to docs/kb).
  2. Fill the {{PLACEHOLDERS}} in CLAUDE.md, AGENTS.md, MODULES.md (stack, DB, pkg mgr, seam paths).
  3. Write the stack ADR:               docs/adr/0001-stack.md
  4. Move docs/contracts-package-CLAUDE.md into your contracts package once it exists.
  5. Author the development-contract artifacts from toolkit/contract/*.tmpl, in order:
       acceptance-criteria.md  ->  design-spec.md  ->  build-plan.md  ->  ticket.todo.md
  6. Tune the .gitattributes seam paths to your real schema dir / registries / contracts index.
  7. Run the orchestrator: file tickets into .orchestrator/tasks/inbox/ and start Wave 0.

  See examples/ for one tiny slice flowing through every stage above.

EOF

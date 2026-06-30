#!/usr/bin/env bash
# orchctl-init.sh — idempotent: prepare .orchestrator/ + gitignore + gitattributes.
# Run from inside the target project repo. Safe to run multiple times.

set -euo pipefail

if [ ! -d .git ]; then
  echo "orchctl-init: not in a git repo. Run from the project root." >&2
  exit 1
fi

# 0. Claim the session lock (PROTOCOL.md §11.1).
mkdir -p .orchestrator
LOCK=".orchestrator/session.lock"
if [ -f "$LOCK" ]; then
  # Stale-lock detection: ignore locks older than 1 hour.
  if [ "$(find "$LOCK" -mmin +60 -print 2>/dev/null)" = "" ]; then
    EXISTING=$(grep -m1 '^session_id:' "$LOCK" 2>/dev/null | awk '{print $2}' || echo "?")
    STARTED=$(grep -m1 '^started:'    "$LOCK" 2>/dev/null | cut -d' ' -f2- || echo "?")
    echo "orchctl-init: another orchestrator session ($EXISTING, started $STARTED) is active." >&2
    echo "  - if stale: rm $LOCK && retry" >&2
    echo "  - if live:  wait OR run in a separate worktree of this repo" >&2
    echo "              (git worktree add <path> origin/main)" >&2
    exit 3
  else
    echo "orchctl-init: removing stale lock (older than 1h)"
    rm "$LOCK"
  fi
fi

# Generate a session id. Prefer uuidgen; fall back to openssl rand hex.
if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="$(uuidgen | tr 'A-Z' 'a-z')"
else
  SESSION_ID="$(openssl rand -hex 16)"
fi
SESSION_SHORT="${SESSION_ID:0:5}"

cat > "$LOCK" <<EOF
session_id: $SESSION_ID
session_short: $SESSION_SHORT
hostname: $(hostname -s 2>/dev/null || echo unknown)
pid: $$
started: $(date -Iseconds 2>/dev/null || date)
EOF

echo "orchctl-init: claimed session $SESSION_SHORT ($SESSION_ID)"
echo "  -> sub-agents should suffix their branch names with '-s${SESSION_SHORT}'"

# 1. Create the queue layout.
mkdir -p .orchestrator/tasks/{inbox,in-progress,done,escalated}

if [ ! -f .orchestrator/state.md ]; then
  cat > .orchestrator/state.md <<'EOF'
# Orchestrator State

**Date:** _set on first wave_
**Run ID:** _set on first wave_

## Baselines

_filled by Phase 0 before any spawn_

## Producer ledger

_filled after each Wave-1 producer returns_

## Consumer ledger

_filled after each Wave-2 consumer returns_

## Run summary

_filled in Phase 3_
EOF
  echo "orchctl-init: created .orchestrator/state.md"
fi

# 2. Ensure .gitignore on the current branch lists .orchestrator/.
GITIGNORE_ENTRIES=(
  ".orchestrator/"
  ".artifacts/"
)
TOUCHED_GITIGNORE=0
for entry in "${GITIGNORE_ENTRIES[@]}"; do
  if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
    echo "$entry" >> .gitignore
    TOUCHED_GITIGNORE=1
    echo "orchctl-init: added $entry to .gitignore"
  fi
done

# 3. Ensure .gitattributes has merge=union for append-only docs.
GITATTR_ENTRIES=(
  "docs/open-questions.md merge=union"
  "tests/qa/findings/by-persona/*.md merge=union"
  "tests/qa/findings/consolidated.md merge=union"
)
TOUCHED_GITATTR=0
for entry in "${GITATTR_ENTRIES[@]}"; do
  if ! grep -qxF "$entry" .gitattributes 2>/dev/null; then
    echo "$entry" >> .gitattributes
    TOUCHED_GITATTR=1
    echo "orchctl-init: added '$entry' to .gitattributes"
  fi
done

# 4. Commit the pre-flight changes (only if anything actually changed and there
#    are no other staged changes to avoid pulling in unrelated work).
if [ "$TOUCHED_GITIGNORE$TOUCHED_GITATTR" != "00" ]; then
  if git diff --cached --quiet; then
    git add .gitignore .gitattributes 2>/dev/null || true
    git commit -m "chore(orch): prepare orchestrator infra

- gitignore .orchestrator/ + .artifacts/
- gitattributes merge=union for append-only finding/open-question docs

Co-Authored-By: orchctl-init
" >/dev/null
    echo "orchctl-init: committed orchestrator infra"
  else
    echo "orchctl-init: WARNING — staged changes already present; please commit them separately, then re-run." >&2
    exit 2
  fi
else
  echo "orchctl-init: gitignore + gitattributes already current — nothing to commit"
fi

echo "orchctl-init: ready. Queue at .orchestrator/tasks/."

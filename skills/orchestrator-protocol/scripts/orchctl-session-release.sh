#!/usr/bin/env bash
# orchctl-session-release.sh — clear the session lock, append a run-summary
# entry to .orchestrator/state.md, and prune the session's own throwaway
# worktrees + branches (PROTOCOL.md §11.5 / §11.6). Idempotent.
#
# Environment:
#   MISSION_REF   ref to test "merged into" against (default: HEAD)
#   SESSION_SHORT 5-char session id suffix for branch matching
#                 (default: read from .orchestrator/session.lock)
#   SKIP_CLEANUP  set to 1 to release the lock but skip §11.6 cleanup

set -euo pipefail

if [ ! -d .orchestrator ]; then
  echo "orchctl-session-release: .orchestrator/ does not exist." >&2
  exit 1
fi

LOCK=".orchestrator/session.lock"
SESSION_ID="?"
SESSION_SHORT="${SESSION_SHORT:-}"
STARTED="?"
ENDED="$(date -Iseconds 2>/dev/null || date)"

if [ -f "$LOCK" ]; then
  SESSION_ID=$(grep -m1 '^session_id:' "$LOCK" 2>/dev/null | awk '{print $2}' || echo "?")
  STARTED=$(grep -m1 '^started:' "$LOCK" 2>/dev/null | cut -d' ' -f2- || echo "?")
  if [ -z "$SESSION_SHORT" ] && [ "$SESSION_ID" != "?" ]; then
    SESSION_SHORT="${SESSION_ID:0:5}"
  fi
  rm "$LOCK"
  echo "orchctl-session-release: released session $SESSION_ID (started $STARTED, ended $ENDED)"
else
  echo "orchctl-session-release: no active lock (already released or never claimed)"
fi

# ---- §11.6 Session artifact cleanup -----------------------------------------
removed_wt=0
deleted_br=0
dirty_skip=()
unmerged_skip=()

cleanup() {
  local mission_ref="${MISSION_REF:-HEAD}"

  # Resolve the list of branches currently held by any worktree so we never
  # delete a branch out from under one.
  local held
  held=$(git worktree list --porcelain 2>/dev/null \
    | awk '/^branch refs\/heads\//{sub("refs/heads/","",$2); print $2}')

  # 1) Worktrees under .claude/worktrees/agent-*
  if [ -d .claude/worktrees ]; then
    for wt in .claude/worktrees/agent-*; do
      [ -d "$wt" ] || continue
      local br dirty
      br=$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo "")
      dirty=$(git -C "$wt" status --short 2>/dev/null | wc -l | tr -d ' ')
      if [ "$dirty" != "0" ]; then
        dirty_skip+=("$wt [$br] ($dirty dirty files)")
        continue
      fi
      if [ -n "$br" ] && ! git merge-base --is-ancestor "$br" "$mission_ref" 2>/dev/null; then
        unmerged_skip+=("$wt [$br]")
        continue
      fi
      if git worktree remove --force "$wt" >/dev/null 2>&1; then
        removed_wt=$((removed_wt + 1))
      fi
    done
  fi

  # 2) Free-standing branches: harness worktree-agent-* + session-suffixed.
  local branches=""
  branches=$(git for-each-ref --format='%(refname:short)' 'refs/heads/worktree-agent-*' 2>/dev/null || true)
  if [ -n "$SESSION_SHORT" ]; then
    branches="$branches
$(git for-each-ref --format='%(refname:short)' "refs/heads/*-s${SESSION_SHORT}" 2>/dev/null || true)"
  fi
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    if echo "$held" | grep -qx "$b"; then
      continue
    fi
    if git branch -d "$b" >/dev/null 2>&1; then
      deleted_br=$((deleted_br + 1))
    else
      unmerged_skip+=("branch $b")
    fi
  done <<< "$branches"
}

if [ "${SKIP_CLEANUP:-0}" != "1" ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    cleanup
    echo "cleanup: removed $removed_wt worktrees, deleted $deleted_br branches, skipped ${#dirty_skip[@]} dirty + ${#unmerged_skip[@]} unmerged"
    for x in "${dirty_skip[@]:-}";  do [ -n "$x" ] && echo "  DIRTY-SKIP: $x"; done
    for x in "${unmerged_skip[@]:-}"; do [ -n "$x" ] && echo "  UNMERGED-SKIP: $x"; done
  else
    echo "cleanup: not inside a git work tree; skipping §11.6 artifact pass"
  fi
fi

# ---- Ledger entry -----------------------------------------------------------
if [ -f .orchestrator/state.md ]; then
  {
    echo
    echo "## Run summary — session $SESSION_ID"
    echo "- started: $STARTED"
    echo "- ended: $ENDED"
    if [ "${SKIP_CLEANUP:-0}" != "1" ]; then
      echo "- cleanup: removed $removed_wt worktrees, deleted $deleted_br branches, skipped ${#dirty_skip[@]} dirty + ${#unmerged_skip[@]} unmerged"
      for x in "${dirty_skip[@]:-}";  do [ -n "$x" ] && echo "  - DIRTY-SKIP: $x"; done
      for x in "${unmerged_skip[@]:-}"; do [ -n "$x" ] && echo "  - UNMERGED-SKIP: $x"; done
    fi
  } >> .orchestrator/state.md
fi

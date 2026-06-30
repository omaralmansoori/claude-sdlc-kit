#!/usr/bin/env bash
# orchctl-status.sh — print a snapshot of the queue.

set -euo pipefail

if [ ! -d .orchestrator/tasks ]; then
  echo "orchctl-status: .orchestrator/tasks does not exist. Run orchctl-init.sh first." >&2
  exit 1
fi

printf "%-14s %s\n" "bucket" "count"
printf "%-14s %s\n" "------" "-----"
for bucket in inbox in-progress done escalated; do
  count=$(ls .orchestrator/tasks/$bucket 2>/dev/null | wc -l | tr -d ' ')
  printf "%-14s %s\n" "$bucket" "$count"
done
echo

if compgen -G ".orchestrator/tasks/inbox/*.todo.md" > /dev/null; then
  echo "inbox/:"
  for f in .orchestrator/tasks/inbox/*.todo.md; do
    id=$(grep -m1 '^id:' "$f" | awk '{print $2}')
    role=$(grep -m1 '^consumer_role:' "$f" | awk '{print $2}')
    prio=$(grep -m1 '^priority:' "$f" | awk '{print $2}')
    area=$(grep -m1 '^area:' "$f" | awk '{print $2}')
    printf "  %-30s role=%-12s prio=%-8s area=%s\n" "$id" "$role" "$prio" "$area"
  done
  echo
fi

if compgen -G ".orchestrator/tasks/in-progress/*.todo.md" > /dev/null; then
  echo "in-progress/:"
  for f in .orchestrator/tasks/in-progress/*.todo.md; do
    id=$(grep -m1 '^id:' "$f" | awk '{print $2}')
    branch=$(grep -A2 '^## Activity' "$f" | grep -m1 'branch:' | awk '{print $NF}' || true)
    printf "  %-30s branch=%s\n" "$id" "${branch:-?}"
  done
  echo
fi

if compgen -G ".orchestrator/tasks/escalated/*.todo.md" > /dev/null; then
  echo "escalated/ (Phase 3 will drain these into the operator-facing report):"
  for f in .orchestrator/tasks/escalated/*.todo.md; do
    id=$(grep -m1 '^id:' "$f" | awk '{print $2}')
    prio=$(grep -m1 '^priority:' "$f" | awk '{print $2}')
    printf "  %-30s prio=%s\n" "$id" "$prio"
  done
fi

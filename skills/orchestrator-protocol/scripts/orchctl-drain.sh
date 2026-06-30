#!/usr/bin/env bash
# orchctl-drain.sh — validate the queue is consolidatable and emit a paste-ready summary.
# Refuses to emit if any in-progress/ lacks ## Activity, any done/ lacks ## Resolution,
# or any escalated/ lacks ## Escalation reason.

set -euo pipefail

if [ ! -d .orchestrator/tasks ]; then
  echo "orchctl-drain: .orchestrator/tasks does not exist." >&2
  exit 1
fi

ERR=0

check_section () {
  local bucket="$1"
  local section="$2"
  for f in .orchestrator/tasks/$bucket/*.todo.md; do
    [ -e "$f" ] || continue
    if ! grep -q "^## $section" "$f"; then
      echo "orchctl-drain: $f missing '## $section'" >&2
      ERR=1
    fi
  done
}

check_section in-progress  "Activity"
check_section done         "Resolution"
check_section escalated    "Escalation reason"

if [ "$ERR" -ne 0 ]; then
  echo "orchctl-drain: refusing to emit summary — fix the missing sections first." >&2
  exit 2
fi

# Emit summary tables suitable for the operator-facing report.

echo "## Queue summary"
echo
printf "%-14s %s\n" "bucket" "count"
for bucket in inbox in-progress done escalated; do
  count=$(ls .orchestrator/tasks/$bucket 2>/dev/null | wc -l | tr -d ' ')
  printf "%-14s %s\n" "$bucket" "$count"
done
echo

if compgen -G ".orchestrator/tasks/escalated/*.todo.md" > /dev/null; then
  echo "## RED tracker (from escalated/)"
  echo
  echo "| id | priority | area | title |"
  echo "|---|---|---|---|"
  for f in .orchestrator/tasks/escalated/*.todo.md; do
    id=$(grep -m1 '^id:' "$f" | awk '{print $2}')
    prio=$(grep -m1 '^priority:' "$f" | awk '{print $2}')
    area=$(grep -m1 '^area:' "$f" | awk '{print $2}')
    title=$(grep -A1 '^## Title' "$f" | tail -n1 | sed 's/|/\\|/g')
    echo "| $id | $prio | $area | $title |"
  done
  echo
fi

if compgen -G ".orchestrator/tasks/done/*.todo.md" > /dev/null; then
  echo "## Closed tickets (from done/)"
  echo
  echo "| id | area | resolution commit |"
  echo "|---|---|---|"
  for f in .orchestrator/tasks/done/*.todo.md; do
    id=$(grep -m1 '^id:' "$f" | awk '{print $2}')
    area=$(grep -m1 '^area:' "$f" | awk '{print $2}')
    commit=$(grep -A4 '^## Resolution' "$f" | grep -m1 -oE '[a-f0-9]{7,40}' || echo "?")
    echo "| $id | $area | $commit |"
  done
fi

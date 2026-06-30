#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# remote-qa-launcher.sh — fan out a browser-tester QA fleet against a REMOTE,
# prod-shape QA box over an SSH tunnel.
#
# This is the reusable artifact the original project never committed: the
# remote-farm plumbing existed only as operator tribal knowledge. The canonical
# *local* recipe is parallel-browser-qa.md; this script is its remote analogue.
#
# It (a) opens an SSH local-forward from LOCAL_PORT -> the remote web port,
# (b) fans out N `claude -p` browser-only tester sessions against the tunneled
# origin (http://127.0.0.1:LOCAL_PORT), and (c) collects each tester's log.
# A trap tears the tunnel down on any exit.
#
# -----------------------------------------------------------------------------
# !!! DATA-RESIDENCY WARNING — READ BEFORE YOU RUN !!!
# -----------------------------------------------------------------------------
# This launcher is approved ONLY for environments seeded with SYNTHETIC test
# data. A personal / out-of-boundary remote box is FINE for synthetic seed data
# and is NEVER acceptable for regulated, PII, or otherwise sensitive data.
#
# If the target environment holds regulated/PII data, the heavy-QA box MUST sit
# INSIDE the approved hosting boundary (same residency/compliance perimeter as
# production). Do not tunnel regulated data to a developer laptop. When in doubt,
# stop and ask your data owner. You accept this responsibility by running this.
# -----------------------------------------------------------------------------
#
# Everything is parameterized by env vars — NO hardcoded host/user/port:
#   REMOTE_HOST      (required)  hostname/IP of the remote prod-shape QA box
#   REMOTE_USER      (required)  ssh user on that box
#   REMOTE_WEB_PORT  (required)  port the app listens on, ON the remote box
#   LOCAL_PORT       (default 8443)  local port to forward from
#   PERSONAS         (default "caseworker supervisor readonly admin")
#                                space-separated persona ids; each needs
#                                brief.<persona>.md and mcp.<persona>.json present
#   CONCURRENCY      (default 4)  max simultaneous tester sessions (the cap)
#   SSH_KEY          (optional)  path to an ssh identity file
#   MODEL            (default sonnet)  model for the tester sessions
#   OUT_DIR          (default ./qa-logs)  where per-persona logs are written
#
# Usage:
#   REMOTE_HOST=<a remote prod-shape QA box> REMOTE_USER=<user> \
#   REMOTE_WEB_PORT=3000 ./remote-qa-launcher.sh
#
# Prereqs: ssh, claude (Claude Code CLI), and per-persona brief.<p>.md +
# mcp.<p>.json files in the working dir (render them from the templates first).
# =============================================================================

# ---- config (env-driven, defensive defaults) --------------------------------
REMOTE_HOST="${REMOTE_HOST:?set REMOTE_HOST to the remote prod-shape QA box hostname}"
REMOTE_USER="${REMOTE_USER:?set REMOTE_USER to the ssh user on the remote box}"
REMOTE_WEB_PORT="${REMOTE_WEB_PORT:?set REMOTE_WEB_PORT to the app port on the remote box}"
LOCAL_PORT="${LOCAL_PORT:-8443}"
PERSONAS="${PERSONAS:-caseworker supervisor readonly admin}"
CONCURRENCY="${CONCURRENCY:-4}"
MODEL="${MODEL:-sonnet}"
OUT_DIR="${OUT_DIR:-./qa-logs}"
SSH_KEY="${SSH_KEY:-}"

BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
TUNNEL_PID=""

log() { printf '[remote-qa] %s\n' "$*" >&2; }
die() { printf '[remote-qa][FATAL] %s\n' "$*" >&2; exit 1; }

# ---- safety acknowledgement -------------------------------------------------
cat >&2 <<'BANNER'
-------------------------------------------------------------------------------
 remote-qa-launcher: SYNTHETIC DATA ONLY.
 Regulated/PII data requires the QA box to sit INSIDE the approved hosting
 boundary. Tunneling regulated data to an out-of-boundary box is prohibited.
-------------------------------------------------------------------------------
BANNER

# ---- preflight --------------------------------------------------------------
command -v ssh    >/dev/null 2>&1 || die "ssh not found on PATH"
command -v claude >/dev/null 2>&1 || die "claude (Claude Code CLI) not found on PATH"

for P in $PERSONAS; do
  [ -f "brief.${P}.md" ] || die "missing brief.${P}.md (render it from tester-brief.md.tmpl)"
  [ -f "mcp.${P}.json" ] || die "missing mcp.${P}.json (render it from mcp.persona.json.tmpl)"
done

mkdir -p "$OUT_DIR"

# ---- teardown trap: always close the tunnel --------------------------------
cleanup() {
  local status=$?
  if [ -n "${TUNNEL_PID}" ] && kill -0 "${TUNNEL_PID}" 2>/dev/null; then
    log "closing ssh tunnel (pid ${TUNNEL_PID})"
    kill "${TUNNEL_PID}" 2>/dev/null || true
    wait "${TUNNEL_PID}" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

# ---- open the tunnel --------------------------------------------------------
SSH_OPTS=(-N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3)
[ -n "$SSH_KEY" ] && SSH_OPTS+=(-i "$SSH_KEY")

log "opening tunnel: localhost:${LOCAL_PORT} -> ${REMOTE_HOST}:${REMOTE_WEB_PORT} (as ${REMOTE_USER})"
ssh "${SSH_OPTS[@]}" \
  -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_WEB_PORT}" \
  "${REMOTE_USER}@${REMOTE_HOST}" &
TUNNEL_PID=$!

# wait for the forwarded port to accept connections (max ~30s)
log "waiting for ${BASE_URL} to come up via the tunnel..."
for _ in $(seq 1 30); do
  if kill -0 "${TUNNEL_PID}" 2>/dev/null \
     && (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null; then
    exec 3>&- 2>/dev/null || true
    log "tunnel is up."
    break
  fi
  kill -0 "${TUNNEL_PID}" 2>/dev/null || die "ssh tunnel died during startup (check creds/host/port)"
  sleep 1
done

# ---- fan out the testers, capped at CONCURRENCY -----------------------------
run_tester() {
  local P="$1"
  local logf="${OUT_DIR}/${P}.log"
  log "launching tester: ${P} -> ${logf}"
  # Resolve the {{BASE_URL}} placeholder the tester-brief template actually uses to the
  # tunnel origin. (envsubst only handles $-style vars, never {{double-brace}} — so we sed.)
  BASE_URL="${BASE_URL}" claude -p "$(sed -e "s|{{BASE_URL}}|${BASE_URL}|g" "brief.${P}.md")" \
    --model "${MODEL}" \
    --mcp-config "mcp.${P}.json" \
    --strict-mcp-config \
    --allowedTools "mcp__playwright" \
    > "${logf}" 2>&1 \
    && log "tester ${P} finished OK" \
    || log "tester ${P} exited non-zero (inspect ${logf})"
}

running=0
pids=()
for P in $PERSONAS; do
  run_tester "$P" &
  pids+=("$!")
  running=$((running + 1))
  if [ "$running" -ge "$CONCURRENCY" ]; then
    # wait for the oldest in-flight tester before launching more (simple cap)
    wait "${pids[0]}" 2>/dev/null || true
    pids=("${pids[@]:1}")
    running=$((running - 1))
  fi
done

# drain the rest
for pid in "${pids[@]}"; do
  wait "$pid" 2>/dev/null || true
done

log "all tester sessions complete. logs in ${OUT_DIR}/"
log "NEXT: harvest each <persona>.log tail (the '# QA Findings - <persona>' block),"
log "      then run the MANDATORY Phase-3 adversarial verification in an Opus session"
log "      (see parallel-browser-qa.md) before trusting any finding."

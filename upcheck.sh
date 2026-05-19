#!/usr/bin/env bash
# Command line tool that monitors a remote server through a reboot and alerts when it's back up.

set -euo pipefail

# --------------- Vars ---------------
HOST="${1:-}"         # remote host to check
PORT="${2:-22}"       # port to test when the server is up (Default 22)
PING_INTERVAL=2       # seconds between checks
TIMEOUT=3             # ping/ssh timeout in seconds
MAX_WAIT=600          # max seconds to wait for server to come back (10 min)

# --------------- Usage ---------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <host> [port]

Monitors a remote server through a reboot and alerts when it's back up.

Arguments:
  host        IP address or hostname of the remote server (required)
  port        Port to verify the server is fully up (default: 22)

Options:
  -h, --help  Show this help message and exit

Examples:
  ./$(basename "$0") [host] [port]
  ./$(basename "$0") remote_server.example.com
  ./$(basename "$0") remote_server.example.com 2222

Behaviour:
  Phase 1 — Waits for the server to stop responding to pings (go down 🔴)
  Phase 2 — Waits for ping + port to both recover (come back up ✅)
  Exits 0 on success ✅, 2 on timeout ❌

Tunable variables (edit in script):
  PING_INTERVAL   Seconds between checks         (default: $PING_INTERVAL)
  TIMEOUT         Ping/TCP timeout per attempt   (default: $TIMEOUT)
  MAX_WAIT        Max seconds to wait for reboot (default: $MAX_WAIT/s)
EOF
  exit 0
}

# Handle -h / --help / no args
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
[[ -z "$HOST" ]] && { echo "Error: host is required."; echo ""; usage; }

# --------------- print timestamp message ---------------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# --------------- Notification ---------------
notify() {
  local title="$1"
  local message="$2"
  echo ""
  echo "========================================"
  echo "  >>> $title <<<"
  echo "  $message"
  echo "========================================"
  echo -e "\a"   # audible terminal bell
}

# --------------- check if host is pingable ---------------
is_pingable() {
  ping -c 1 -W "$TIMEOUT" "$HOST" &>/dev/null
}

# --------------- check if SSH port is open ---------------
is_port_open() {
  timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$HOST/$PORT" &>/dev/null
}

# --------------- Phase 1: Wait for the server to go down ---------------
log "Monitoring $HOST (port $PORT) - waiting for it to go offline..."

went_down=false
while true; do
  if ! is_pingable; then
    went_down=true
    log "Server is DOWN (no ping response)."
    notify "🔴 Server Down" "$HOST is not responding to pings."
    break
  fi
  sleep "$PING_INTERVAL"
done

# --------------- Phase 2: Wait for the server to come back up ---------------
log "Waiting for $HOST to come back online (max ${MAX_WAIT}s)..."

elapsed=0
while (( elapsed < MAX_WAIT )); do
  if is_pingable; then
    log "Ping restored - checking SSH port $PORT..."
    if is_port_open; then
      log "✅ Server is BACK UP! ($HOST responded on port $PORT)"
      notify "✅ Server Back Online" "$HOST is back up and accepting connections on port $PORT."
      exit 0
    else
      log "Ping OK, but port $PORT not yet open - still waiting..."
    fi
  fi
  sleep "$PING_INTERVAL"
  (( elapsed += PING_INTERVAL ))
done

# ─── Timeout ──────────────────────────────────────────────────────────────────
log "❌ Timed out after ${MAX_WAIT}s - $HOST did not come back online."
notify "❌ Server Timeout" "$HOST did not come back online within ${MAX_WAIT}s."
exit 2

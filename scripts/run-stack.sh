#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
cd "$REPO_DIR"

[[ -r "$ENV_FILE" ]] || { echo "Missing configuration: $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a
redis-cli ping | grep -qx PONG || { echo "Redis is not running" >&2; exit 1; }
[[ -x /usr/bin/node ]] || { echo "System Node is missing; run scripts/setup-backend.sh" >&2; exit 1; }

PIDS=()
cleanup() {
  trap - EXIT INT TERM
  ((${#PIDS[@]} == 0)) || kill "${PIDS[@]}" 2>/dev/null || true
  wait "${PIDS[@]}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

bash "$REPO_DIR/scripts/run-photon.sh" "$ENV_FILE" &
PIDS+=("$!")

npm start &
PIDS+=("$!")

sudo -u nominatim bash -c "set -a; source '$ENV_FILE'; cd '$REPO_DIR'; exec /usr/bin/node workers/searchIndexUpdateWorker.js" &
PIDS+=("$!")

echo "Photon, API, and worker started. Press Ctrl+C to stop them."
wait -n "${PIDS[@]}"
echo "A service stopped; shutting down the remaining services." >&2
exit 1

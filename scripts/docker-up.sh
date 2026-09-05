#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
HOST_PORT=5000

usage() {
  echo "Usage: bash scripts/docker-up.sh [--port HOST_PORT]"
}

while (( $# > 0 )); do
  case "$1" in
    -p|--port)
      [[ $# -ge 2 ]] || { echo "Missing value after $1" >&2; usage; exit 2; }
      HOST_PORT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ "$HOST_PORT" =~ ^[0-9]+$ ]] && (( HOST_PORT >= 1 && HOST_PORT <= 65535 )) || {
  echo "Invalid host port: $HOST_PORT" >&2
  exit 2
}
export HOST_PORT
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO_DIR/.env.example" "$ENV_FILE"
  token="$(openssl rand -hex 32)"
  sed -i \
    -e "s|^SEARCH_INDEX_ADMIN_TOKEN=.*|SEARCH_INDEX_ADMIN_TOKEN=$token|" \
    -e 's|^DB_PASS=.*|DB_PASS=postgres|' \
    -e 's|^NOMINATIM_DB_PASS=.*|NOMINATIM_DB_PASS=nominatim|' \
    -e 's|^PHOTON_DB_PASS=.*|PHOTON_DB_PASS=photon|' \
    "$ENV_FILE"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  echo "Generated $ENV_FILE. Review it now and make any changes you need."
  read -r -p "Press Enter to build and start the container... "
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a


API_PORT="$HOST_PORT"
READY_URL="http://127.0.0.1:$API_PORT/api/health"
TIMEOUT_SECONDS="${DOCKER_STARTUP_TIMEOUT_SECONDS:-28800}"
POLL_SECONDS=5

cd "$REPO_DIR"
docker compose up --build -d

echo "Container is running in the background."
echo "Waiting for the backend to become ready at $READY_URL ..."

started_at=$(date +%s)
last_log_at=0
while true; do
  if curl -fsS "$READY_URL" >/dev/null 2>&1; then
    echo
    echo "Bangladesh place-search backend is ready."
    echo "API: http://127.0.0.1:$API_PORT"
    echo
    echo "Try a search:"
    echo "curl --get 'http://127.0.0.1:$API_PORT/api' \\"
    echo "  --data-urlencode 'q=Dhaka' --data 'limit=5' | jq"
    echo
    echo "Status: docker compose ps"
    echo "Logs: docker compose logs -f"
    echo "Stop: docker compose down"
    exit 0
  fi

  container_id=$(docker compose ps -q place-search)
  if [[ -z "$container_id" ]] || [[ "$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null)" != true ]]; then
    echo "The container stopped before the backend became ready." >&2
    docker compose logs --tail=100 >&2
    exit 1
  fi

  elapsed=$(( $(date +%s) - started_at ))
  if (( elapsed >= TIMEOUT_SECONDS )); then
    echo "Timed out after ${TIMEOUT_SECONDS}s waiting for backend readiness." >&2
    echo "The container remains running. Inspect it with: docker compose logs -f" >&2
    exit 1
  fi

  if (( elapsed - last_log_at >= 30 )); then
    echo
    echo "Still starting (${elapsed}s elapsed). Recent container logs:"
    docker compose logs --tail=8 --no-color
    last_log_at=$elapsed
  fi

  sleep "$POLL_SECONDS"
done

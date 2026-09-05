#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${1:-/app/.env}"
[[ -r "$ENV_FILE" ]] || { echo "Startup update skipped: missing $ENV_FILE" >&2; exit 0; }

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

[[ "${SEARCH_INDEX_UPDATE_ON_START:-true}" == true ]] || {
  echo "Startup update is disabled."
  exit 0
}

: "${PORT:=10000}"
: "${SEARCH_INDEX_ADMIN_TOKEN:?Set SEARCH_INDEX_ADMIN_TOKEN}"
WAIT_SECONDS="${SEARCH_INDEX_STARTUP_WAIT_SECONDS:-900}"
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"
UPDATE_URL="http://127.0.0.1:${PORT}/api/admin/update"
deadline=$(( $(date +%s) + WAIT_SECONDS ))

until curl --fail --silent "$HEALTH_URL" >/dev/null 2>&1; do
  if (( $(date +%s) >= deadline )); then
    echo "Startup update skipped: services were not ready within ${WAIT_SECONDS}s." >&2
    exit 0
  fi
  sleep 5
done

echo "Checking for Geofabrik updates after startup..."
if ! curl --fail-with-body --silent --show-error --request POST "$UPDATE_URL" \
  --header "Authorization: Bearer ${SEARCH_INDEX_ADMIN_TOKEN}" \
  --header "Idempotency-Key: startup-$(date -u +%Y%m%dT%H)"; then
  echo "Startup update request failed; the running search snapshot remains available." >&2
  exit 0
fi
echo

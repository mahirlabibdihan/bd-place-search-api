#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
[[ -r "$ENV_FILE" ]] || { echo "Missing configuration: $ENV_FILE" >&2; exit 1; }

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${PORT:=5000}"
: "${SEARCH_INDEX_ADMIN_TOKEN:?Set SEARCH_INDEX_ADMIN_TOKEN in $ENV_FILE}"
: "${SEARCH_INDEX_API_BASE_URL:=http://127.0.0.1:${PORT}}"

IDEMPOTENCY_KEY="scheduled-$(date -u +%Y%m%dT%H)"
curl --fail-with-body --silent --show-error --request POST \
  "${SEARCH_INDEX_API_BASE_URL}/api/v1/admin/search-index-updates" \
  --header "Authorization: Bearer ${SEARCH_INDEX_ADMIN_TOKEN}" \
  --header "Idempotency-Key: ${IDEMPOTENCY_KEY}"
echo

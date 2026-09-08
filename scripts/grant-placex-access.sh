#!/usr/bin/env bash
set -Eeuo pipefail

# Applies the placex SELECT grant GET /api/admin/update/stats needs. Safe to run against an
# already-provisioned database — it only grants, it never creates or alters the role — so this
# covers a Render snapshot (volumes/*.tar) captured before the grant existed, or any existing
# bare-metal/Docker deployment that ran setup-search-engine.sh before this grant was added there.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
[[ -r "$ENV_FILE" ]] || { echo "Missing configuration: $ENV_FILE" >&2; exit 1; }

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${DB_HOST:=127.0.0.1}"
: "${DB_PORT:=5432}"
: "${DB_DB:=nominatim}"
: "${DB_USER:=place_search_status}"
: "${DB_ADMIN_USER:=postgres}"

for role in "$DB_ADMIN_USER" "$DB_USER"; do
  [[ "$role" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { echo "Invalid DB role: $role" >&2; exit 1; }
done

if [[ "$DB_HOST" == 127.0.0.1 || "$DB_HOST" == localhost ]]; then
  sudo -u postgres psql -X -v ON_ERROR_STOP=1 -p "$DB_PORT" -d "$DB_DB" -c "GRANT SELECT ON TABLE placex TO \"$DB_USER\""
else
  PGPASSWORD="${DB_ADMIN_PASS:-}" psql -X -v ON_ERROR_STOP=1 \
    -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d "$DB_DB" -c "GRANT SELECT ON TABLE placex TO \"$DB_USER\""
fi

echo "Granted SELECT on placex to \"$DB_USER\"."

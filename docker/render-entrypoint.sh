#!/usr/bin/env bash
set -Eeuo pipefail

: "${SEARCH_INDEX_ADMIN_TOKEN:?Set SEARCH_INDEX_ADMIN_TOKEN in the Render dashboard}"

if [[ -r /app/.snapshot-db.env ]]; then
  set -a
  # shellcheck source=/dev/null
  source /app/.snapshot-db.env
  set +a
fi

# Render owns the public listener. All bundled services stay on localhost.
export HOST=0.0.0.0
export PORT="${PORT:-10000}"
export DB_HOST=127.0.0.1
export DB_PORT=5432
export DB_PASS="${DB_PASS:-render-status-internal}"
export DB_ADMIN_PASS=""
export NOMINATIM_DB_PASS="${NOMINATIM_DB_PASS:-render-nominatim-internal}"
export PHOTON_DB_PASS="${PHOTON_DB_PASS:-render-photon-internal}"
export DB_PGPASSFILE=/srv/place-search/.pgpass
export NOMINATIM_HOME=/srv/nominatim
export NOMINATIM_PROJECT_DIR=/srv/nominatim/project
export NOMINATIM_BIN=/srv/nominatim/venv/bin/nominatim
export PHOTON_HOME=/srv/photon
export PHOTON_BASE_URL=http://127.0.0.1:2322
export PHOTON_LISTEN_IP=127.0.0.1
export REDIS_URL=redis://127.0.0.1:6379/0

# Lock files captured in an image snapshot are never valid in a new container.
find -L "$PHOTON_HOME/current/photon_data" -type f -name '*.lock' -delete

install -d -m 0700 /srv/place-search
printf '%s:%s:%s:%s:%s\n' "$DB_HOST" "$DB_PORT" "${DB_DB:-nominatim}" "${DB_USER:-place_search_status}" "$DB_PASS" > /srv/place-search/.pgpass
chmod 0600 /srv/place-search/.pgpass

ENV_FILE=/app/.env
: > "$ENV_FILE"
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    default_value="${BASH_REMATCH[2]}"
    printf '%s=%s\n' "$key" "${!key-$default_value}" >> "$ENV_FILE"
  else
    printf '%s\n' "$line" >> "$ENV_FILE"
  fi
done < /app/.env.example
chmod 600 "$ENV_FILE"

exec /usr/bin/supervisord -n -c /app/docker/supervisord.render.conf

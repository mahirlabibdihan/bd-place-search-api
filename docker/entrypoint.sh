#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE=/app/.env
MARKER=/srv/nominatim/.docker-setup-complete
[[ -r "$ENV_FILE" ]] || { echo "Missing /app/.env. Run: bash scripts/docker-up.sh" >&2; exit 1; }
chown nominatim:nominatim /srv/nominatim
chown photon:photon /srv/photon

service postgresql start
if [[ ! -f "$MARKER" ]]; then
  echo "First start: importing Bangladesh and building Photon. This can take a long time."
  bash /app/scripts/setup-search-engine.sh "$ENV_FILE"
  touch "$MARKER"
fi
service postgresql stop || true
exec /usr/bin/supervisord -n -c /app/docker/supervisord.conf

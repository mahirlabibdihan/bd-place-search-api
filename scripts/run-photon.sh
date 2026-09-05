#!/usr/bin/env bash
set -Eeuo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${DB_HOST:=127.0.0.1}"
: "${DB_PORT:=5432}"
: "${DB_DB:=nominatim}"
: "${PHOTON_DB_USER:=photon_import}"
: "${PHOTON_HOME:=/srv/photon}"
: "${PHOTON_VERSION:=1.2.1}"
: "${PHOTON_HEAP_MIN:=1g}"
: "${PHOTON_HEAP_MAX:=3g}"
: "${PHOTON_LANGUAGES:=en,bn}"
: "${PHOTON_COUNTRY_CODES:=bd}"
: "${PHOTON_LISTEN_IP:=127.0.0.1}"
: "${PHOTON_LISTEN_PORT:=2322}"

exec sudo -u photon java "-Xms$PHOTON_HEAP_MIN" "-Xmx$PHOTON_HEAP_MAX" \
  -jar "$PHOTON_HOME/releases/photon-$PHOTON_VERSION.jar" serve \
  -data-dir "$PHOTON_HOME/current" \
  -listen-ip "$PHOTON_LISTEN_IP" -listen-port "$PHOTON_LISTEN_PORT" \
  -default-language en -metrics-enable prometheus -enable-update-api \
  -host "$DB_HOST" -port "$DB_PORT" -database "$DB_DB" \
  -user "$PHOTON_DB_USER" -languages "$PHOTON_LANGUAGES" \
  -country-codes "$PHOTON_COUNTRY_CODES"

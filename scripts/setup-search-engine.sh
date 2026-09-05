#!/usr/bin/env bash
set -Eeuo pipefail

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
: "${DB_PASS:?Set DB_PASS in .env}"
: "${DB_PGPASSFILE:=/srv/place-search/.pgpass}"
: "${DB_ADMIN_USER:=postgres}"
: "${NOMINATIM_DB_USER:=nominatim}"
: "${NOMINATIM_DB_PASS:?Set NOMINATIM_DB_PASS in .env}"
: "${PHOTON_DB_USER:=photon_import}"
: "${PHOTON_DB_PASS:?Set PHOTON_DB_PASS in .env}"
: "${NOMINATIM_HOME:=/srv/nominatim}"
: "${PHOTON_HOME:=/srv/photon}"
: "${NOMINATIM_VERSION:=5.3.2}"
: "${PHOTON_VERSION:=1.2.1}"
: "${NOMINATIM_REPLICATION_URL:=https://download.geofabrik.de/asia/bangladesh-updates}"
: "${OSM_PBF_URL:=https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf}"
: "${PHOTON_LANGUAGES:=en,bn}"
: "${PHOTON_COUNTRY_CODES:=bd}"
: "${PHOTON_HEAP_MIN:=1g}"
: "${PHOTON_HEAP_MAX:=3g}"

IS_LOCAL_DB=false
if [[ "$DB_HOST" == 127.0.0.1 || "$DB_HOST" == localhost ]]; then
  IS_LOCAL_DB=true
fi

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash scripts/setup-search-engine.sh" >&2; exit 1; }
for role in "$DB_ADMIN_USER" "$NOMINATIM_DB_USER" "$PHOTON_DB_USER" "$DB_USER"; do
  [[ "$role" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { echo "Invalid DB role: $role" >&2; exit 1; }
done

sql_literal() { printf "%s" "${1//\'/\'\'}"; }

admin_psql() {
  if [[ "$IS_LOCAL_DB" == true ]]; then
    sudo -u postgres psql -X -v ON_ERROR_STOP=1 -p "$DB_PORT" "$@"
  else
    PGPASSWORD="${DB_ADMIN_PASS:-}" psql -X -v ON_ERROR_STOP=1 \
      -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d "${DB_ADMIN_DB:-postgres}" "$@"
  fi
}

ensure_role() {
  local role=$1 password=$2 escaped
  escaped=$(sql_literal "$password")
  if ! admin_psql -Atc "SELECT 1 FROM pg_roles WHERE rolname='${role}'" | grep -qx 1; then
    printf 'CREATE ROLE "%s" LOGIN PASSWORD '\''%s'\'';\n' "$role" "$escaped" | admin_psql
  else
    printf 'ALTER ROLE "%s" PASSWORD '\''%s'\'';\n' "$role" "$escaped" | admin_psql
  fi
}

write_pgpass() {
  local file=$1 owner=$2 user=$3 password=$4 database=${5:-$DB_DB}
  install -m 0600 -o "$owner" -g "$owner" /dev/null "$file"
  printf '%s:%s:%s:%s:%s\n' "$DB_HOST" "$DB_PORT" "$database" "$user" "$password" > "$file"
  chown "$owner:$owner" "$file"
  chmod 0600 "$file"
}

echo "[1/6] Installing system packages"
apt update
apt install -y postgresql postgresql-postgis postgresql-postgis-scripts osm2pgsql \
  build-essential pkg-config libicu-dev python3-venv python3-pip python3-dev openjdk-21-jre-headless \
  curl wget jq bzip2 ca-certificates

echo "[2/6] Creating service users and database roles"
if [[ "$IS_LOCAL_DB" == true ]] && command -v pg_lsclusters >/dev/null 2>&1; then
  LOCAL_DB_PORT=$(pg_lsclusters --no-header | awk '$4 == "online" { print $3; exit }')
  if [[ -n "$LOCAL_DB_PORT" && "$DB_PORT" != "$LOCAL_DB_PORT" ]]; then
    echo "Configured DB_PORT=$DB_PORT, but this Ubuntu PostgreSQL cluster uses $LOCAL_DB_PORT." >&2
    echo "Use a separate environment file with DB_PORT=$LOCAL_DB_PORT." >&2
    echo "Example: cp .env .env.test && sed -i 's/^DB_PORT=.*/DB_PORT=$LOCAL_DB_PORT/' .env.test" >&2
    exit 1
  fi
fi
if [[ "$IS_LOCAL_DB" == true && -n "${DB_ADMIN_PASS:-}" ]]; then
  escaped_admin_password=$(sql_literal "$DB_ADMIN_PASS")
  printf 'ALTER ROLE "%s" PASSWORD '\''%s'\'';\n' "$DB_ADMIN_USER" "$escaped_admin_password" | admin_psql
fi
id -u nominatim >/dev/null 2>&1 || useradd --create-home --home-dir "$NOMINATIM_HOME" --shell /bin/bash nominatim
id -u photon >/dev/null 2>&1 || useradd --system --home "$PHOTON_HOME" --shell /usr/sbin/nologin photon
install -d -o nominatim -g nominatim "$NOMINATIM_HOME/project" "$NOMINATIM_HOME/data" "$NOMINATIM_HOME/log"
install -d -o photon -g photon "$PHOTON_HOME/releases" "$PHOTON_HOME/builds" "$PHOTON_HOME/current"
chown nominatim:nominatim "$NOMINATIM_HOME"
chown photon:photon "$PHOTON_HOME"
ensure_role "$NOMINATIM_DB_USER" "$NOMINATIM_DB_PASS"
admin_psql -c "ALTER ROLE \"$NOMINATIM_DB_USER\" SUPERUSER"
ensure_role "$PHOTON_DB_USER" "$PHOTON_DB_PASS"
if ! admin_psql -Atc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -qx 1; then
  admin_psql -c 'CREATE ROLE "www-data" LOGIN'
fi
write_pgpass "$NOMINATIM_HOME/.pgpass" nominatim "$NOMINATIM_DB_USER" "$NOMINATIM_DB_PASS" "*"
write_pgpass "$PHOTON_HOME/.pgpass" photon "$PHOTON_DB_USER" "$PHOTON_DB_PASS"

echo "[3/6] Installing Nominatim"
if [[ ! -x "$NOMINATIM_HOME/venv/bin/nominatim" ]]; then
  sudo -u nominatim python3 -m venv "$NOMINATIM_HOME/venv"
  sudo -u nominatim "$NOMINATIM_HOME/venv/bin/pip" install --upgrade pip
  sudo -u nominatim "$NOMINATIM_HOME/venv/bin/pip" install \
    "nominatim-db==$NOMINATIM_VERSION" 'psycopg[binary]' osmium
fi
cat > "$NOMINATIM_HOME/project/.env" <<EOF
NOMINATIM_DATABASE_DSN=pgsql:host=$DB_HOST;port=$DB_PORT;dbname=$DB_DB;user=$NOMINATIM_DB_USER
NOMINATIM_TOKENIZER=icu
NOMINATIM_REPLICATION_URL=$NOMINATIM_REPLICATION_URL
NOMINATIM_REPLICATION_UPDATE_INTERVAL=86400
NOMINATIM_REPLICATION_RECHECK_INTERVAL=900
EOF
chown nominatim:nominatim "$NOMINATIM_HOME/project/.env"
chmod 0600 "$NOMINATIM_HOME/project/.env"

echo "[4/6] Importing Bangladesh into Nominatim"
PBF="$NOMINATIM_HOME/data/bangladesh-latest.osm.pbf"
PBF_DIR=$(dirname "$PBF")
PBF_NAME=$(basename "$PBF")
DATABASE_READY=false
if admin_psql -Atc "SELECT 1 FROM pg_database WHERE datname='${DB_DB}'" | grep -qx 1; then
  if admin_psql -d "$DB_DB" -Atc "SELECT to_regclass('public.import_status')" | grep -qx import_status; then
    DATABASE_READY=true
    echo "Existing Nominatim database is valid; resuming setup without reimporting it."
  else
    echo "Database $DB_DB exists but is not a valid Nominatim import; refusing to modify it." >&2
    exit 1
  fi
fi

if [[ "$DATABASE_READY" == false ]]; then
  sudo -u nominatim wget -c -O "$PBF" "$OSM_PBF_URL"
  sudo -u nominatim wget --no-cache -O "$PBF.md5" "$OSM_PBF_URL.md5"

  if ! (cd "$PBF_DIR" && md5sum --check "$PBF_NAME.md5"); then
    echo "Cached PBF failed verification; downloading a clean copy." >&2
    rm -f -- "$PBF" "$PBF.md5"
    sudo -u nominatim wget --no-cache -O "$PBF" "$OSM_PBF_URL"
    sudo -u nominatim wget --no-cache -O "$PBF.md5" "$OSM_PBF_URL.md5"
    (cd "$PBF_DIR" && md5sum --check "$PBF_NAME.md5")
  fi

  sudo -u nominatim bash -c "cd '$NOMINATIM_HOME/project' && '$NOMINATIM_HOME/venv/bin/nominatim' import --osm-file '$PBF' --reverse-only"
  sudo -u nominatim bash -c "cd '$NOMINATIM_HOME/project' && '$NOMINATIM_HOME/venv/bin/nominatim' admin --check-database && '$NOMINATIM_HOME/venv/bin/nominatim' replication --init"
fi

echo "Catching Nominatim up to the latest published regional diff"
sudo -u nominatim bash -c "cd '$NOMINATIM_HOME/project' && '$NOMINATIM_HOME/venv/bin/nominatim' replication --catch-up"

ensure_role "$DB_USER" "$DB_PASS"
admin_psql -d "$DB_DB" -c "GRANT CONNECT ON DATABASE \"$DB_DB\" TO \"$DB_USER\""
admin_psql -d "$DB_DB" -c "GRANT USAGE ON SCHEMA public TO \"$DB_USER\""
admin_psql -d "$DB_DB" -c "GRANT SELECT ON TABLE import_status TO \"$DB_USER\""
STATUS_OWNER=${SUDO_USER:-root}
install -d -m 0700 -o "$STATUS_OWNER" -g "$STATUS_OWNER" "$(dirname "$DB_PGPASSFILE")"
write_pgpass "$DB_PGPASSFILE" "$STATUS_OWNER" "$DB_USER" "$DB_PASS"

echo "[5/6] Building Photon index"
JAR="$PHOTON_HOME/releases/photon-$PHOTON_VERSION.jar"
[[ -f "$JAR" ]] || sudo -u photon wget -O "$JAR" "https://github.com/komoot/photon/releases/download/$PHOTON_VERSION/photon-$PHOTON_VERSION.jar"
chmod 0755 "$PHOTON_HOME" "$PHOTON_HOME/releases"
chmod 0644 "$JAR"
admin_psql -d "$DB_DB" -c 'CREATE INDEX IF NOT EXISTS placex_country_code_idx ON placex(country_code)'
admin_psql -d "$DB_DB" -c "GRANT USAGE ON SCHEMA public TO \"$PHOTON_DB_USER\""
admin_psql -d "$DB_DB" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"$PHOTON_DB_USER\""
BUILD="$PHOTON_HOME/builds/bd-initial"
STALE_BUILD=""
if [[ -e "$BUILD/photon_data" ]]; then
  if pgrep -u photon -f 'photon-.*\.jar' >/dev/null 2>&1; then
    echo "Photon is running; stop it before rebuilding the index." >&2
    exit 1
  fi
  STALE_BUILD="${BUILD}.stale-$(date -u +%Y%m%dT%H%M%SZ)"
  mv -- "$BUILD" "$STALE_BUILD"
  echo "Archived stale Photon build at $STALE_BUILD"
fi
install -d -o photon -g photon "$BUILD"
sudo -u photon java "-Xms$PHOTON_HEAP_MIN" "-Xmx$PHOTON_HEAP_MAX" -jar "$JAR" import \
  -host "$DB_HOST" -port "$DB_PORT" -database "$DB_DB" -user "$PHOTON_DB_USER" \
  -languages "$PHOTON_LANGUAGES" -country-codes "$PHOTON_COUNTRY_CODES" -data-dir "$BUILD"
sudo -u photon ln -sfnT "$BUILD/photon_data" "$PHOTON_HOME/current/photon_data"

echo "[6/6] Initializing live updates"
sudo -u nominatim java -jar "$JAR" update-init -host "$DB_HOST" -port "$DB_PORT" \
  -database "$DB_DB" -user "$NOMINATIM_DB_USER" -import-user "$PHOTON_DB_USER"
rm -f -- "$PBF" "$PBF.md5"
if [[ -n "$STALE_BUILD" && -d "$STALE_BUILD" ]]; then
  rm -rf -- "$STALE_BUILD"
fi
sudo -u nominatim "$NOMINATIM_HOME/venv/bin/pip" cache purge >/dev/null 2>&1 || true
echo "Removed temporary PBF/checksum, pip cache, and any replaced Photon build."
echo "Setup complete. Start Photon with: bash scripts/run-photon.sh"

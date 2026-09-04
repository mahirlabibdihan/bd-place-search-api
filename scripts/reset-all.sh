#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISTRO_NAME=${WSL_DISTRO_NAME:-unknown}

[[ $EUID -eq 0 ]] || {
  echo "Run with sudo: sudo bash scripts/reset-all.sh" >&2
  exit 1
}

cat <<EOF
This will reset the place-search installation in WSL distribution: $DISTRO_NAME

It will permanently remove:
  /srv/nominatim
  /srv/photon
  /srv/place-search
  PostgreSQL databases and cluster configuration
  Redis data and configuration
  Node.js, Redis, PostgreSQL/PostGIS, osm2pgsql and Java packages
  NodeSource repository configuration

It will preserve:
  $REPO_DIR
  $REPO_DIR/.env
  $REPO_DIR/node_modules
EOF

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Type RESET-$DISTRO_NAME to continue: " confirmation
  [[ "$confirmation" == "RESET-$DISTRO_NAME" ]] || {
    echo "Reset cancelled."
    exit 1
  }
fi

echo "[1/5] Stopping place-search processes"
systemctl disable --now redis-server.service 2>/dev/null || true
systemctl disable --now postgresql.service 2>/dev/null || true
pkill -u photon -f 'photon-.*\.jar' 2>/dev/null || true
pkill -u nominatim -f 'searchIndexUpdateWorker\.js' 2>/dev/null || true

if pgrep -f "$REPO_DIR/server.js|node server.js" >/dev/null 2>&1; then
  echo "The backend API is still running. Stop run-stack.sh with Ctrl+C, then rerun reset." >&2
  exit 1
fi

echo "[2/5] Purging installed packages"
PACKAGE_CANDIDATES=(
  nodejs redis-server redis-tools
  postgresql postgresql-common postgresql-client-common
  postgresql-16 postgresql-client-16
  postgresql-postgis postgresql-postgis-scripts
  postgresql-16-postgis-3 postgresql-16-postgis-3-scripts
  osm2pgsql openjdk-21-jre-headless openjdk-21-jre
)
INSTALLED_PACKAGES=()
for package in "${PACKAGE_CANDIDATES[@]}"; do
  if dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii'; then
    INSTALLED_PACKAGES+=("$package")
  fi
done
if ((${#INSTALLED_PACKAGES[@]})); then
  apt-get purge -y "${INSTALLED_PACKAGES[@]}"
fi
apt-get autoremove --purge -y
apt-get clean

echo "[3/5] Removing application and database data"
for target in \
  /srv/nominatim \
  /srv/photon \
  /srv/place-search \
  /var/lib/postgresql \
  /etc/postgresql \
  /var/log/postgresql \
  /var/lib/redis \
  /etc/redis; do
  case "$target" in
    /srv/nominatim|/srv/photon|/srv/place-search|/var/lib/postgresql|/etc/postgresql|/var/log/postgresql|/var/lib/redis|/etc/redis)
      rm -rf -- "$target"
      ;;
    *)
      echo "Refusing unexpected removal target: $target" >&2
      exit 1
      ;;
  esac
done

echo "[4/5] Removing service users and NodeSource configuration"
id -u photon >/dev/null 2>&1 && userdel photon || true
id -u nominatim >/dev/null 2>&1 && userdel nominatim || true
rm -f -- \
  /etc/apt/sources.list.d/nodesource.list \
  /etc/apt/sources.list.d/nodesource.sources \
  /usr/share/keyrings/nodesource.gpg

echo "[5/5] Refreshing package metadata"
apt-get update

echo "Reset completed for $DISTRO_NAME."
echo "Reinstall with: sudo bash scripts/setup-all.sh"

#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash scripts/setup-all.sh [.env-file]" >&2; exit 1; }

bash "$REPO_DIR/scripts/setup-backend.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  TEMPLATE_FILE="$REPO_DIR/.env.example"
  [[ -f "$TEMPLATE_FILE" ]] || { echo "Missing environment template: $TEMPLATE_FILE" >&2; exit 1; }

  cp "$TEMPLATE_FILE" "$ENV_FILE"
  ADMIN_TOKEN="$(openssl rand -hex 32)"
  sed -i \
    -e "s|^SEARCH_INDEX_ADMIN_TOKEN=.*|SEARCH_INDEX_ADMIN_TOKEN=$ADMIN_TOKEN|" \
    -e 's|^DB_PASS=.*|DB_PASS=postgres|' \
    -e 's|^NOMINATIM_DB_PASS=.*|NOMINATIM_DB_PASS=nominatim|' \
    -e 's|^PHOTON_DB_PASS=.*|PHOTON_DB_PASS=photon|' \
    "$ENV_FILE"

  APP_OWNER=${SUDO_USER:-root}
  if [[ "$APP_OWNER" != root ]]; then
    chown "$APP_OWNER":"$(id -gn "$APP_OWNER")" "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE" 2>/dev/null || true

  echo
  echo "Generated $ENV_FILE with local-development database passwords and a random admin token."
  echo "Review it now and make any changes you need."
  echo "WARNING: The generated database passwords are intended only for a private local development setup."
  if [[ -t 0 ]]; then
    read -r -p "Press Enter to continue setup... "
  else
    echo "Non-interactive shell detected; continuing without waiting."
  fi
else
  echo "Using existing $ENV_FILE; it was not modified."
fi

bash "$REPO_DIR/scripts/setup-search-engine.sh" "$ENV_FILE"

echo "Everything is installed. Run: sudo bash scripts/run-stack.sh"

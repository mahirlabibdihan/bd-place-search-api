#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash scripts/install-update-timer.sh [.env-file]" >&2; exit 1; }
[[ -r "$ENV_FILE" ]] || { echo "Missing configuration: $ENV_FILE" >&2; exit 1; }

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${SEARCH_INDEX_AUTO_UPDATE_ENABLED:=true}"
: "${SEARCH_INDEX_AUTO_UPDATE_INTERVAL:=6h}"
: "${SEARCH_INDEX_AUTO_UPDATE_BOOT_DELAY:=10min}"
: "${SEARCH_INDEX_AUTO_UPDATE_RANDOM_DELAY:=10min}"

if [[ "$SEARCH_INDEX_AUTO_UPDATE_ENABLED" != true ]]; then
  systemctl disable --now place-search-update.timer 2>/dev/null || true
  echo "Automatic search-index updates are disabled in $ENV_FILE."
  exit 0
fi

for value in "$SEARCH_INDEX_AUTO_UPDATE_INTERVAL" "$SEARCH_INDEX_AUTO_UPDATE_BOOT_DELAY" "$SEARCH_INDEX_AUTO_UPDATE_RANDOM_DELAY"; do
  [[ "$value" =~ ^[1-9][0-9]*(s|min|h|d)$ ]] || {
    echo "Invalid systemd duration: $value (examples: 30min, 6h, 1d)" >&2
    exit 1
  }
done

APP_USER=${SUDO_USER:-root}
SERVICE_FILE=/etc/systemd/system/place-search-update.service
TIMER_FILE=/etc/systemd/system/place-search-update.timer

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Check and queue Bangladesh place-search updates
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$APP_USER
WorkingDirectory=$REPO_DIR
ExecStart=/usr/bin/bash $REPO_DIR/scripts/request-scheduled-update.sh $ENV_FILE
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Periodically check for Bangladesh place-search updates

[Timer]
OnBootSec=$SEARCH_INDEX_AUTO_UPDATE_BOOT_DELAY
OnUnitActiveSec=$SEARCH_INDEX_AUTO_UPDATE_INTERVAL
RandomizedDelaySec=$SEARCH_INDEX_AUTO_UPDATE_RANDOM_DELAY
Unit=place-search-update.service

[Install]
WantedBy=timers.target
EOF

chmod 0644 "$SERVICE_FILE" "$TIMER_FILE"
systemctl daemon-reload
systemctl enable --now place-search-update.timer
systemctl list-timers place-search-update.timer --no-pager

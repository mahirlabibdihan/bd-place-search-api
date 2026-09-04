#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash scripts/setup-backend.sh" >&2; exit 1; }

apt update
apt install -y curl ca-certificates redis-server

NODE_MAJOR=0
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -p 'Number(process.versions.node.split(".")[0])')
fi
if (( NODE_MAJOR < 22 )); then
  INSTALLER=$(mktemp)
  trap 'rm -f "$INSTALLER"' EXIT
  curl -fsSL https://deb.nodesource.com/setup_22.x -o "$INSTALLER"
  bash "$INSTALLER"
  apt install -y nodejs
fi

if redis-cli ping 2>/dev/null | grep -qx PONG; then
  echo "Redis is already running."
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable redis-server >/dev/null 2>&1 || true
  fi
else
  if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    systemctl enable --now redis-server
  else
    service redis-server start
  fi
fi

redis-cli ping 2>/dev/null | grep -qx PONG || {
  echo "Redis did not become ready. Check: systemctl status redis-server" >&2
  exit 1
}

APP_OWNER=${SUDO_USER:-root}
sudo -u "$APP_OWNER" bash -c "cd '$REPO_DIR' && npm install"

echo "Backend setup complete: Node $(node --version), Redis $(redis-cli ping)."

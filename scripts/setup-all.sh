#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/.env}"
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash scripts/setup-all.sh [.env-file]" >&2; exit 1; }

bash "$REPO_DIR/scripts/setup-backend.sh"
bash "$REPO_DIR/scripts/setup-search-engine.sh" "$ENV_FILE"

echo "Everything is installed. Run: bash scripts/run-stack.sh"

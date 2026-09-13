#!/usr/bin/env bash
set -Eeuo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"
for file in postgres.tar nominatim.tar photon.tar db.env; do
  [[ -s "volumes/$file" ]] || {
    echo 'First capture data with: bash scripts/snapshot-render-container.sh CONTAINER_NAME' >&2
    exit 1
  }
done
# Reuse the saved snapshot. Code updates never export or commit runtime data.
previous_image=$(docker image inspect -f '{{.Id}}' mahirlabibdihan/bangladesh-place-search:latest 2>/dev/null || true)
bash scripts/build-render-from-volumes.sh
docker compose -f compose.render-local.yaml up -d --wait --wait-timeout 180
current_image=$(docker image inspect -f '{{.Id}}' mahirlabibdihan/bangladesh-place-search:latest)
if [[ -n "$previous_image" && "$previous_image" != "$current_image" ]]; then
  docker image rm "$previous_image" || echo 'Previous image is still referenced; leaving it in place.'
fi
echo "Local API: http://localhost:${HOST_PORT:-5001}"

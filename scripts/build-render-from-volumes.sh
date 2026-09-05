#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
SNAPSHOT_DIR="$REPO_DIR/volumes"
IMAGE_TAG=bangladesh-place-search:render
SERVICE=place-search
LATEST=false
was_running=false
image_tag_set=false

usage() {
  echo "Usage: bash scripts/build-render-from-volumes.sh [--latest] [IMAGE_TAG]"
}

while (( $# > 0 )); do
  case "$1" in
    --latest)
      LATEST=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      [[ "$image_tag_set" == false ]] || {
        echo "Only one image tag may be provided." >&2
        usage
        exit 2
      }
      IMAGE_TAG=$1
      image_tag_set=true
      shift
      ;;
  esac
done

[[ -r "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker is required." >&2; exit 1; }

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

cleanup() {
  rm -f -- "$SNAPSHOT_DIR"/*.new
  if [[ "$was_running" == true ]]; then
    docker compose -f "$REPO_DIR/compose.yaml" start "$SERVICE" >/dev/null
    echo "Local stack restarted."
  fi
}
trap cleanup EXIT

cd "$REPO_DIR"
mkdir -p "$SNAPSHOT_DIR"

snapshot_complete=true
for file in postgres.tar nominatim.tar photon.tar db.env; do
  [[ -s "$SNAPSHOT_DIR/$file" ]] || snapshot_complete=false
done

if [[ "$LATEST" == true || "$snapshot_complete" == false ]]; then
  container_id=$(docker compose ps -aq "$SERVICE")
  [[ -n "$container_id" ]] || {
    echo "No local Compose container found. Run bash scripts/docker-up.sh first." >&2
    exit 1
  }

  if [[ "$LATEST" == true ]]; then
    echo "--latest requested; refreshing the saved data snapshot."
  else
    echo "No complete saved snapshot found; creating it now."
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' "$container_id")" == true ]]; then
    was_running=true
    echo "Stopping the local stack for a consistent PostgreSQL snapshot..."
    docker compose stop -t 60 "$SERVICE"
  fi

  volume_for() {
    docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$1\"}}{{.Name}}{{end}}{{end}}" "$container_id"
  }

  postgres_volume=$(volume_for /var/lib/postgresql)
  nominatim_volume=$(volume_for /srv/nominatim)
  photon_volume=$(volume_for /srv/photon)
  for volume in "$postgres_volume" "$nominatim_volume" "$photon_volume"; do
    [[ -n "$volume" ]] || { echo "A required Compose volume is missing." >&2; exit 1; }
    docker volume inspect "$volume" >/dev/null
  done

  export_volume() {
    local volume=$1 archive=$2
    shift 2
    echo "Exporting $volume..."
    docker run --rm \
      -v "$volume:/source:ro" \
      -v "$SNAPSHOT_DIR:/backup" \
      ubuntu:24.04 \
      tar --numeric-owner "$@" -C /source -cf "/backup/$archive.new" .
  }

  export_volume "$postgres_volume" postgres.tar
  export_volume "$nominatim_volume" nominatim.tar \
    --exclude='./data/bangladesh-latest.osm.pbf' \
    --exclude='./data/bangladesh-latest.osm.pbf.md5'
  export_volume "$photon_volume" photon.tar --exclude='./builds/*.stale-*'

  umask 077
  {
    printf 'DB_USER=%q\n' "${DB_USER:-place_search_status}"
    printf 'DB_DB=%q\n' "${DB_DB:-nominatim}"
    printf 'DB_PASS=%q\n' "${DB_PASS:?DB_PASS is required}"
    printf 'NOMINATIM_DB_USER=%q\n' "${NOMINATIM_DB_USER:-nominatim}"
    printf 'NOMINATIM_DB_PASS=%q\n' "${NOMINATIM_DB_PASS:?NOMINATIM_DB_PASS is required}"
    printf 'PHOTON_DB_USER=%q\n' "${PHOTON_DB_USER:-photon_import}"
    printf 'PHOTON_DB_PASS=%q\n' "${PHOTON_DB_PASS:?PHOTON_DB_PASS is required}"
  } > "$SNAPSHOT_DIR/db.env.new"

  for file in postgres.tar nominatim.tar photon.tar db.env; do
    mv -f -- "$SNAPSHOT_DIR/$file.new" "$SNAPSHOT_DIR/$file"
  done
  echo "Saved the reusable snapshot in $SNAPSHOT_DIR."
else
  echo "Reusing the saved data snapshot in $SNAPSHOT_DIR."
  echo "Use --latest when you want to capture the current volumes again."
fi

echo "Building $IMAGE_TAG..."
docker build \
  -f Dockerfile.render-snapshot \
  -t "$IMAGE_TAG" .

echo "Built $IMAGE_TAG."

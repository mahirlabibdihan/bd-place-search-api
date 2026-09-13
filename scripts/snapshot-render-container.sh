#!/usr/bin/env bash
set -Eeuo pipefail

# Export a consistent data snapshot without docker commit or copying image layers.
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${1:-bangladesh-place-search}"
SNAPSHOT_DIR="$REPO_DIR/volumes"
mkdir -p "$SNAPSHOT_DIR"
umask 077
was_running=false
restart_container() {
  if [[ "$was_running" == true ]]; then
    docker start "$CONTAINER" >/dev/null
  fi
}
trap restart_container EXIT

[[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" == true ]] || {
  echo 'Start the source container first so its active database configuration can be read.' >&2
  exit 1
}
# Only database settings belong in the snapshot; never capture the API admin token.
docker exec "$CONTAINER" bash -c '
  set -Eeuo pipefail
  source /app/.env
  for key in DB_USER DB_DB DB_PASS NOMINATIM_DB_USER NOMINATIM_DB_PASS PHOTON_DB_USER PHOTON_DB_PASS; do
    printf "%s=%q\n" "$key" "${!key}"
  done
' > "$SNAPSHOT_DIR/db.env.new"

echo 'Stopping the source container for a consistent database/index snapshot...'
was_running=true
docker stop -t 120 "$CONTAINER"
[[ "$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER")" == 0 ]] || {
  echo 'Container did not stop cleanly; snapshot cancelled.' >&2
  exit 1
}
docker cp "$CONTAINER":/var/lib/postgresql/. - > "$SNAPSHOT_DIR/postgres.tar.new"
docker cp "$CONTAINER":/srv/nominatim/. - > "$SNAPSHOT_DIR/nominatim.tar.new"
docker cp "$CONTAINER":/srv/photon/. - > "$SNAPSHOT_DIR/photon.tar.new"
for archive in postgres nominatim photon; do
  tar -tf "$SNAPSHOT_DIR/$archive.tar.new" >/dev/null
done
for file in postgres.tar nominatim.tar photon.tar db.env; do
  mv -f -- "$SNAPSHOT_DIR/$file.new" "$SNAPSHOT_DIR/$file"
done
restart_container
was_running=false
echo "Snapshot saved in $SNAPSHOT_DIR; source container restarted."

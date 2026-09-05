# Bangladesh Place Search Backend

Standalone Bangladesh place search backed by Photon. The API returns selected
place coordinates as `[longitude, latitude]`; downstream services own all later
spatial logic.

```text
Geofabrik -> Nominatim/PostgreSQL -> Photon index -> Express API
                                      ^
                         Redis/BullMQ update worker
```

The scripts target Ubuntu 24.04/WSL2, Node.js 22, Nominatim 5.3.2,
Photon 1.2.1, Java 21, and Bangladesh data.

## Quick start

From Ubuntu, open the repository stored on Windows:

```bash
cd /mnt/c/Users/Asus/Documents/BPO/bpo-postcode-backend
cp .env.example .env
nano .env
```

Configure the required `.env` values described below, then install everything:

```bash
sudo bash scripts/setup-all.sh
```

The initial PBF import and Photon index build can take a long time. The installer
validates the PBF checksum, catches Nominatim up with current regional diffs, and
can resume after an interruption. A stale Photon build is archived before being
rebuilt.

Start Photon, the API, and the worker:

```bash
bash scripts/run-stack.sh
```

Keep the terminal open. Press `Ctrl+C` to stop the stack.

## Configure `.env`

`.env` is ignored by Git and is sourced by Bash scripts, so use `KEY=value`
without spaces around `=`. Generate suitable development secrets with:

```bash
openssl rand -hex 32
```

### Values you must change

| Variable | What to set |
| --- | --- |
| `SEARCH_INDEX_ADMIN_TOKEN` | A long random token used to authorize update APIs. |
| `DB_PASS` | Password for the read-only `DB_USER` used by the API and worker. |
| `NOMINATIM_DB_PASS` | Password for the Nominatim database owner. |
| `PHOTON_DB_PASS` | Password for the Photon import/update database user. |

Using a different generated value for each password is recommended. The setup
script creates the roles and generates their required `.pgpass` files.

### Database settings

These defaults are correct for a single local installation:

```dotenv
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DB=nominatim
DB_USER=place_search_status
DB_PASS=replace-with-a-strong-password
DB_SSL=false
DB_PGPASSFILE=/srv/place-search/.pgpass

DB_ADMIN_USER=postgres
DB_ADMIN_PASS=
DB_ADMIN_DB=postgres
NOMINATIM_DB_USER=nominatim
NOMINATIM_DB_PASS=replace-with-a-strong-password
PHOTON_DB_USER=photon_import
PHOTON_DB_PASS=replace-with-a-strong-password
```

- Leave `DB_ADMIN_PASS` empty for local Ubuntu peer authentication.
- For a remote PostgreSQL server, change `DB_HOST`, `DB_PORT`, and administrator
  credentials. Set `DB_SSL=true` for the Node API/worker connection.
- `DB_USER` is intentionally read-only; do not replace it with the database
  administrator.
- If a second WSL distribution selects port `5433`, use a separate file:

```bash
cp .env .env.test
sed -i 's/^DB_PORT=.*/DB_PORT=5433/' .env.test
sudo bash scripts/setup-all.sh .env.test
bash scripts/run-stack.sh .env.test
```

The installer detects a local PostgreSQL port mismatch and reports the correct
port. `.env.test` and other `.env.*` files are ignored by Git.

### API, Photon, and Redis settings

Normally keep these defaults:

```dotenv
NODE_ENV=development
PORT=5000
PHOTON_BASE_URL=http://127.0.0.1:2322
PHOTON_REQUEST_TIMEOUT_MS=2000
PHOTON_RESULT_LIMIT=5
PLACE_SEARCH_MIN_CHARS=2
REDIS_URL=redis://127.0.0.1:6379/0
REDIS_CONNECT_TIMEOUT_MS=1000
SEARCH_INDEX_UPDATE_ENABLED=true
SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS=7200
```

- Increase `PHOTON_REQUEST_TIMEOUT_MS` if searches time out under heavy load.
- Text search remains available when Redis is down; only update features are
  disabled.
- Search returns HTTP 503 when Photon is unavailable.
- Photon update endpoints are derived from `PHOTON_BASE_URL`.
- Geofabrik's `state.txt` URL is derived from `NOMINATIM_REPLICATION_URL`.

### Search-engine installation settings

These defaults install English and Bangla Bangladesh data:

```dotenv
NOMINATIM_PROJECT_DIR=/srv/nominatim/project
NOMINATIM_BIN=/srv/nominatim/venv/bin/nominatim
NOMINATIM_HOME=/srv/nominatim
NOMINATIM_VERSION=5.3.2
NOMINATIM_REPLICATION_URL=https://download.geofabrik.de/asia/bangladesh-updates
OSM_PBF_URL=https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf

PHOTON_HOME=/srv/photon
PHOTON_VERSION=1.2.1
PHOTON_HEAP_MIN=1g
PHOTON_HEAP_MAX=3g
PHOTON_LANGUAGES=en,bn
PHOTON_COUNTRY_CODES=bd
PHOTON_LISTEN_IP=127.0.0.1
PHOTON_LISTEN_PORT=2322
```

Increase `PHOTON_HEAP_MAX` only when the machine has enough RAM. Keep Photon
bound to localhost unless a private network and access controls are configured.

## Scripts

| Command | Purpose |
| --- | --- |
| `sudo bash scripts/setup-all.sh` | Install the complete search engine and backend. |
| `sudo bash scripts/setup-backend.sh` | Install Node.js 22, Redis, and npm packages only. |
| `sudo bash scripts/setup-search-engine.sh` | Install/import Nominatim and Photon only. |
| `bash scripts/run-stack.sh` | Run Photon, API, and worker together. |
| `bash scripts/run-photon.sh` | Run Photon only. |
| `sudo bash scripts/reset-all.sh` | Remove the WSL installation while preserving the repository and `.env`. |

The reset script prints the active WSL distribution and requires an explicit
confirmation phrase. It permanently deletes PostgreSQL, Nominatim, Photon, and
Redis data from that distribution.

## Optional automatic updates

Automatic updates are separate from `setup-all.sh`. Configure the schedule:

```dotenv
SEARCH_INDEX_AUTO_UPDATE_ENABLED=true
SEARCH_INDEX_AUTO_UPDATE_INTERVAL=6h
SEARCH_INDEX_AUTO_UPDATE_BOOT_DELAY=10min
SEARCH_INDEX_AUTO_UPDATE_RANDOM_DELAY=10min
SEARCH_INDEX_API_BASE_URL=http://127.0.0.1:5000
```

Install the systemd timer explicitly:

```bash
sudo bash scripts/install-update-timer.sh
```

The timer calls the conditional update API. It creates no job when Geofabrik is
not newer. The API, Redis, and worker must be running when the timer fires.

```bash
systemctl list-timers place-search-update.timer
sudo systemctl start place-search-update.service
journalctl -u place-search-update.service -n 50 --no-pager
sudo systemctl disable --now place-search-update.timer
```

## API usage

Search:

```bash
curl --get 'http://127.0.0.1:5000/api/v1/places/search' \
  --data-urlencode 'q=Dhaka' --data 'lang=en' --data 'limit=5' | jq

curl --get 'http://127.0.0.1:5000/api/v1/places/search' \
  --data-urlencode 'q=ঢাকা' --data 'lang=bn' --data 'limit=5' | jq
```

Health:

```bash
curl -sS 'http://127.0.0.1:5000/api/v1/health' | jq
curl -sS 'http://127.0.0.1:5000/api/v1/health/ready' | jq
```

Load the admin token for the following commands:

```bash
export SEARCH_INDEX_ADMIN_TOKEN="$(sed -n 's/^SEARCH_INDEX_ADMIN_TOKEN=//p' .env)"
```

Check availability without Redis or queueing:

```bash
curl -sS 'http://127.0.0.1:5000/api/v1/admin/search-index-updates/availability' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" | jq
```

Update only when Geofabrik is newer:

```bash
curl -sS -X POST 'http://127.0.0.1:5000/api/v1/admin/search-index-updates' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" \
  -H "Idempotency-Key: $(openssl rand -hex 16)" | jq
```

Force an update attempt without the availability precheck:

```bash
curl -sS -X POST 'http://127.0.0.1:5000/api/v1/admin/search-index-updates/force' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" \
  -H "Idempotency-Key: $(openssl rand -hex 16)" | jq
```

Force means the worker always runs Nominatim catch-up. Photon is still skipped
when Nominatim's sequence does not advance.

Inspect a queued job:

```bash
curl -sS 'http://127.0.0.1:5000/api/v1/admin/search-index-updates/JOB_ID' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" | jq
```

## Development

```bash
npm run dev
npm test
```

For a 1,000-concurrent-request smoke load test:

```bash
npx autocannon -c 1000 -d 30 -t 20 \
  'http://127.0.0.1:5000/api/v1/places/search?q=Dhaka&lang=en&limit=5'
```

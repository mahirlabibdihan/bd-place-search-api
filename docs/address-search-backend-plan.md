# Bangladesh Photon Backend Setup

Focused runbook from Bangladesh OSM data to autocomplete:

```text
Geofabrik .osm.pbf -> Nominatim PostgreSQL -> Photon index
 -> Node API autocomplete -> user selection -> PostGIS postcode lookup
```

Photon cannot import PBF directly. Nominatim is private build/update
infrastructure; the application queries Photon only.

## 1. Environment

Use Ubuntu 24.04, NVMe, Java 21, Node.js 22, PostgreSQL/PostGIS, and Redis.
For a pilot, start near 8 CPU, 32 GB RAM, and 150 GB free disk, then measure.

| Service | Private endpoint |
| --- | --- |
| Photon | `127.0.0.1:2322` |
| Nominatim DB | `127.0.0.1:5432/nominatim` |
| BPO PostGIS | `127.0.0.1:5432/bpo_postcode` |
| Redis | `127.0.0.1:6379` |
| Node API | `127.0.0.1:5000` |

Examples pin Nominatim 5.3.2 and Photon 1.2.1. Verify compatibility before
upgrading.

## 2. Install dependencies

```bash
sudo apt update
sudo apt install -y postgresql postgresql-postgis \
  postgresql-postgis-scripts osm2pgsql pkg-config libicu-dev \
  python3-venv python3-pip openjdk-21-jre-headless \
  curl wget jq bzip2 ca-certificates
```

Install Node.js 22 LTS separately.

## 3. Install Nominatim

```bash
sudo useradd --create-home --home-dir /srv/nominatim --shell /bin/bash nominatim
sudo -u nominatim python3 -m venv /srv/nominatim/venv
sudo -u nominatim /srv/nominatim/venv/bin/pip install --upgrade pip
sudo -u nominatim /srv/nominatim/venv/bin/pip install \
  'nominatim-db==5.3.2' 'psycopg[binary]' osmium
sudo install -d -o nominatim -g nominatim \
  /srv/nominatim/project /srv/nominatim/data /srv/nominatim/log
sudo -u postgres createuser --superuser nominatim
sudo -u postgres createdb --owner=nominatim nominatim
```

Create `/srv/nominatim/project/.env`, owner `nominatim`, mode `0600`:

```dotenv
NOMINATIM_DATABASE_DSN=pgsql:dbname=nominatim;user=nominatim
NOMINATIM_TOKENIZER=icu
NOMINATIM_REPLICATION_URL=https://download.geofabrik.de/asia/bangladesh-updates
NOMINATIM_REPLICATION_UPDATE_INTERVAL=86400
NOMINATIM_REPLICATION_RECHECK_INTERVAL=900
```

Verify the replication URL and interval against Geofabrik before production.

## 4. Download and import Bangladesh

```bash
sudo -u nominatim wget -O /srv/nominatim/data/bangladesh-latest.osm.pbf \
  https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf
sudo -u nominatim wget -O /srv/nominatim/data/bangladesh-latest.osm.pbf.md5 \
  https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf.md5
cd /srv/nominatim/data
md5sum --check bangladesh-latest.osm.pbf.md5
sha256sum bangladesh-latest.osm.pbf

cd /srv/nominatim/project
sudo -u nominatim /srv/nominatim/venv/bin/nominatim import \
  --osm-file /srv/nominatim/data/bangladesh-latest.osm.pbf \
  --reverse-only 2>&1 | sudo tee /srv/nominatim/log/import.log
sudo -u nominatim /srv/nominatim/venv/bin/nominatim admin --check-database
sudo -u nominatim /srv/nominatim/venv/bin/nominatim replication --init
```

`--reverse-only` is suitable when Nominatim only feeds Photon. Do not use
`--no-updates`, because Photon updates require Nominatim's update data.

## 5. Install Photon

```bash
sudo useradd --system --home /srv/photon --shell /usr/sbin/nologin photon
sudo install -d -o photon -g photon \
  /srv/photon/releases /srv/photon/builds /srv/photon/current
sudo -u photon wget -O /srv/photon/releases/photon-1.2.1.jar \
  https://github.com/komoot/photon/releases/download/1.2.1/photon-1.2.1.jar
sha256sum /srv/photon/releases/photon-1.2.1.jar
java -jar /srv/photon/releases/photon-1.2.1.jar import -h
```

Verify the JAR checksum against an approved value.

## 6. Give Photon read access

```bash
sudo -u postgres createuser --pwprompt photon_import
sudo -u postgres psql -d nominatim -c \
  'CREATE INDEX IF NOT EXISTS placex_country_code_idx ON placex(country_code)'
sudo -u postgres psql -d nominatim -c \
  'GRANT USAGE ON SCHEMA public TO photon_import'
sudo -u postgres psql -d nominatim -c \
  'GRANT SELECT ON ALL TABLES IN SCHEMA public TO photon_import'
```

Allow only authenticated local access in `pg_hba.conf`. Store the password in
`/srv/photon/.pgpass`, owner `photon`, mode `0600`; never pass it in commands.

## 7. Build the Bangladesh Photon index

Pause Nominatim replication during the import.

```bash
sudo -u photon mkdir -p /srv/photon/builds/bd-initial
cd /srv/photon/builds/bd-initial
sudo -u photon java -Xms8g -Xmx8g \
  -jar /srv/photon/releases/photon-1.2.1.jar import \
  -host 127.0.0.1 -port 5432 -database nominatim -user photon_import \
  -languages en,bn -country-codes bd \
  -data-dir /srv/photon/builds/bd-initial/photon_data
```

Do not use Photon's `-reverse-only`; this product needs forward autocomplete.
Promote the tested build to `/srv/photon/current`. Never import over a live index.

## 8. Run and test Photon

```bash
sudo -u photon java -Xms8g -Xmx8g \
  -jar /srv/photon/releases/photon-1.2.1.jar serve \
  -data-dir /srv/photon/current/photon_data \
  -listen-ip 127.0.0.1 -listen-port 2322 \
  -default-language bn -metrics-enable
```

Use this command in a systemd service with `User=photon`, `Restart=on-failure`,
memory limits, and the private bind address.

```bash
curl --get 'http://127.0.0.1:2322/api' \
  --data-urlencode 'q=ধানমন্ডি ঢাকা' --data 'lang=bn' --data 'limit=5'
curl --get 'http://127.0.0.1:2322/api' \
  --data-urlencode 'q=Dhanmondi Dhaka' --data 'lang=en' --data 'limit=5'
```

Results must be in Bangladesh. GeoJSON coordinates are `[longitude, latitude]`.

## 9. Updates

Initialize Photon tracking once:

```bash
sudo -u photon java -jar /srv/photon/releases/photon-1.2.1.jar update-init \
  -host 127.0.0.1 -port 5432 -database nominatim -user nominatim \
  -import-user photon_import
```

The fixed `bangladesh-latest.osm.pbf` URL always downloads the newest complete
snapshot. Do not download and re-import it every day. Use it only for the initial
import, disaster recovery, or a periodic clean rebuild. Routine updates should use
the smaller Geofabrik replication diffs configured in Nominatim.

For a manual update window, stop Photon, update Nominatim, then update Photon with
the same filters used at import:

```bash
cd /srv/nominatim/project
sudo -u nominatim /srv/nominatim/venv/bin/nominatim replication --once
cd /srv/photon/current
sudo -u photon java -jar /srv/photon/releases/photon-1.2.1.jar update \
  -host 127.0.0.1 -port 5432 -database nominatim -user photon_import \
  -languages en,bn -country-codes bd \
  -data-dir /srv/photon/current/photon_data
```

Never update Nominatim and Photon concurrently. If using Photon's live update API,
never expose `/nominatim-update` publicly.

### Automatic background update

Run the update on a schedule (daily is a reasonable starting point) and optionally
allow an administrator to trigger the same job through the backend:

```http
POST /api/v1/admin/search-index-updates
Authorization: Bearer <admin-token>
Idempotency-Key: <unique-value>

202 Accepted
{ "jobId": "...", "status": "queued" }
```

Status endpoint:

```http
GET /api/v1/admin/search-index-updates/{jobId}
```

The HTTP handler must only validate authorization and enqueue a durable BullMQ
job. Do not run imports or spawn a detached shell process inside the API process.
A dedicated worker performs these steps:

1. acquire a Redis lock such as `search-index-update` so only one job can run;
2. record the starting Nominatim and Photon dataset timestamps;
3. run `nominatim replication --once` and wait for success;
4. run the Photon `update` command while Photon is stopped, or call Photon's
   private update endpoint when live updates are enabled;
5. run English and Bangla smoke searches;
6. record completion, timestamps, duration, and logs;
7. release the lock and invalidate autocomplete cache keys.

Use states `queued`, `updating_nominatim`, `updating_photon`, `verifying`,
`succeeded`, and `failed`. A duplicate request should return the active job rather
than start another update. Set a hard timeout, retain bounded logs, alert on
failure, and never automatically retry a failed import indefinitely.

For zero-downtime incremental updates, start Photon `serve` with
`-enable-update-api`, its Nominatim connection options, and the same
`-languages en,bn -country-codes bd` filters. The worker then calls only the
private `http://127.0.0.1:2322/nominatim-update`, polls
`/nominatim-update/status` until it returns `OK`, and performs smoke tests. Firewall
and reverse-proxy rules must block both update paths from public access.

A separate, less frequent clean-rebuild job may download the fixed latest PBF,
build new Nominatim and Photon stores beside the live stores, verify them, and
atomically switch services. Never overwrite live databases or indexes in place.

## 10. Node API environment

```dotenv
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://bpo_api:REDACTED@127.0.0.1:5432/bpo_postcode
PHOTON_BASE_URL=http://127.0.0.1:2322
PHOTON_CONNECT_TIMEOUT_MS=500
PHOTON_REQUEST_TIMEOUT_MS=2000
PHOTON_RESULT_LIMIT=5
PLACE_SEARCH_MIN_CHARS=2
REDIS_URL=redis://127.0.0.1:6379/0
SEARCH_INDEX_UPDATE_CRON="0 3 * * *"
SEARCH_INDEX_UPDATE_ENABLED=true
SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS=7200
PLACE_SUGGESTION_CACHE_TTL_SECONDS=14400
SUGGESTION_TOKEN_SECRET=REDACTED-AT-LEAST-32-RANDOM-BYTES
SUGGESTION_TOKEN_TTL_SECONDS=900
```

The API returns Photon suggestions and coordinates. Only after selection does it
run PostGIS `ST_Covers` against the published postcode boundary.

## 11. Acceptance checklist

- Nominatim database check passes and replication is initialized.
- Photon starts without index errors.
- English and Bangla queries return Bangladesh results with coordinates.
- Photon and database ports are private.
- Versions, checksums, import log, and timestamps are recorded.
- Scheduled and admin-triggered update jobs cannot overlap.
- Failed updates retain the previous usable Photon index and expose job logs.
- The API reaches Photon, Redis, and BPO PostGIS.
- A selected coordinate resolves against a test postcode boundary.

## References

- [Photon usage](https://github.com/komoot/photon/blob/master/docs/usage.md)
- [Photon API](https://github.com/komoot/photon/blob/master/docs/api-v1.md)
- [Nominatim import](https://nominatim.org/release-docs/latest/admin/Import/)
- [Nominatim updates](https://nominatim.org/release-docs/latest/admin/Update/)
- [Geofabrik Bangladesh](https://download.geofabrik.de/asia/bangladesh.html)

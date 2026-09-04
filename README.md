# Bangladesh Place Search Backend

This repository has two parts:

1. a private Bangladesh Photon search engine built from OpenStreetMap data;
2. a standalone Express API that exposes text search and manages background
   Nominatim/Photon updates.

Photon returns coordinates as `[longitude, latitude]`. After a caller selects a
place, this service's responsibility ends; spatial business logic belongs to
downstream services.

# 1. Set up the Photon search engine

The data flow is:

```text
Geofabrik .osm.pbf -> Nominatim PostgreSQL -> Photon/OpenSearch index
```

These commands target Ubuntu 24.04, Nominatim 5.3.2, Photon 1.2.1, Java 21,
and Bangladesh data. Nominatim and Photon should remain bound to localhost.

## Automated setup

For a new installation, configure everything in the repository's ignored `.env`
and run one setup script:

```bash
cp .env.example .env
nano .env
sudo bash scripts/setup-all.sh
bash scripts/run-stack.sh
```

At minimum, replace these values in `.env`:

```dotenv
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DB=nominatim
DB_ADMIN_USER=postgres
DB_ADMIN_PASS=
NOMINATIM_DB_USER=nominatim
NOMINATIM_DB_PASS=replace-with-a-strong-password
PHOTON_DB_USER=photon_import
PHOTON_DB_PASS=replace-with-a-strong-password
```

For local PostgreSQL peer authentication, leave `DB_ADMIN_PASS` empty. For a
remote database, set `DB_HOST`, `DB_ADMIN_USER`, and `DB_ADMIN_PASS`. Quote values
containing shell-special characters because the setup script sources `.env`.
`setup-all.sh` installs the search engine, system Node.js 22, Redis, and npm
dependencies. `run-stack.sh` starts Photon, the Express API, and the update worker
together and stops the remaining processes if one exits. The installer creates
the database roles and password files. Interrupted setup is resumable: a valid
Nominatim database is reused, while a stale Photon build is archived with a UTC
timestamp before a fresh index is created. Before building Photon, setup applies
all currently published Geofabrik diffs so a new installation starts current.

When testing in a second WSL distribution while the original one is running,
PostgreSQL may select another port because WSL distributions share localhost.
The installer detects this and reports the correct port. Use a separate config:

```bash
cp .env .env.test
sed -i 's/^DB_PORT=.*/DB_PORT=5433/' .env.test  # use the port reported by the script
sudo bash scripts/setup-all.sh .env.test
bash scripts/run-stack.sh .env.test
```

The individual scripts remain available when only one part is needed:

```bash
sudo bash scripts/setup-search-engine.sh  # Nominatim and Photon
sudo bash scripts/setup-backend.sh        # Node.js, Redis and npm packages
bash scripts/run-photon.sh                # Photon only
bash scripts/run-stack.sh                 # Photon, API and worker
```

To completely reset only this stack and test installation again:

```bash
sudo bash scripts/reset-all.sh
sudo bash scripts/setup-all.sh
bash scripts/run-stack.sh
```

The reset script displays the active WSL distribution and exact deletion scope,
then requires typing its confirmation phrase. It preserves the Windows repository,
`.env`, and `node_modules`. Use `--yes` only in disposable automated test distros.

The remaining section documents the equivalent manual steps and troubleshooting.

## 1.1 Install system dependencies

```bash
sudo apt update
sudo apt install -y postgresql postgresql-postgis \
  postgresql-postgis-scripts osm2pgsql pkg-config libicu-dev \
  python3-venv python3-pip openjdk-21-jre-headless \
  curl wget jq bzip2 ca-certificates
```

## 1.2 Install Nominatim

```bash
sudo useradd --create-home --home-dir /srv/nominatim --shell /bin/bash nominatim
sudo install -d -o nominatim -g nominatim \
  /srv/nominatim/project /srv/nominatim/data /srv/nominatim/log
sudo -u nominatim python3 -m venv /srv/nominatim/venv
sudo -u nominatim /srv/nominatim/venv/bin/pip install --upgrade pip
sudo -u nominatim /srv/nominatim/venv/bin/pip install \
  'nominatim-db==5.3.2' 'psycopg[binary]' osmium
sudo -u postgres createuser --superuser nominatim
sudo -u postgres createuser www-data
```

Do not pre-create the `nominatim` database. `nominatim import` creates it, and an
empty pre-created database causes `database already exists` followed by a version
mismatch.

Create the Nominatim project configuration:

```bash
sudo install -m 0600 -o nominatim -g nominatim /dev/null \
  /srv/nominatim/project/.env
sudo -u nominatim nano /srv/nominatim/project/.env
```

```dotenv
NOMINATIM_DATABASE_DSN=pgsql:dbname=nominatim;user=nominatim
NOMINATIM_TOKENIZER=icu
NOMINATIM_REPLICATION_URL=https://download.geofabrik.de/asia/bangladesh-updates
NOMINATIM_REPLICATION_UPDATE_INTERVAL=86400
NOMINATIM_REPLICATION_RECHECK_INTERVAL=900
```

## 1.3 Download and import Bangladesh

```bash
sudo -u nominatim wget -O /srv/nominatim/data/bangladesh-latest.osm.pbf \
  https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf
sudo -u nominatim wget -O /srv/nominatim/data/bangladesh-latest.osm.pbf.md5 \
  https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf.md5

cd /srv/nominatim/data
md5sum --check bangladesh-latest.osm.pbf.md5
sha256sum bangladesh-latest.osm.pbf

cd /srv/nominatim/project
set -o pipefail
sudo -u nominatim /srv/nominatim/venv/bin/nominatim import \
  --osm-file /srv/nominatim/data/bangladesh-latest.osm.pbf \
  --reverse-only 2>&1 | sudo tee /srv/nominatim/log/import.log

sudo -u nominatim /srv/nominatim/venv/bin/nominatim admin --check-database
sudo -u nominatim /srv/nominatim/venv/bin/nominatim replication --init
```

`--reverse-only` is appropriate because Nominatim feeds Photon rather than serving
forward search itself. Do not use `--no-updates`.

Nominatim persists the replication source selected by `replication --init`.
Changing `NOMINATIM_REPLICATION_URL` later does not switch an initialized database
until initialization is run again. Verify the project setting:

```bash
sudo -u nominatim sed -n '/^NOMINATIM_REPLICATION_/p' \
  /srv/nominatim/project/.env
```

For this Bangladesh installation, the URL must be:

```dotenv
NOMINATIM_REPLICATION_URL=https://download.geofabrik.de/asia/bangladesh-updates
```

After changing the URL, stop the update worker, wait until no replication command
is running, and reinitialize from the Nominatim project directory:

```bash
pgrep -af '[n]ominatim replication'
pgrep -af '[s]earchIndexUpdateWorker'

sudo -u nominatim bash -c '
  cd /srv/nominatim/project &&
  /srv/nominatim/venv/bin/nominatim replication --init
'

sudo -u postgres psql -d nominatim -c \
  'SELECT sequence_id, lastimportdate FROM import_status'
```

With Geofabrik Bangladesh updates, `sequence_id` must be in the same regional
namespace as `bangladesh-updates/state.txt` (for example, around `4867`), not the
global OSM minutely namespace (for example, around `7271751`).

## 1.4 Install Photon and grant database access

```bash
sudo useradd --system --home /srv/photon --shell /usr/sbin/nologin photon
sudo install -d -o photon -g photon \
  /srv/photon/releases /srv/photon/builds /srv/photon/current
sudo -u photon wget -O /srv/photon/releases/photon-1.2.1.jar \
  https://github.com/komoot/photon/releases/download/1.2.1/photon-1.2.1.jar
sha256sum /srv/photon/releases/photon-1.2.1.jar

sudo -u postgres createuser --pwprompt photon_import
sudo -u postgres psql -d nominatim -c \
  'CREATE INDEX IF NOT EXISTS placex_country_code_idx ON placex(country_code)'
sudo -u postgres psql -d nominatim -c \
  'GRANT USAGE ON SCHEMA public TO photon_import'
sudo -u postgres psql -d nominatim -c \
  'GRANT SELECT ON ALL TABLES IN SCHEMA public TO photon_import'
```

If the last grant reports `tuple concurrently updated`, wait for the Nominatim
import to finish and run that grant again.

Allow authenticated localhost access for `photon_import` in `pg_hba.conf`. Store
its password without putting the secret in a shell command:

```bash
sudo install -m 0600 -o photon -g photon /dev/null /srv/photon/.pgpass
sudo -u photon nano /srv/photon/.pgpass
```

Enter this line, replacing `PASSWORD`:

```text
127.0.0.1:5432:nominatim:photon_import:PASSWORD
```

Verify permissions:

```bash
sudo stat -c '%U %G %a %n' /srv/photon/.pgpass
```

## 1.5 Build and prepare the Photon index

Pause Nominatim replication while performing the initial Photon import.

```bash
sudo -u photon mkdir -p /srv/photon/builds/bd-initial
cd /srv/photon/builds/bd-initial
sudo -u photon java -Xms1g -Xmx3g \
  -jar /srv/photon/releases/photon-1.2.1.jar import \
  -host 127.0.0.1 -port 5432 -database nominatim -user photon_import \
  -languages en,bn -country-codes bd \
  -data-dir /srv/photon/builds/bd-initial
```

Photon automatically creates a `photon_data` child inside `-data-dir`. Promote
the verified index with a symlink instead of copying or importing over it:

```bash
sudo -u photon ln -sfnT \
  /srv/photon/builds/bd-initial/photon_data \
  /srv/photon/current/photon_data

readlink -f /srv/photon/current/photon_data
sudo du -shL /srv/photon/current/photon_data
```

The resolved path must be
`/srv/photon/builds/bd-initial/photon_data`. If `ln` reports that the target is a
real directory rather than a symlink, stop and inspect it; do not delete or
overwrite an unknown index.

Photon update initialization needs a database owner connection over TCP. Set a
password for `nominatim` and store it in that operating-system user's password
file without putting the secret in a command:

```bash
sudo -u postgres psql -c '\password nominatim'
sudo install -m 0600 -o nominatim -g nominatim /dev/null \
  /srv/nominatim/.pgpass
sudo -u nominatim nano /srv/nominatim/.pgpass
```

Enter this line, replacing `PASSWORD`:

```text
127.0.0.1:5432:nominatim:nominatim:PASSWORD
```

Then initialize Photon's Nominatim update tracking once:

```bash
sudo -u nominatim java \
  -jar /srv/photon/releases/photon-1.2.1.jar update-init \
  -host 127.0.0.1 -port 5432 -database nominatim -user nominatim \
  -import-user photon_import
```

This creates the tracking tables/triggers and grants the required update rights
to `photon_import`. It must finish before Photon starts with `-enable-update-api`.

## 1.6 Run Photon

```bash
sudo -u photon java -Xms1g -Xmx3g \
  -jar /srv/photon/releases/photon-1.2.1.jar serve \
  -data-dir /srv/photon/current \
  -listen-ip 127.0.0.1 -listen-port 2322 \
  -default-language bn -metrics-enable prometheus \
  -enable-update-api \
  -host 127.0.0.1 -port 5432 -database nominatim \
  -user photon_import -languages en,bn -country-codes bd
```

Always pass the parent directory to `-data-dir`. Passing
`/srv/photon/current/photon_data` makes Photon look for the incorrect nested path
`/srv/photon/current/photon_data/photon_data`.

Test Photon inside WSL:

```bash
curl --get 'http://127.0.0.1:2322/api' \
  --data-urlencode 'q=Dhaka' --data 'lang=en' --data 'limit=5' | jq
curl --get 'http://127.0.0.1:2322/api' \
  --data-urlencode 'q=ঢাকা' --data 'lang=bn' --data 'limit=5' | jq
curl -sS 'http://127.0.0.1:2322/nominatim-update/status'
```

Photon 1.2.1 returns plain-text `BUSY` or `OK` from the status endpoint. The
worker supports these responses as well as JSON forms.


# 2. Set up and run the backend

## 2.1 Install Node.js and Redis

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install 22
nvm alias default 22
nvm use 22

sudo apt update
sudo apt install -y redis-server
sudo systemctl enable --now redis-server
redis-cli ping
```

Redis is optional for text search. If Redis is down, search remains available,
readiness reports `searchIndexUpdates: disabled`, and update requests fail quickly
with HTTP 503. The feature reconnects when Redis returns.

## 2.2 Configure the application

```bash
cd /mnt/c/Users/Asus/Documents/BPO/bpo-postcode-backend
cp .env.example .env
npm install
openssl rand -hex 32
nano .env
```

Put the generated value in `SEARCH_INDEX_ADMIN_TOKEN`. Never commit `.env`.

## 2.3 Configure the availability check

The availability endpoint compares Nominatim's local `lastimportdate` with
Geofabrik's current data timestamp. It deliberately uses timestamps because a
misconfigured Nominatim database may use the global OSM sequence namespace while
Geofabrik's `sequenceNumber` is regional. Create a narrowly scoped PostgreSQL login:

```bash
sudo -u postgres createuser --pwprompt place_search_status
sudo -u postgres psql -d nominatim -c \
  'GRANT CONNECT ON DATABASE nominatim TO place_search_status'
sudo -u postgres psql -d nominatim -c \
  'GRANT USAGE ON SCHEMA public TO place_search_status'
sudo -u postgres psql -d nominatim -c \
  'GRANT SELECT ON TABLE import_status TO place_search_status'

sudo install -d -m 0700 -o "$USER" -g "$USER" /srv/place-search
sudo install -m 0600 -o "$USER" -g "$USER" /dev/null \
  /srv/place-search/.pgpass
nano /srv/place-search/.pgpass
```

Enter this line, replacing `PASSWORD`:

```text
127.0.0.1:5432:nominatim:place_search_status:PASSWORD
```

Configure the API and worker with the same database connection:

```dotenv
DB_USER=place_search_status
DB_HOST=127.0.0.1
DB_PASS=
DB_DB=nominatim
DB_PORT=5432
DB_SSL=false
DB_PGPASSFILE=/srv/place-search/.pgpass
```

Leave `DB_PASS` empty to load the password from `DB_PGPASSFILE`. For a remote
database, change `DB_HOST`, set `DB_SSL=true`, and use the remote hostname in
`.pgpass`. These settings configure the Node API and worker; Nominatim itself
continues to use `/srv/nominatim/project/.env`.

## 2.4 Run the API and worker

Terminal 1 - the API:

```bash
cd /mnt/c/Users/Asus/Documents/BPO/bpo-postcode-backend
npm start
```

Terminal 2 - the worker. Use system Node because the `nominatim` user normally
cannot traverse another user's nvm installation:

```bash
sudo -u nominatim /usr/bin/node \
  /mnt/c/Users/Asus/Documents/BPO/bpo-postcode-backend/workers/searchIndexUpdateWorker.js
```

The worker reads `import_status.sequence_id` before and after Nominatim
replication. When it is unchanged, the job completes with `outcome: no_changes`
and does not call Photon. The POST endpoint also returns `status: no_changes`
without queuing when the availability check is false. When an update exists, the
worker uses `replication --catch-up`, which checks immediately and applies all
available diffs without `--once` sleeping until the daily publication window.
`DB_USER`, `DB_HOST`, `DB_PASS`, `DB_DB`, `DB_PORT`, `DB_SSL`, and
`DB_PGPASSFILE` configure database access for both the API and worker.

Always run manual Nominatim replication from its project directory:

```bash
sudo -u nominatim bash -c '
  cd /srv/nominatim/project &&
  /srv/nominatim/venv/bin/nominatim replication --catch-up
'
```

For production, run Photon, the API, and the worker as separate systemd services.

## 2.5 Test the API

English and Bangla search:

```bash
curl --get 'http://127.0.0.1:5000/api/v1/places/suggestions' \
  --data-urlencode 'q=Dhaka' --data 'lang=en' --data 'limit=5' | jq

curl --get 'http://127.0.0.1:5000/api/v1/places/search' \
  --data-urlencode 'q=ঢাকা' --data 'lang=bn' --data 'limit=5' | jq
```

Check whether Geofabrik has newer data:

```bash
curl -sS \
  'http://127.0.0.1:5000/api/v1/admin/search-index-updates/availability' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" | jq
```

The response includes `updateAvailable`, `localImportDate`,
`remoteDataTimestamp`, `remoteRegionalSequence`, and `checkedAt`. This check does not require Redis.

Update only when Geofabrik has newer data:

```bash
curl -sS -X POST 'http://127.0.0.1:5000/api/v1/admin/search-index-updates' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" \
  -H "Idempotency-Key: $(openssl rand -hex 16)" | jq
```

This endpoint checks availability first. It returns `status: no_changes` without
creating a job when the local import is current.

Force an update attempt without the availability check:

```bash
curl -sS -X POST \
  'http://127.0.0.1:5000/api/v1/admin/search-index-updates/force' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" \
  -H "Idempotency-Key: $(openssl rand -hex 16)" | jq
```

The force endpoint always queues the worker. The worker runs Nominatim catch-up,
but still avoids calling Photon when Nominatim's sequence does not advance.

Inspect a queued job:

```bash
curl -sS \
  'http://127.0.0.1:5000/api/v1/admin/search-index-updates/JOB_ID' \
  -H "Authorization: Bearer $SEARCH_INDEX_ADMIN_TOKEN" | jq
```

Health:

```bash
curl -i 'http://127.0.0.1:5000/api/v1/health'
curl -i 'http://127.0.0.1:5000/api/v1/health/ready'
```

When Photon is down, search returns HTTP 503:

```json
{ "error": "Place search is temporarily unavailable" }
```

## 2.6 Replication troubleshooting

Use the API availability endpoint before requesting an update. Do not invoke
`replication --once` for an on-demand check against Geofabrik: it respects
`NOMINATIM_REPLICATION_UPDATE_INTERVAL=86400` and may print:

```text
Sleeping for ... sec before next update.
```

Do not override the interval with `0`. Nominatim rejects that for Geofabrik with:

```text
Update interval too low for download.geofabrik.de.
FATAL: Invalid replication update interval setting.
```

The backend avoids both cases: POST checks the upstream timestamp before queuing,
and the worker uses `replication --catch-up` only when newer data exists.

If `sequenceBefore` is around `727xxxx`, Nominatim is using the global OSM
minutely namespace. For this setup it should be near Geofabrik's Bangladesh
regional sequence, such as `4867`. Verify `.env`, stop all update processes, and
rerun `replication --init` as described in section 1.3.

A BullMQ job with `status: waiting` is only queued. Confirm Redis and the worker:

```bash
redis-cli ping
pgrep -af '[s]earchIndexUpdateWorker'
```

Generating a fresh `Idempotency-Key` intentionally creates a different job.
Reuse the same key when retrying the same request.

## 2.7 Updates, recovery, and production checks

The fixed `bangladesh-latest.osm.pbf` URL is for initial installation, disaster
recovery, or an occasional clean rebuild. Do not download and re-import the full
PBF for routine updates. Use the configured Geofabrik replication diffs instead.

The update sequence is:

1. the worker reads Nominatim's current replication sequence;
2. Nominatim applies available `.osc.gz` diffs;
3. if the sequence did not advance, the job finishes without calling Photon;
4. if it advanced, the worker triggers Photon's private update API;
5. the worker waits for `OK` and runs English and Bangla smoke searches.

Operational rules:

- Keep PostgreSQL, Photon, Redis, and the update endpoints private.
- Do not run Nominatim and Photon update operations concurrently.
- Do not import over a live Photon index; build beside it and switch after checks.
- Keep `.env` and all `.pgpass` files at mode `0600` and out of Git.
- Use bounded job retention and no automatic infinite retry of failed imports.
- Back up configuration and record the PBF checksum, import date, and versions.

Acceptance checklist:

- `nominatim admin --check-database` succeeds and replication is initialized.
- Photon starts without index errors and `/nominatim-update/status` returns `OK`.
- English and Bangla searches return Bangladesh results with coordinates.
- Text search still works when Redis is stopped; update endpoints return 503.
- Photon outages produce a clear search 503 response.
- Duplicate update requests cannot run overlapping update jobs.
- An unchanged replication sequence completes with `outcome: no_changes`.

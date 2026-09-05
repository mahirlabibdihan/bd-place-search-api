FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl sudo supervisor openssl postgresql postgresql-postgis postgresql-postgis-scripts osm2pgsql build-essential pkg-config libicu-dev python3-venv python3-pip python3-dev openjdk-21-jre-headless wget jq bzip2 redis-server && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --home-dir /srv/nominatim --shell /bin/bash nominatim \
 && useradd --system --create-home --home-dir /srv/photon --shell /usr/sbin/nologin photon

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
RUN chmod +x docker/entrypoint.sh scripts/*.sh && mkdir -p /var/log/place-search
EXPOSE 5000
VOLUME ["/var/lib/postgresql", "/srv/nominatim", "/srv/photon"]
ENTRYPOINT ["/app/docker/entrypoint.sh"]

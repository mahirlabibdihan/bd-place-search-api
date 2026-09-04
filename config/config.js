require("dotenv").config();

const numberFromEnv = (name, fallback) => {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
};

module.exports = {
  NODE_ENV: process.env.NODE_ENV || "development",
  PORT: numberFromEnv("PORT", 5000),
  PHOTON_BASE_URL: process.env.PHOTON_BASE_URL || "http://127.0.0.1:2322",
  PHOTON_REQUEST_TIMEOUT_MS: numberFromEnv("PHOTON_REQUEST_TIMEOUT_MS", 2000),
  PHOTON_RESULT_LIMIT: numberFromEnv("PHOTON_RESULT_LIMIT", 5),
  PLACE_SEARCH_MIN_CHARS: numberFromEnv("PLACE_SEARCH_MIN_CHARS", 2),
  REDIS_URL: process.env.REDIS_URL || "redis://127.0.0.1:6379/0",
  REDIS_CONNECT_TIMEOUT_MS: numberFromEnv("REDIS_CONNECT_TIMEOUT_MS", 1000),
  SEARCH_INDEX_ADMIN_TOKEN: process.env.SEARCH_INDEX_ADMIN_TOKEN || "",
  SEARCH_INDEX_UPDATE_ENABLED: process.env.SEARCH_INDEX_UPDATE_ENABLED !== "false",
  SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS: numberFromEnv("SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS", 7200),
  NOMINATIM_PROJECT_DIR: process.env.NOMINATIM_PROJECT_DIR || "/srv/nominatim/project",
  NOMINATIM_BIN: process.env.NOMINATIM_BIN || "/srv/nominatim/venv/bin/nominatim",
  DB_USER: process.env.DB_USER || "place_search_status",
  DB_HOST: process.env.DB_HOST || "127.0.0.1",
  DB_PASS: process.env.DB_PASS || "",
  DB_DB: process.env.DB_DB || "nominatim",
  DB_PORT: numberFromEnv("DB_PORT", 5432),
  DB_SSL: process.env.DB_SSL === "true",
  DB_PGPASSFILE: process.env.DB_PGPASSFILE || "/srv/place-search/.pgpass",
  GEOFABRIK_REPLICATION_STATE_URL: process.env.GEOFABRIK_REPLICATION_STATE_URL || "https://download.geofabrik.de/asia/bangladesh-updates/state.txt",
  PHOTON_UPDATE_URL: process.env.PHOTON_UPDATE_URL || "http://127.0.0.1:2322/nominatim-update",
  PHOTON_UPDATE_STATUS_URL: process.env.PHOTON_UPDATE_STATUS_URL || "http://127.0.0.1:2322/nominatim-update/status",
};


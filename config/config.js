require("dotenv").config();

const numberFromEnv = (name, fallback) => {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
};

const withoutTrailingSlash = (value) => value.replace(/\/+$/, "");
const PHOTON_BASE_URL = withoutTrailingSlash(
  process.env.PHOTON_BASE_URL || "http://127.0.0.1:2322",
);
const NOMINATIM_REPLICATION_URL = withoutTrailingSlash(
  process.env.NOMINATIM_REPLICATION_URL
    || "https://download.geofabrik.de/asia/bangladesh-updates",
);

module.exports = {
  NODE_ENV: process.env.NODE_ENV || "development",
  HOST: process.env.HOST || "127.0.0.1",
  PORT: numberFromEnv("PORT", 5001),
  CORS_ALLOWED_ORIGINS: (
    process.env.CORS_ALLOWED_ORIGINS
      || "http://127.0.0.1:5173,http://localhost:5173"
  )
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
  PHOTON_BASE_URL,
  PHOTON_REQUEST_TIMEOUT_MS: numberFromEnv("PHOTON_REQUEST_TIMEOUT_MS", 2000),
  PLACE_SEARCH_DEFAULT_LIMIT: numberFromEnv("PLACE_SEARCH_DEFAULT_LIMIT", 5),
  PLACE_SEARCH_MAX_LIMIT: numberFromEnv("PLACE_SEARCH_MAX_LIMIT", 20),
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
  NOMINATIM_REPLICATION_URL,
  GEOFABRIK_REPLICATION_STATE_URL: `${NOMINATIM_REPLICATION_URL}/state.txt`,
  PHOTON_UPDATE_URL: `${PHOTON_BASE_URL}/nominatim-update`,
  PHOTON_UPDATE_STATUS_URL: `${PHOTON_BASE_URL}/nominatim-update/status`,
};
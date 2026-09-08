const { Pool } = require("pg");
const { DB_DB, DB_HOST, DB_PORT, DB_SSL, DB_USER, PHOTON_REQUEST_TIMEOUT_MS } = require("../config/config");
const { databasePassword } = require("../utils/databaseConfig");

const pool = new Pool({
  host: DB_HOST,
  port: DB_PORT,
  database: DB_DB,
  user: DB_USER,
  password: databasePassword,
  ssl: DB_SSL ? { rejectUnauthorized: true } : false,
  connectionTimeoutMillis: PHOTON_REQUEST_TIMEOUT_MS,
  idleTimeoutMillis: 10000,
  max: 2,
});

pool.on("error", (error) => {
  console.error("Unexpected Nominatim status database error", error);
});

// Counts from Nominatim's placex table — the same table Photon indexes from, so these numbers
// are exactly "what an update actually changed." class='highway' covers roads/tracks/paths;
// class='boundary' + type='administrative' covers admin areas (districts, upazilas, etc.).
exports.getStats = async () => {
  try {
    const [places, roads, administrativeAreas, importStatus] = await Promise.all([
      pool.query("SELECT count(*)::int AS count FROM placex"),
      pool.query("SELECT count(*)::int AS count FROM placex WHERE class = 'highway'"),
      pool.query("SELECT count(*)::int AS count FROM placex WHERE class = 'boundary' AND type = 'administrative'"),
      pool.query("SELECT lastimportdate FROM import_status LIMIT 1"),
    ]);
    return {
      totalPlaces: places.rows[0].count,
      roads: roads.rows[0].count,
      administrativeAreas: administrativeAreas.rows[0].count,
      lastImportDate: importStatus.rows[0]?.lastimportdate ? new Date(importStatus.rows[0].lastimportdate).toISOString() : null,
      checkedAt: new Date().toISOString(),
    };
  } catch (cause) {
    const error = new Error("Index stats are temporarily unavailable", { cause });
    error.status = 503;
    error.expose = true;
    throw error;
  }
};

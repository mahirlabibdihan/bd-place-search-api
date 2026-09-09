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
    const result = await pool.query(`
      SELECT
        count(*)::int AS total_places,
        count(*) FILTER (WHERE class = 'highway')::int AS roads,
        count(*) FILTER (
          WHERE class = 'boundary' AND type = 'administrative'
        )::int AS administrative_areas,
        (SELECT lastimportdate FROM import_status LIMIT 1) AS last_import_date
      FROM placex
    `);
    const stats = result.rows[0];
    return {
      totalPlaces: stats.total_places,
      roads: stats.roads,
      administrativeAreas: stats.administrative_areas,
      lastImportDate: stats.last_import_date
        ? new Date(stats.last_import_date).toISOString()
        : null,
      checkedAt: new Date().toISOString(),
    };
  } catch (cause) {
    const error = new Error("Index stats are temporarily unavailable", { cause });
    error.status = 503;
    error.expose = true;
    throw error;
  }
};

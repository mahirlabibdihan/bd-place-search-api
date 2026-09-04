const { Pool } = require("pg");
const {
  DB_DB,
  DB_HOST,
  DB_PORT,
  DB_SSL,
  DB_USER,
  GEOFABRIK_REPLICATION_STATE_URL,
  PHOTON_REQUEST_TIMEOUT_MS,
} = require("../config/config");
const { databasePassword } = require("../utils/databaseConfig");

const connection = {
  host: DB_HOST,
  port: DB_PORT,
  database: DB_DB,
  user: DB_USER,
};

const pool = new Pool({
  ...connection,
  password: databasePassword,
  ssl: DB_SSL ? { rejectUnauthorized: true } : false,
  connectionTimeoutMillis: PHOTON_REQUEST_TIMEOUT_MS,
  idleTimeoutMillis: 10000,
  max: 2,
});

pool.on("error", (error) => {
  console.error("Unexpected Nominatim status database error", error);
});

const parseTimestamp = (value, source) => {
  const date = new Date(String(value).trim().replaceAll("\\:", ":"));
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid ${source} timestamp`);
  return date;
};

const parseGeofabrikState = (text) => {
  const timestamp = String(text).match(/^timestamp=(.+)\s*$/m)?.[1];
  const regionalSequence = String(text).match(/^sequenceNumber=(\d+)\s*$/m)?.[1];
  if (!timestamp || !regionalSequence) {
    throw new Error("Geofabrik state is missing timestamp or sequence number");
  }
  return {
    timestamp: parseTimestamp(timestamp, "Geofabrik"),
    regionalSequence,
  };
};

const getLocalImportDate = async () => {
  const result = await pool.query("SELECT lastimportdate FROM import_status LIMIT 1");
  if (!result.rows[0]?.lastimportdate) {
    throw new Error("Nominatim import status is missing lastimportdate");
  }
  return parseTimestamp(result.rows[0].lastimportdate, "Nominatim import");
};

const getRemoteState = async () => {
  const response = await fetch(GEOFABRIK_REPLICATION_STATE_URL, {
    headers: { accept: "text/plain" },
    signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Geofabrik returned HTTP ${response.status}`);
  return parseGeofabrikState(await response.text());
};

exports.check = async () => {
  try {
    const [localImportDate, remoteState] = await Promise.all([
      getLocalImportDate(),
      getRemoteState(),
    ]);
    return {
      updateAvailable: remoteState.timestamp > localImportDate,
      localImportDate: localImportDate.toISOString(),
      remoteDataTimestamp: remoteState.timestamp.toISOString(),
      remoteRegionalSequence: remoteState.regionalSequence,
      checkedAt: new Date().toISOString(),
    };
  } catch (cause) {
    const error = new Error("Update availability is temporarily unavailable", { cause });
    error.status = 503;
    error.expose = true;
    throw error;
  }
};

exports.parseGeofabrikState = parseGeofabrikState;


const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const {
  GEOFABRIK_REPLICATION_STATE_URL,
  NOMINATIM_PROJECT_DIR,
  NOMINATIM_STATUS_DSN,
  NOMINATIM_STATUS_PGPASSFILE,
  PHOTON_REQUEST_TIMEOUT_MS,
  PSQL_BIN,
} = require("../config/config");
const { parseSequence } = require("../utils/nominatimSequence");

const execFileAsync = promisify(execFile);

const parseGeofabrikState = (text) => {
  const match = String(text).match(/^sequenceNumber=(\d+)\s*$/m);
  if (!match) throw new Error("Geofabrik state does not contain a sequence number");
  return parseSequence(match[1]);
};

const getLocalSequence = async () => {
  const { stdout } = await execFileAsync(PSQL_BIN, [
    "-X",
    "-d",
    NOMINATIM_STATUS_DSN,
    "-Atc",
    "SELECT sequence_id FROM import_status LIMIT 1",
  ], {
    cwd: NOMINATIM_PROJECT_DIR,
    env: { ...process.env, PGPASSFILE: NOMINATIM_STATUS_PGPASSFILE },
    timeout: PHOTON_REQUEST_TIMEOUT_MS,
  });
  return parseSequence(stdout);
};

const getRemoteSequence = async () => {
  const response = await fetch(GEOFABRIK_REPLICATION_STATE_URL, {
    headers: { accept: "text/plain" },
    signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Geofabrik returned HTTP ${response.status}`);
  return parseGeofabrikState(await response.text());
};

exports.check = async () => {
  try {
    const [localSequence, remoteSequence] = await Promise.all([
      getLocalSequence(),
      getRemoteSequence(),
    ]);
    return {
      updateAvailable: remoteSequence > localSequence,
      localSequence: String(localSequence),
      remoteSequence: String(remoteSequence),
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


const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { Worker } = require("bullmq");
const { Pool } = require("pg");
const { connection } = require("../config/redis");
const {
  NOMINATIM_BIN,
  NOMINATIM_PROJECT_DIR,
  PHOTON_UPDATE_URL,
  PHOTON_UPDATE_STATUS_URL,
  PHOTON_REQUEST_TIMEOUT_MS,
  SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS,
} = require("../config/config");
const { QUEUE_NAME } = require("../queues/searchIndexUpdateQueue");
const { connection: databaseConnection, databasePassword } = require("../utils/databaseConfig");
const { hasNewSequence, parseSequence } = require("../utils/nominatimSequence");
const { parsePhotonStatus } = require("../utils/photonStatus");

const execFileAsync = promisify(execFile);
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const databasePool = new Pool({
  ...databaseConnection,
  password: databasePassword,
  connectionTimeoutMillis: PHOTON_REQUEST_TIMEOUT_MS,
  idleTimeoutMillis: 10000,
  max: 2,
});

databasePool.on("error", (error) => {
  console.error("Unexpected Nominatim worker database error", error);
});

const getNominatimSequence = async () => {
  const result = await databasePool.query("SELECT sequence_id FROM import_status LIMIT 1");
  return parseSequence(result.rows[0]?.sequence_id);
};

const runNominatimUpdate = async () => {
  await execFileAsync(NOMINATIM_BIN, ["replication", "--catch-up"], {
    cwd: NOMINATIM_PROJECT_DIR,
    timeout: SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS * 1000,
    maxBuffer: 10 * 1024 * 1024,
  });
};

const requestPhotonUpdate = async () => {
  const response = await fetch(PHOTON_UPDATE_URL, {
    signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Photon update request returned HTTP ${response.status}`);
};

const waitForPhotonUpdate = async () => {
  const deadline = Date.now() + SEARCH_INDEX_UPDATE_TIMEOUT_SECONDS * 1000;
  while (Date.now() < deadline) {
    const response = await fetch(PHOTON_UPDATE_STATUS_URL, {
      signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS),
    });
    if (!response.ok) throw new Error(`Photon update status returned HTTP ${response.status}`);
    const status = parsePhotonStatus(await response.text());
    if (status === "OK") return;
    if (status !== "BUSY") throw new Error(`Unexpected Photon update status: ${status}`);
    await wait(5000);
  }
  throw new Error("Photon update timed out");
};

const smokeTest = async (query, lang) => {
  const url = new URL("/api", PHOTON_UPDATE_URL);
  url.searchParams.set("q", query);
  url.searchParams.set("lang", lang);
  url.searchParams.set("limit", "1");
  const response = await fetch(url, { signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS) });
  if (!response.ok) throw new Error(`Photon ${lang} smoke test returned HTTP ${response.status}`);
  const body = await response.json();
  if (!Array.isArray(body.features) || body.features.length === 0) {
    throw new Error(`Photon ${lang} smoke test returned no results`);
  }
};

const worker = new Worker(QUEUE_NAME, async (job) => {
  const sequenceBefore = await getNominatimSequence();
  await job.updateProgress({ state: "updating_nominatim", sequenceBefore: String(sequenceBefore) });
  await runNominatimUpdate();
  const sequenceAfter = await getNominatimSequence();

  if (!hasNewSequence(sequenceBefore, sequenceAfter)) {
    const result = { outcome: "no_changes", sequence: String(sequenceAfter) };
    await job.updateProgress({ state: "succeeded", ...result });
    return result;
  }

  await job.updateProgress({
    state: "updating_photon",
    sequenceBefore: String(sequenceBefore),
    sequenceAfter: String(sequenceAfter),
  });
  await requestPhotonUpdate();
  await waitForPhotonUpdate();
  await job.updateProgress({ state: "verifying" });
  await smokeTest("Dhaka", "en");
  await smokeTest("\u09a2\u09be\u0995\u09be", "bn");
  const result = { outcome: "updated", sequence: String(sequenceAfter) };
  await job.updateProgress({ state: "succeeded", ...result });
  return result;
}, { connection, concurrency: 1 });

worker.on("completed", (job, result) => {
  console.log(`Search-index update ${job.id} completed (${result.outcome})`);
});
worker.on("failed", (job, error) => console.error(`Search-index update ${job?.id} failed`, error));
console.log("Search-index update worker started");

module.exports = { getNominatimSequence, requestPhotonUpdate, waitForPhotonUpdate };


const { PHOTON_BASE_URL, PHOTON_REQUEST_TIMEOUT_MS } = require("../config/config");
const searchIndexUpdateService = require("./searchIndexUpdateService");

const photonAvailable = async () => {
  try {
    const response = await fetch(new URL("/api?q=Dhaka&limit=1", PHOTON_BASE_URL), {
      signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS),
    });
    return response.ok;
  } catch (_error) {
    return false;
  }
};

exports.readiness = async () => {
  const [photon, updates] = await Promise.all([
    photonAvailable(),
    searchIndexUpdateService.isAvailable(),
  ]);
  return {
    status: photon ? "ok" : "degraded",
    dependencies: { photon: photon ? "up" : "down" },
    features: { searchIndexUpdates: updates ? "enabled" : "disabled" },
  };
};


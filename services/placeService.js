const {
  PHOTON_BASE_URL,
  PHOTON_REQUEST_TIMEOUT_MS,
  PHOTON_RESULT_LIMIT,
  PLACE_SEARCH_MIN_CHARS,
} = require("../config/config");

const clientError = (message) => {
  const error = new Error(message);
  error.status = 400;
  return error;
};

class PlaceService {
  suggest = async ({ q, lang = "bn", limit }) => {
    const query = typeof q === "string" ? q.trim() : "";
    if (query.length < PLACE_SEARCH_MIN_CHARS) {
      throw clientError(`q must contain at least ${PLACE_SEARCH_MIN_CHARS} characters`);
    }
    if (!/^[a-z]{2}$/i.test(lang)) throw clientError("lang must be a two-letter language code");

    const requestedLimit = limit === undefined ? PHOTON_RESULT_LIMIT : Number(limit);
    if (!Number.isInteger(requestedLimit) || requestedLimit < 1) {
      throw clientError("limit must be a positive integer");
    }

    const url = new URL("/api", PHOTON_BASE_URL);
    url.searchParams.set("q", query);
    url.searchParams.set("lang", lang.toLowerCase());
    url.searchParams.set("limit", String(Math.min(requestedLimit, PHOTON_RESULT_LIMIT)));
    url.searchParams.set("bbox", "88.0,20.5,92.8,26.7");

    let response;
    try {
      response = await fetch(url, {
        headers: { accept: "application/json" },
        signal: AbortSignal.timeout(PHOTON_REQUEST_TIMEOUT_MS),
      });
    } catch (cause) {
      const error = new Error("Place search is temporarily unavailable", { cause });
      error.status = 503;
      error.expose = true;
      throw error;
    }

    if (!response.ok) {
      const error = new Error(`Photon returned HTTP ${response.status}`);
      error.status = 502;
      error.expose = true;
      throw error;
    }

    const body = await response.json();
    return (body.features || [])
      .filter((feature) => feature.properties?.countrycode?.toLowerCase() === "bd")
      .map((feature) => ({
        osmType: feature.properties.osm_type,
        osmId: feature.properties.osm_id,
        name: feature.properties.name,
        street: feature.properties.street,
        locality: feature.properties.locality,
        district: feature.properties.district,
        city: feature.properties.city,
        state: feature.properties.state,
        postcode: feature.properties.postcode,
        country: feature.properties.country,
        coordinates: feature.geometry?.coordinates,
      }));
  };
}

module.exports = new PlaceService();


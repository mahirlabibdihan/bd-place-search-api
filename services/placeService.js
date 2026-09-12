const {
  PHOTON_BASE_URL,
  PHOTON_REQUEST_TIMEOUT_MS,
  PLACE_SEARCH_DEFAULT_LIMIT,
  PLACE_SEARCH_MAX_LIMIT,
  PLACE_SEARCH_MIN_CHARS,
} = require("../config/config");

const clientError = (message) => {
  const error = new Error(message);
  error.status = 400;
  return error;
};

class PlaceService {
  searchGeoJson = async ({ q, lang, limit, lat, lon }) => {
    const query = typeof q === "string" ? q.trim() : "";
    if (query.length < PLACE_SEARCH_MIN_CHARS) {
      throw clientError(`q must contain at least ${PLACE_SEARCH_MIN_CHARS} characters`);
    }
    if (lang !== undefined && !/^[a-z]{2}$/i.test(lang)) {
      throw clientError("lang must be a two-letter language code");
    }

    const requestedLimit = limit === undefined ? PLACE_SEARCH_DEFAULT_LIMIT : Number(limit);
    if (!Number.isInteger(requestedLimit) || requestedLimit < 1) {
      throw clientError("limit must be a positive integer");
    }
    // What every caller here actually wants is a deliverable address -- something with a postcode
    // -- not a city/village/admin area, and not a road, land-use parcel, or natural feature either
    // (all of which can match a query by name but aren't a single deliverable location). The
    // postcode requirement is enforced below, after the fetch, since Photon has no "field exists"
    // filter -- so we over-fetch here (capped at PLACE_SEARCH_MAX_LIMIT) to still have enough left
    // after that filter to fill the caller's actual requested limit.
    const fetchLimit = Math.min(requestedLimit * 4, PLACE_SEARCH_MAX_LIMIT);

    const url = new URL("/api", PHOTON_BASE_URL);
    url.searchParams.set("q", query);
    if (lang) url.searchParams.set("lang", lang.toLowerCase());
    url.searchParams.set("limit", String(fetchLimit));
    url.searchParams.set("bbox", "88.0,20.5,92.8,26.7");
    // Photon's osm_tag filter (repeatable, ANDed together for exclusions) applies this at query
    // time, cheaper than fetching them just to discard them in the postcode filter below.
    url.searchParams.append("osm_tag", "!place");
    url.searchParams.append("osm_tag", "!boundary");
    url.searchParams.append("osm_tag", "!highway");
    url.searchParams.append("osm_tag", "!landuse");
    url.searchParams.append("osm_tag", "!natural");
    url.searchParams.append("osm_tag", "!waterway");
    // Some water bodies (e.g. ponds) are tagged with "water" as their own top-level key
    // (water=pond/lake/reservoir) instead of natural=water, so !natural alone misses them.
    url.searchParams.append("osm_tag", "!water");

    if ((lat === undefined) !== (lon === undefined)) {
      throw clientError("lat and lon must be provided together");
    }
    if (lat !== undefined) {
      const latitude = Number(lat);
      const longitude = Number(lon);
      if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
        throw clientError("lat must be a number between -90 and 90");
      }
      if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
        throw clientError("lon must be a number between -180 and 180");
      }
      url.searchParams.set("lat", String(latitude));
      url.searchParams.set("lon", String(longitude));
    }

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
    const features = (body.features || [])
      .filter(
        (feature) => feature.properties?.countrycode?.toLowerCase() === "bd" && Boolean(feature.properties?.postcode),
      )
      .slice(0, requestedLimit);
    return { type: "FeatureCollection", features };
  };

  suggest = async ({ q, lang = "en", limit }) => {
    const body = await this.searchGeoJson({ q, lang, limit });
    return body.features.map((feature) => ({
      osmType: feature.properties.osm_type,
      osmId: feature.properties.osm_id,
      // The raw OSM tag value (e.g. "city", "village", "administrative", "college") -- this is
      // what Photon's own demo (photon.komoot.io) shows as each result's type badge, not the
      // coarser osm_key/type facet (which collapses both a city and a village down to "city").
      osmValue: feature.properties.osm_value,
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

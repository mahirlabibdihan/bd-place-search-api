const request = require("supertest");
const { app } = require("../app");

describe("API", () => {
  test("reports liveness", async () => {
    const response = await request(app).get("/api/v1/health");
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: "ok" });
  });

  test("allows the configured frontend origin", async () => {
    const response = await request(app)
      .options("/api/v1/places/suggestions")
      .set("Origin", "http://127.0.0.1:5173");
    expect(response.status).toBe(204);
    expect(response.headers["access-control-allow-origin"]).toBe("http://127.0.0.1:5173");
  });

  test("rejects a short place query", async () => {
    const response = await request(app).get("/api/v1/places/suggestions?q=a");
    expect(response.status).toBe(400);
    expect(response.body.error).toMatch(/at least 2 characters/);
  });

  test("provides a Photon-compatible GeoJSON search endpoint", async () => {
    const originalFetch = global.fetch;
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: { type: "Point", coordinates: [90.4125, 23.8103] },
            properties: { name: "Dhaka", countrycode: "BD", osm_type: "R", osm_id: 1 },
          },
          {
            type: "Feature",
            geometry: { type: "Point", coordinates: [13.405, 52.52] },
            properties: { name: "Berlin", countrycode: "DE", osm_type: "R", osm_id: 2 },
          },
        ],
      }),
    });

    try {
      const response = await request(app).get("/api/?q=dhaka&lang=en&limit=3&lat=23.8&lon=90.4");
      expect(response.status).toBe(200);
      expect(response.body.type).toBe("FeatureCollection");
      expect(response.body.features).toHaveLength(1);
      expect(response.body.features[0].properties.name).toBe("Dhaka");

      const upstreamUrl = new URL(global.fetch.mock.calls[0][0]);
      expect(upstreamUrl.searchParams.get("q")).toBe("dhaka");
      expect(upstreamUrl.searchParams.get("lang")).toBe("en");
      expect(upstreamUrl.searchParams.get("limit")).toBe("3");
      expect(upstreamUrl.searchParams.get("lat")).toBe("23.8");
      expect(upstreamUrl.searchParams.get("lon")).toBe("90.4");
    } finally {
      global.fetch = originalFetch;
    }
  });

  test("requires both Photon location-bias coordinates", async () => {
    const response = await request(app).get("/api?q=dhaka&lat=23.8");
    expect(response.status).toBe(400);
    expect(response.body.error).toMatch(/lat and lon/);
  });

  test("reports Photon connection failures as unavailable", async () => {
    const originalFetch = global.fetch;
    global.fetch = jest.fn().mockRejectedValue(new Error("connect ECONNREFUSED"));
    try {
      const response = await request(app).get("/api/v1/places/suggestions?q=dhaka");
      expect(response.status).toBe(503);
      expect(response.body).toEqual({ error: "Place search is temporarily unavailable" });
    } finally {
      global.fetch = originalFetch;
    }
  });

  test("protects the background-update API", async () => {
    const response = await request(app).post("/api/v1/admin/search-index-updates");
    expect([401, 503]).toContain(response.status);
  });

  test("returns JSON for unknown routes", async () => {
    const response = await request(app).get("/api/v1/missing");
    expect(response.status).toBe(404);
  });
});


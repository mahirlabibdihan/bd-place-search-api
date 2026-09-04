const request = require("supertest");
const { app } = require("../app");

describe("API", () => {
  test("reports liveness", async () => {
    const response = await request(app).get("/api/v1/health");
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: "ok" });
  });

  test("rejects a short place query", async () => {
    const response = await request(app).get("/api/v1/places/suggestions?q=a");
    expect(response.status).toBe(400);
    expect(response.body.error).toMatch(/at least 2 characters/);
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


const { parseGeofabrikState } = require("../services/updateAvailabilityService");

describe("Geofabrik replication state", () => {
  test("reads its sequence number", () => {
    const state = "timestamp=2026-09-04T00\\:00\\:00Z\nsequenceNumber=12345\n";
    expect(parseGeofabrikState(state)).toBe(12345n);
  });

  test("rejects a state without a sequence", () => {
    expect(() => parseGeofabrikState("timestamp=unknown")).toThrow(/sequence number/);
  });
});

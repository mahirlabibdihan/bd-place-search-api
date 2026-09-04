const { parseGeofabrikState } = require("../services/updateAvailabilityService");

describe("Geofabrik replication state", () => {
  test("reads its timestamp and regional sequence", () => {
    const state = [
      "# original OSM minutely replication sequence number 7271351",
      "timestamp=2026-09-03T20\\:21\\:51Z",
      "sequenceNumber=4867",
    ].join("\n");

    expect(parseGeofabrikState(state)).toEqual({
      timestamp: new Date("2026-09-03T20:21:51Z"),
      regionalSequence: "4867",
    });
  });

  test("rejects an incomplete state", () => {
    expect(() => parseGeofabrikState("timestamp=unknown")).toThrow(/missing|timestamp/);
  });
});

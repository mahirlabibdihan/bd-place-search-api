jest.mock("../services/searchIndexUpdateService", () => ({ enqueue: jest.fn() }));
jest.mock("../services/updateAvailabilityService", () => ({ check: jest.fn() }));
jest.mock("../services/indexStatsService", () => ({ getStats: jest.fn() }));

const searchIndexUpdateService = require("../services/searchIndexUpdateService");
const updateAvailabilityService = require("../services/updateAvailabilityService");
const indexStatsService = require("../services/indexStatsService");
const controller = require("../controllers/searchIndexUpdateController");

const response = () => {
  const res = {};
  res.status = jest.fn(() => res);
  res.json = jest.fn(() => res);
  return res;
};

describe("search-index update creation", () => {
  beforeEach(() => jest.clearAllMocks());

  test("does not enqueue when no update is available", async () => {
    const availability = { updateAvailable: false, localImportDate: "local" };
    updateAvailabilityService.check.mockResolvedValue(availability);
    const res = response();

    await controller.create({ get: jest.fn() }, res, jest.fn());

    expect(searchIndexUpdateService.enqueue).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith({ status: "no_changes", ...availability });
  });

  test("enqueues when an update is available", async () => {
    updateAvailabilityService.check.mockResolvedValue({ updateAvailable: true });
    searchIndexUpdateService.enqueue.mockResolvedValue({ jobId: "update-1" });
    const req = { get: jest.fn().mockReturnValue("request-1") };
    const res = response();

    await controller.create(req, res, jest.fn());

    expect(searchIndexUpdateService.enqueue).toHaveBeenCalledWith("request-1");
    expect(res.status).toHaveBeenCalledWith(202);
  });
});

describe("search-index stats", () => {
  beforeEach(() => jest.clearAllMocks());

  test("returns the stats service's result", async () => {
    const stats = { totalPlaces: 100, roads: 40, administrativeAreas: 5, lastImportDate: "2026-01-01T00:00:00.000Z" };
    indexStatsService.getStats.mockResolvedValue(stats);
    const res = response();

    await controller.stats({}, res, jest.fn());

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(stats);
  });

  test("forwards errors to next", async () => {
    const error = new Error("boom");
    indexStatsService.getStats.mockRejectedValue(error);
    const next = jest.fn();

    await controller.stats({}, response(), next);

    expect(next).toHaveBeenCalledWith(error);
  });
});

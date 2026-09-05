jest.mock("../services/searchIndexUpdateService", () => ({ enqueue: jest.fn() }));
jest.mock("../services/updateAvailabilityService", () => ({ check: jest.fn() }));

const searchIndexUpdateService = require("../services/searchIndexUpdateService");
const updateAvailabilityService = require("../services/updateAvailabilityService");
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

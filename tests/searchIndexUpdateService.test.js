jest.mock("../queues/searchIndexUpdateQueue", () => ({
  getQueue: jest.fn(),
  resetQueue: jest.fn().mockResolvedValue(undefined),
}));

const queueStore = require("../queues/searchIndexUpdateQueue");
const service = require("../services/searchIndexUpdateService");

describe("searchIndexUpdateService Redis availability", () => {
  beforeEach(() => jest.clearAllMocks());

  test("fails fast with 503 when Redis is unavailable", async () => {
    queueStore.getQueue.mockReturnValue({
      waitUntilReady: jest.fn().mockRejectedValue(new Error("ECONNREFUSED")),
    });

    await expect(service.enqueue("test-key")).rejects.toMatchObject({
      status: 503,
      code: "SEARCH_INDEX_UPDATES_UNAVAILABLE",
    });
    expect(queueStore.resetQueue).toHaveBeenCalledTimes(1);
  });

  test("reports the update feature unavailable", async () => {
    queueStore.getQueue.mockReturnValue({
      waitUntilReady: jest.fn().mockRejectedValue(new Error("ECONNREFUSED")),
    });

    await expect(service.isAvailable()).resolves.toBe(false);
  });

  test("reports the update feature available after Redis recovers", async () => {
    queueStore.getQueue.mockReturnValue({
      waitUntilReady: jest.fn().mockResolvedValue(undefined),
      client: Promise.resolve({ ping: jest.fn().mockResolvedValue("PONG") }),
    });

    await expect(service.isAvailable()).resolves.toBe(true);
  });
});


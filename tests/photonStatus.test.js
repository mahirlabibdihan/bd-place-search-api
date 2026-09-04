const { parsePhotonStatus } = require("../utils/photonStatus");

describe("parsePhotonStatus", () => {
  test.each([
    ["BUSY", "BUSY"],
    [" OK\n", "OK"],
    ["\"BUSY\"", "BUSY"],
    ['{"status":"OK"}', "OK"],
  ])("parses %p", (input, expected) => {
    expect(parsePhotonStatus(input)).toBe(expected);
  });
});


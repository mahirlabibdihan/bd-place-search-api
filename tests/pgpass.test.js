const { splitLine } = require("../utils/pgpass");

describe("pgpass parsing", () => {
  test("splits a normal credential line", () => {
    expect(splitLine("127.0.0.1:5432:nominatim:status:secret")).toEqual([
      "127.0.0.1",
      "5432",
      "nominatim",
      "status",
      "secret",
    ]);
  });

  test("supports escaped colons and backslashes", () => {
    expect(splitLine("host:5432:db:user:pass\\:word\\\\end")).toEqual([
      "host",
      "5432",
      "db",
      "user",
      "pass:word\\end",
    ]);
  });
});

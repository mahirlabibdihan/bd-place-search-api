const { hasNewSequence, parseSequence } = require("../utils/nominatimSequence");

describe("Nominatim replication sequences", () => {
  test("detects an advanced sequence", () => {
    expect(hasNewSequence("100", "101")).toBe(true);
  });

  test("detects that no update was applied", () => {
    expect(hasNewSequence("100", "100")).toBe(false);
  });

  test("rejects missing or malformed sequence values", () => {
    expect(() => parseSequence("")).toThrow(/Invalid Nominatim/);
    expect(() => parseSequence("12x")).toThrow(/Invalid Nominatim/);
  });
});

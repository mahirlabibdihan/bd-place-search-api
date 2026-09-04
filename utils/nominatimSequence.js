const parseSequence = (value) => {
  const sequence = String(value).trim();
  if (!/^\d+$/.test(sequence)) {
    throw new Error(`Invalid Nominatim replication sequence: ${sequence || "empty"}`);
  }
  return BigInt(sequence);
};

const hasNewSequence = (before, after) => parseSequence(after) > parseSequence(before);

module.exports = { hasNewSequence, parseSequence };


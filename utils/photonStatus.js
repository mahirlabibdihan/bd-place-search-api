const parsePhotonStatus = (body) => {
  const text = String(body).trim();
  if (!text) return "UNKNOWN";
  try {
    const parsed = JSON.parse(text);
    return String(parsed.status ?? parsed).trim().toUpperCase();
  } catch (_error) {
    return text.toUpperCase();
  }
};

module.exports = { parsePhotonStatus };


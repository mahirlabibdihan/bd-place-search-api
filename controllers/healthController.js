const healthService = require("../services/healthService");

exports.health = async (_req, res) => {
  const result = await healthService.readiness();
  res.status(result.status === "ok" ? 200 : 503).json(result);
};

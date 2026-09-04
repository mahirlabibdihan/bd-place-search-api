const healthService = require("../services/healthService");

exports.live = (_req, res) => res.status(200).json({ status: "ok" });

exports.ready = async (_req, res) => {
  const result = await healthService.readiness();
  res.status(result.status === "ok" ? 200 : 503).json(result);
};


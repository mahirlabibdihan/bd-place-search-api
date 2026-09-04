const searchIndexUpdateService = require("../services/searchIndexUpdateService");
const updateAvailabilityService = require("../services/updateAvailabilityService");

exports.availability = async (_req, res, next) => {
  try {
    res.status(200).json(await updateAvailabilityService.check());
  } catch (error) {
    next(error);
  }
};

exports.create = async (req, res, next) => {
  try {
    const job = await searchIndexUpdateService.enqueue(req.get("Idempotency-Key"));
    res.status(202).json(job);
  } catch (error) {
    next(error);
  }
};

exports.get = async (req, res, next) => {
  try {
    res.status(200).json(await searchIndexUpdateService.get(req.params.jobId));
  } catch (error) {
    next(error);
  }
};


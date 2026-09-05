const router = require("express").Router();
const adminAuth = require("../middlewares/adminAuthMiddleware");
const controller = require("../controllers/searchIndexUpdateController");

router.use(adminAuth);
router.get("/availability", controller.availability);
router.post("/", controller.create);
router.get("/:jobId", controller.get);

module.exports = router;


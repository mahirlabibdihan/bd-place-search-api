const router = require("express").Router();
const placeController = require("../controllers/placeController");

router.get("/suggestions", placeController.suggestions);
router.get("/search", placeController.suggestions);

module.exports = router;


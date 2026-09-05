const router = require("express").Router();
const placeController = require("../controllers/placeController");

router.get("/search", placeController.search);

module.exports = router;


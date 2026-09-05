const express = require("express");
const healthRoutes = require("./routes/healthRoutes");
const placeRoutes = require("./routes/placeRoutes");
const placeController = require("./controllers/placeController");
const searchIndexUpdateRoutes = require("./routes/searchIndexUpdateRoutes");
const { errorHandler, notFoundHandler } = require("./middlewares/errorMiddleware");
const cors = require("./middlewares/corsMiddleware");

const app = express();
app.disable("x-powered-by");
app.use(cors);
app.use(express.json({ limit: "32kb" }));
app.get("/api", placeController.photon);
app.use("/api", healthRoutes);
app.use("/api", placeRoutes);
app.use("/api/admin/update", searchIndexUpdateRoutes);
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = { app };


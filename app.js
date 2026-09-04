const express = require("express");
const healthRoutes = require("./routes/healthRoutes");
const placeRoutes = require("./routes/placeRoutes");
const searchIndexUpdateRoutes = require("./routes/searchIndexUpdateRoutes");
const { errorHandler, notFoundHandler } = require("./middlewares/errorMiddleware");

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "32kb" }));
app.use("/api/v1/health", healthRoutes);
app.use("/api/v1/places", placeRoutes);
app.use("/api/v1/admin/search-index-updates", searchIndexUpdateRoutes);
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = { app };


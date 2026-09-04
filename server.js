const { app } = require("./app");
const { PORT } = require("./config/config");

app.listen(PORT, "127.0.0.1", () => {
  console.log(`Place-search API listening on http://127.0.0.1:${PORT}`);
});


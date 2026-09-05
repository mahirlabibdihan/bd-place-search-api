const { app } = require("./app");
const { HOST, PORT } = require("./config/config");

app.listen(PORT, HOST, () => {
  console.log(`Place-search API listening on http://${HOST}:${PORT}`);
});


const Controller = require("./base");
const placeService = require("../services/placeService");

class PlaceController extends Controller {
  suggestions = async (req, res, next) => {
    try {
      const suggestions = await placeService.suggest(req.query);
      res.status(200).json({ data: suggestions });
    } catch (error) {
      next(error);
    }
  };
}

module.exports = new PlaceController();


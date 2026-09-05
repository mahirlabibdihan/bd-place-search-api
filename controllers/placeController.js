const Controller = require("./base");
const placeService = require("../services/placeService");

class PlaceController extends Controller {
  photon = async (req, res, next) => {
    try {
      const featureCollection = await placeService.searchGeoJson(req.query);
      res.status(200).json(featureCollection);
    } catch (error) {
      next(error);
    }
  };

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


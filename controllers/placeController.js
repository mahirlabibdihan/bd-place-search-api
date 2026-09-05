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

  search = async (req, res, next) => {
    try {
      const places = await placeService.suggest(req.query);
      res.status(200).json({ data: places });
    } catch (error) {
      next(error);
    }
  };
}

module.exports = new PlaceController();


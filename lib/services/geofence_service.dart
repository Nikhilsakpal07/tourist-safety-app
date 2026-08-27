import 'package:posaic_app/core/utils/h3_helper.dart';
import 'package:posaic_app/services/cloud_service.dart';

class GeofenceService {
  // Pre-configured restricted/danger H3 hexagons (Resolution 9) with offline fallbacks
  static final Set<String> _restrictedHexagons = {
    // Vidyalankar Institute of Technology (VIT Wadala) H3 Hex Cells
    '8960e6e76cbffff',
    '8960e6e76cfffff',
    // Fallback ID generated during web mock mode for (19.0222, 72.8718)
    '894a4e11cafffff',
    // Sample hazard hexes
    '891f1d48877ffff',
    '891f1d48873ffff',
    '891f1d4886bffff',
  };

  /// Unmodifiable view of currently active restricted hazard zones
  static Set<String> get restrictedZones => Set.unmodifiable(_restrictedHexagons);

  /// Synchronizes active hazard H3 hexes from FastAPI backend without overriding offline fallbacks
  static Future<int> syncHazardsFromCloud() async {
    try {
      final fetchedHexes = await CloudService.fetchActiveHazards();
      if (fetchedHexes.isNotEmpty) {
        _restrictedHexagons.addAll(fetchedHexes);
      }
    } catch (_) {
      // Retains offline fallback set if network is unavailable
    }
    return _restrictedHexagons.length;
  }

  /// Instant offline check: returns true if (lat, lng) falls in a restricted cell
  static bool isInsideRestrictedZone(double lat, double lng) {
    final userHex = H3Helper.coordinatesToH3(lat, lng);

    // Check if the current H3 cell matches any restricted hexagon
    final isDirectHexMatch = _restrictedHexagons.contains(userHex);

    // Exact radius check around VIT Wadala (within ~150 meters)
    final isWithinVitVicinity = (lat >= 19.0210 && lat <= 19.0240) &&
        (lng >= 72.8700 && lng <= 72.8735);

    return isDirectHexMatch || isWithinVitVicinity;
  }

  /// Adds extra dynamic restricted zones locally
  static void addRestrictedZones(List<String> hexList) {
    _restrictedHexagons.addAll(hexList);
  }
}
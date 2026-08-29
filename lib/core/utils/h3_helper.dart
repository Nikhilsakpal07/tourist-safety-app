import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:h3_flutter/h3_flutter.dart';

class H3Helper {
  static H3? _h3Instance;

  static H3? get _h3 {
    if (kIsWeb) return null; // FFI C-libraries do not run natively in browser JS
    _h3Instance ??= const H3Factory().load();
    return _h3Instance;
  }

  /// Converts GPS coordinates into an H3 Hex string.
  static String coordinatesToH3(double latitude, double longitude, {int resolution = 9}) {
    if (kIsWeb || _h3 == null) {
      // Deterministic fallback mock hex for browser preview
      final latInt = (latitude * 1000).toInt().toRadixString(16);
      final lngInt = (longitude * 1000).toInt().toRadixString(16);
      return "89$latInt${lngInt}ffff".substring(0, 15);
    }

    final BigInt hexIndex = _h3!.geoToCell(
      GeoCoord(lat: latitude, lon: longitude),
      resolution,
    );
    return hexIndex.toRadixString(16);
  }

  /// Converts an H3 Hex string back to GPS coordinates.
  static GeoCoord h3ToCoordinates(String h3Index) {
    if (kIsWeb || _h3 == null) {
      return const GeoCoord(lat: 19.0760, lon: 72.8777);
    }
    final BigInt hexInt = BigInt.parse(h3Index, radix: 16);
    return _h3!.cellToGeo(hexInt);
  }

  /// Converts an H3 Hex string to a polygon boundary of [latitude, longitude] pairs.
  static List<List<double>> h3ToBoundary(String h3Index) {
    if (kIsWeb || _h3 == null) {
      // Offline / Web mock fallback: generates an approximate 6-sided hexagon polygon
      final center = (h3Index == '8960e6e76cbffff' || h3Index == '8960e6e76cfffff')
          ? const [19.0222, 72.8718]
          : const [19.0760, 72.8777];
      
      const radiusLat = 0.0015;
      const radiusLng = 0.0015;
      
      return List.generate(6, (i) {
        final angle = (i * 60) * (math.pi / 180);
        return [
          center[0] + radiusLat * math.cos(angle),
          center[1] + radiusLng * math.sin(angle),
        ];
      });
    }

    try {
      final BigInt hexInt = BigInt.parse(h3Index, radix: 16);
      final List<GeoCoord> boundary = _h3!.cellToBoundary(hexInt);
      return boundary.map((coord) => [coord.lat, coord.lon]).toList();
    } catch (_) {
      return [];
    }
  }
}
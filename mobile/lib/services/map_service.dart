import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'dart:io' show Platform;
import '../core/interfaces/services.dart';

class MapService implements IHazardMapService {
  final IDatabaseService _dbService;
  
  // Use actual local IP because 10.0.2.2 fails on physical Android devices via USB
  late final String _backendUrl = 'http://192.168.29.211:8000/api/v1/zones/active';
  
  String _currentMapProvider = 'OSM'; // Default to OSM Tiles

  MapService(this._dbService);

  @override
  Future<List<String>> fetchActiveHazardZones({double? lat, double? lon}) async {
    // If no coordinates provided, we can't query Overpass effectively
    if (lat == null || lon == null) return [];

    try {
      // Create a bounding box of roughly ~10-15km around the user
      final bbox = '${lat - 0.1},${lon - 0.1},${lat + 0.1},${lon + 0.1}';
      
      // Overpass query for various natural and man-made hazards
      final query = '''
        [out:json];
        (
          way["hazard"]($bbox);
          way["military"="danger_area"]($bbox);
          way["natural"="volcano"]($bbox);
          way["landuse"="quarry"]($bbox);
          way["waterway"="rapids"]($bbox);
          way["natural"="cliff"]($bbox);
          way["natural"="crevasse"]($bbox);
          way["boundary"="danger_zone"]($bbox);
        );
        out geom;
      ''';

      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List;
        final h3 = const H3Factory().load();
        Set<String> hexSet = {};

        for (var el in elements) {
          if (el['type'] == 'way' && el['geometry'] != null) {
            final geom = el['geometry'] as List;
            List<GeoCoord> coords = [];
            for (var pt in geom) {
              coords.add(GeoCoord(lat: pt['lat'], lon: pt['lon']));
            }
            
            // H3 polygonToCells requires at least 3 points
            if (coords.length >= 3) {
              try {
                final hexes = h3.polygonToCells(perimeter: coords, resolution: 8);
                for (var hex in hexes) {
                  hexSet.add(hex.toRadixString(16));
                }
              } catch (e) {
                // Ignore shapes that fail parsing
              }
            }
          }
        }
        return hexSet.toList();
      }
      return [];
    } catch (e) {
      print('Overpass fetch error: $e');
      return [];
    }
    
    // Fallback to offline cache
    return await _dbService.getCachedHazardZones();
  }

  @override
  void setMapProvider(String providerName) {
    // Hook to switch between 'OSM', 'GoogleMaps', etc.
    // In a real app, this might trigger a state update to swap the Map widget.
    _currentMapProvider = providerName;
    print('Map provider set to $_currentMapProvider');
  }

  @override
  void onHazardZoneEntered(String h3Index) {
    // Hook for when GPS tracking detects user is inside a hazard hex.
    // E.g., trigger local notification, red screen flash, audible siren.
    print('DANGER: Entered Hazard Zone $h3Index!');
  }
  
  String get mapProvider => _currentMapProvider;
}

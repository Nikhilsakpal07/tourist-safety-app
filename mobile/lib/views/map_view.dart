import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/interfaces/services.dart';

class HazardMapView extends StatefulWidget {
  final IHazardMapService mapService;

  const HazardMapView({Key? key, required this.mapService}) : super(key: key);

  @override
  _HazardMapViewState createState() => _HazardMapViewState();
}

class _HazardMapViewState extends State<HazardMapView> {
  List<Polygon> _hazardPolygons = [];
  List<String> _cachedH3Indices = [];
  bool _isLoading = true;
  bool _hasCenteredMap = false;
  
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS is turned off');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('GPS Permission denied');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('GPS permanently denied');

      // Attempt to get an immediate location
      Position? initialPos = await Geolocator.getLastKnownPosition();
      if (initialPos != null && !_hasCenteredMap) {
        setState(() {
          _currentPosition = LatLng(initialPos.latitude, initialPos.longitude);
        });
        _mapController.move(_currentPosition!, 15.0);
        _hasCenteredMap = true;
        _loadHazards(initialPos.latitude, initialPos.longitude);
      } else if (initialPos == null) {
        // If device has no cached location, dismiss loader so map still shows (will load hazards when stream fires)
        if (mounted) setState(() { _isLoading = false; });
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
          });
        }
        if (!_hasCenteredMap) {
          _mapController.move(_currentPosition!, 15.0);
          _hasCenteredMap = true;
          _loadHazards(position.latitude, position.longitude);
        }
        _checkHazardProximity(position);
      });
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location error: $e')));
      }
    }
  }

  void _checkHazardProximity(Position pos) {
    if (_cachedH3Indices.isEmpty) return;
    final h3 = const H3Factory().load();
    final currentHex = h3.geoToCell(GeoCoord(lat: pos.latitude, lon: pos.longitude), 8).toRadixString(16);
    
    if (_cachedH3Indices.contains(currentHex)) {
      widget.mapService.onHazardZoneEntered(currentHex);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⚠️ DANGER ZONE'),
            content: Text('You have entered an active hazard zone (Hex: $currentHex). Please proceed with caution or trigger SOS if needed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ACKNOWLEDGE'))
            ],
          )
        );
      }
    }
  }

  Future<void> _loadHazards(double lat, double lon) async {
    setState(() { _isLoading = true; });
    
    final h3Indices = await widget.mapService.fetchActiveHazardZones(lat: lat, lon: lon);
    final h3 = const H3Factory().load();
    List<Polygon> polygons = [];

    for (String index in h3Indices) {
      // Get the boundaries of the H3 hex
      // Note: H3 returns coordinates in (lat, lon) or (lon, lat) depending on the binding.
      // Assuming lat/lon for h3_flutter here.
      try {
        final boundary = h3.cellToBoundary(BigInt.parse(index, radix: 16));
        final points = boundary.map((coord) => LatLng(coord.lat, coord.lon)).toList();
        
        polygons.add(Polygon(
          points: points,
          color: Colors.red.withOpacity(0.4),
          borderColor: Colors.red,
          borderStrokeWidth: 2,
        ));
      } catch (e) {
        print('Error parsing H3 index: $index');
      }
    }

    setState(() {
      _hazardPolygons = polygons;
      _cachedH3Indices = h3Indices;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dynamic Hazard Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_currentPosition != null) {
                _loadHazards(_currentPosition!.latitude, _currentPosition!.longitude);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Waiting for GPS lock...')),
                );
              }
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition ?? const LatLng(37.7749, -122.4194),
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.tourist_mesh_app',
                  // In a production app, use flutter_map_cache for offline tiling:
                  // tileProvider: CachedTileProvider(),
                ),
                PolygonLayer(
                  polygons: _hazardPolygons,
                ),
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

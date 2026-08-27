import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:posaic_app/services/geofence_service.dart';
import 'package:posaic_app/core/utils/h3_helper.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  LatLng _currentLocation = const LatLng(19.0222, 72.8718); // Default fallback: VIT Wadala
  String _currentH3 = '';
  bool _isRestricted = false;
  bool _isSyncing = false;
  List<Polygon> _hazardPolygons = [];

  @override
  void initState() {
    super.initState();
    _currentH3 = H3Helper.coordinatesToH3(_currentLocation.latitude, _currentLocation.longitude);
    _isRestricted = GeofenceService.isInsideRestrictedZone(_currentLocation.latitude, _currentLocation.longitude);

    _buildHazardPolygons();
    _syncWithCloudHazards();
    _initLiveGpsTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  /// Requests hardware location permissions and starts the live position stream
  Future<void> _initLiveGpsTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // Get immediate initial fix
    try {
      final initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _handlePositionUpdate(LatLng(initialPos.latitude, initialPos.longitude));
    } catch (_) {}

    // Stream live location as you walk
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3, // Fires whenever you move 3 meters
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) {
        _handlePositionUpdate(LatLng(pos.latitude, pos.longitude));
      },
    );
  }

  void _handlePositionUpdate(LatLng point) {
    final h3Index = H3Helper.coordinatesToH3(point.latitude, point.longitude);
    final restricted = GeofenceService.isInsideRestrictedZone(point.latitude, point.longitude);

    setState(() {
      _currentLocation = point;
      _currentH3 = h3Index;
      _isRestricted = restricted;
    });

    _mapController.move(point, _mapController.camera.zoom);

    if (restricted && mounted) {
      _showWarningSnackBar();
    }
  }

  /// Builds polygon boundaries for all active H3 hazard hexes
  void _buildHazardPolygons() {
    final polygons = <Polygon>[];
    for (final hex in GeofenceService.restrictedZones) {
      final boundaryPoints = H3Helper.h3ToBoundary(hex);
      if (boundaryPoints.isNotEmpty) {
        polygons.add(
          Polygon(
            points: boundaryPoints.map((pt) => LatLng(pt[0], pt[1])).toList(),
            color: Colors.red.withOpacity(0.35),
            borderColor: Colors.redAccent,
            borderStrokeWidth: 2.0,
          ),
        );
      }
    }

    setState(() {
      _hazardPolygons = polygons;
    });
  }

  /// Fetches latest hazard hexes from FastAPI backend
  Future<void> _syncWithCloudHazards() async {
    setState(() => _isSyncing = true);
    await GeofenceService.syncHazardsFromCloud();
    _buildHazardPolygons();

    final restricted = GeofenceService.isInsideRestrictedZone(
      _currentLocation.latitude,
      _currentLocation.longitude,
    );

    setState(() {
      _isRestricted = restricted;
      _isSyncing = false;
    });
  }

  void _showWarningSnackBar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('ALERT: Entered restricted hazard zone!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 16.0,
              onTap: (_, latlng) => _handlePositionUpdate(latlng), // Still allows tap-testing
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.posaic.posaic_app',
              ),
              PolygonLayer(polygons: _hazardPolygons),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 45,
                    height: 45,
                    child: Icon(
                      Icons.person_pin_circle,
                      size: 45,
                      color: _isRestricted ? Colors.red : Colors.tealAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'H3 Index: $_currentH3',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                        Text(
                          _isRestricted ? 'ZONE: RESTRICTED HAZARD' : 'ZONE: VERIFIED SAFE',
                          style: TextStyle(
                            color: _isRestricted ? Colors.redAccent : Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                                )
                              : const Icon(Icons.sync, color: Colors.tealAccent),
                          tooltip: 'Sync Hazards from Cloud',
                          onPressed: _isSyncing ? null : _syncWithCloudHazards,
                        ),
                        Icon(
                          _isRestricted ? Icons.warning : Icons.shield,
                          color: _isRestricted ? Colors.red : Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
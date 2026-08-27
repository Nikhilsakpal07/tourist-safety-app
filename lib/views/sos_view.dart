import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:posaic_app/services/mesh_service.dart';
import 'package:posaic_app/services/identity_service.dart';
import 'package:posaic_app/core/utils/h3_helper.dart';

class SosView extends StatefulWidget {
  const SosView({super.key});

  @override
  State<SosView> createState() => _SosViewState();
}

class _SosViewState extends State<SosView> {
  final MeshService _meshService = MeshService();
  bool _isTransmitting = false;
  String _statusMessage = "PRESS BUTTON IN CASE OF EMERGENCY";
  Color _statusColor = Colors.white70;

  @override
  void initState() {
    super.initState();
    _meshService.startBleMeshScanner();
  }

  Future<void> _handlePanicSos() async {
    setState(() {
      _isTransmitting = true;
      _statusMessage = "ACQUIRING GPS FIX & DISPATCHING SOS...";
      _statusColor = Colors.amberAccent;
    });

    try {
      double lat = 19.0222;
      double lon = 72.8718;

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (_) {}

      // 1. Resolve live H3 Index
      final currentH3 = H3Helper.coordinatesToH3(lat, lon);

      // 2. Resolve DID cryptographically
      final did = await IdentityService.getOrCreateDID();

      // 3. Dispatch Smart SOS
      final dispatchChannel = await _meshService.triggerSmartSos(
        did: did,
        h3Index: currentH3,
        emergencyType: "MANUAL_PANIC_BROADCAST",
      );

      setState(() {
        _isTransmitting = false;
        if (dispatchChannel == "DIRECT_CLOUD_DELIVERED") {
          _statusMessage = "ALERT DELIVERED DIRECTLY TO RESCUE AUTHORITIES";
          _statusColor = Colors.greenAccent;
        } else {
          _statusMessage = "OFFLINE: SOS QUEUED & BROADCASTING TO PEERS OVER BLE";
          _statusColor = Colors.redAccent;
        }
      });
    } catch (e) {
      setState(() {
        _isTransmitting = false;
        _statusMessage = "TRANSMISSION FAILED. RETRY.";
        _statusColor = Colors.red;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101216),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'EMERGENCY SOS',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: _isTransmitting ? null : _handlePanicSos,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTransmitting ? Colors.red[900] : const Color(0xFFD32F2F),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.45),
                        blurRadius: 35,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isTransmitting
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.emergency_share, size: 54, color: Colors.white),
                              SizedBox(height: 8),
                              Text(
                                "SOS",
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusColor == Colors.greenAccent
                        ? Icons.cloud_done
                        : (_statusColor == Colors.amberAccent
                            ? Icons.radar
                            : Icons.info_outline),
                    color: _statusColor,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
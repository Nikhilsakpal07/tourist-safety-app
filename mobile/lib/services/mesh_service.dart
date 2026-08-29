import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import '../core/interfaces/services.dart';

class MeshService implements ISosMeshService {
  final IDatabaseService _dbService;
  late final String _backendUrl = 'http://192.168.29.211:8000/api/v1/mesh/sync-sos';
  final String _sosServiceUuid = '0000FEAA-0000-1000-8000-00805F9B34FB';
  
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  StreamSubscription? _connectivitySubscription;

  MeshService(this._dbService) {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        _syncOfflinePackets();
      }
    });
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    bool allGranted = true;
    for (var status in statuses.values) {
      if (status != PermissionStatus.granted) {
        allGranted = false;
      }
    }
    return allGranted;
  }

  @override
  Future<void> stopSilentRelayScanner() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<SosPacket> triggerSos() async {
    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      throw Exception('Location and Bluetooth permissions are required for SOS');
    }

    // 1. Get GPS Fix
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    
    // 2. Convert to H3
    final h3 = const H3Factory().load();
    final h3Index = h3.geoToCell(GeoCoord(lat: position.latitude, lon: position.longitude), 8);
    
    // 3. Generate DID and Timestamp
    final did = 'user_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}'; // Mock DID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    final packet = SosPacket(
      did: did,
      h3Index: h3Index.toRadixString(16),
      timestamp: timestamp,
      type: 'SOS',
      isSynced: false,
    );

    // Save to DB initially
    await _dbService.saveSosPacket(packet);

    // 4. Try Online Sync
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi)) {
      await _syncOnline(packet);
    } else {
      // 5. Offline BLE Advertising (Victim Mode)
      await _startBleAdvertising(packet);
    }
    
    return packet;
  }

  Future<void> _syncOnline(SosPacket packet) async {
    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel': 'DIRECT_CELLULAR',
          'packets': [packet.toMap()]
        }),
      );

      if (response.statusCode == 200) {
        await _dbService.markPacketsAsSynced([packet.did]);
      }
    } catch (e) {
      print('Sync failed, falling back to BLE');
      await _startBleAdvertising(packet);
    }
  }

  Future<void> _syncOfflinePackets() async {
    final unsynced = await _dbService.getUnsyncedPackets();
    if (unsynced.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel': 'BLE_STORE_AND_FORWARD_MESH',
          'packets': unsynced.map((p) => p.toMap()).toList()
        }),
      );

      if (response.statusCode == 200) {
        await _dbService.markPacketsAsSynced(unsynced.map((e) => e.did).toList());
      }
    } catch (e) {
      print('Batch sync failed: $e');
    }
  }

  Future<void> _startBleAdvertising(SosPacket packet) async {
    final payloadString = '${packet.did}|${packet.h3Index}|${packet.timestamp}|${packet.type}';
    final payloadBytes = utf8.encode(payloadString);

    final AdvertiseData advertiseData = AdvertiseData(
      serviceUuid: _sosServiceUuid,
      manufacturerId: 0x00E0,
      manufacturerData: Uint8List.fromList(payloadBytes),
    );

    await _blePeripheral.start(advertiseData: advertiseData);
    print('Started BLE Advertising SOS');
  }

  @override
  Future<void> startSilentRelayScanner() async {
    bool hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      throw Exception('Location and Bluetooth permissions are required to enable Mule mode');
    }

    // Mule Mode - Scans for distress packets in background
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.advertisementData.serviceUuids.contains(Guid(_sosServiceUuid))) {
          // Found an SOS packet!
          // Extract data, save to DB, attempt sync if online.
          final mData = r.advertisementData.manufacturerData;
          if (mData.isNotEmpty) {
             final payload = utf8.decode(mData.values.first);
             final parts = payload.split('|');
             if (parts.length == 4) {
               final relayPacket = SosPacket(
                 did: parts[0],
                 h3Index: parts[1],
                 timestamp: int.tryParse(parts[2]) ?? 0,
                 type: parts[3],
               );
               await _dbService.saveSosPacket(relayPacket);
               _syncOfflinePackets(); // Auto-flush attempt
             }
          }
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(_sosServiceUuid)],
      continuousUpdates: true,
    );
  }
  
  @override
  void setSmsGatewayFallback() {
    // Implement SMS extension here
  }

  @override
  void setLoRaRadioFallback() {
    // Implement LoRa extension here
  }
}

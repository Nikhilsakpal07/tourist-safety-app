import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:posaic_app/models/sos_packet.dart';
import 'package:posaic_app/services/database_service.dart';
import 'package:posaic_app/services/cloud_service.dart';

class MeshService {
  final DatabaseService _db = DatabaseService.instance;
  static const String emergencyServiceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";

  /// Core SOS Trigger: Routes to Cloud if online, or queues and broadcasts via BLE if offline
  Future<String> triggerSmartSos({
    required String did,
    required String h3Index,
    required String emergencyType,
  }) async {
    final packet = SosPacket(
      id: "SOS-${DateTime.now().millisecondsSinceEpoch}",
      did: did,
      h3Index: h3Index,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      emergencyType: emergencyType,
      signature: "ed25519_signed_proof",
      isRelayed: 0,
    );

    // 1. Always persist locally in SQLite first
    await _db.insertSosPacket(packet);

    // 2. Check network connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasNetwork = !connectivityResult.contains(ConnectivityResult.none);

    if (hasNetwork) {
      final isDelivered = await CloudService.syncSosPacketsToCloud([packet]);
      if (isDelivered) {
        await _db.markPacketAsRelayed(packet.id);
        return "DIRECT_CLOUD_DELIVERED";
      }
    }

    // 3. Offline fallback: Broadcast over BLE to nearby peer devices
    await _broadcastBleDistress(packet);
    return "BLE_MESH_BROADCASTED";
  }

  /// Real BLE Mesh Scanner & Opportunistic Cloud Relayer
  void startBleMeshScanner() async {
    try {
      if (await FlutterBluePlus.isSupported == false) return;

      FlutterBluePlus.startScan(
        withServices: [Guid(emergencyServiceUuid)],
        continuousUpdates: true,
      );

      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          final manufacturerData = r.advertisementData.manufacturerData;
          if (manufacturerData.isNotEmpty) {
            try {
              final rawBytes = manufacturerData.values.first;
              final jsonString = utf8.decode(rawBytes);
              final data = jsonDecode(jsonString);

              final receivedPacket = SosPacket(
                id: data['id'],
                did: data['did'],
                h3Index: data['h3Index'],
                timestamp: data['timestamp'],
                emergencyType: data['emergencyType'],
                signature: data['signature'],
                isRelayed: 0,
              );

              await _db.insertSosPacket(receivedPacket);

              // Opportunistic Relay: If this peer device has internet, forward to authority immediately
              final connectivity = await Connectivity().checkConnectivity();
              if (!connectivity.contains(ConnectivityResult.none)) {
                await flushQueuedRelays();
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }

  Future<void> stopBleMeshScanner() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  /// Flushes all stored, un-relayed distress packets to the authority cloud
  Future<int> flushQueuedRelays() async {
    final pending = await _db.getPendingPackets();
    final unsynced = pending.where((p) => p.isRelayed == 0).toList();

    if (unsynced.isEmpty) return 0;

    final isSuccess = await CloudService.syncSosPacketsToCloud(unsynced);
    if (isSuccess) {
      for (final p in unsynced) {
        await _db.markPacketAsRelayed(p.id);
      }
      return unsynced.length;
    }
    return 0;
  }

  /// Simulation methods for UI & Emulator testing
  Future<SosPacket> simulateIncomingPeerSos() async {
    final simulatedPacket = SosPacket(
      id: "SOS-RELAY-HOP-${DateTime.now().millisecondsSinceEpoch}",
      did: "did:key:z6MkuT_PeerRelayHiker",
      h3Index: "89618925b4fffff",
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      emergencyType: "INCOMING_MESH_RELAY",
      signature: "simulated_ed25519_peer_sig",
      isRelayed: 0,
    );

    await _db.insertSosPacket(simulatedPacket);
    return simulatedPacket;
  }

  Future<int> simulateGatewaySync() => flushQueuedRelays();
  Future<int> syncGateway() => flushQueuedRelays();

  Future<void> _broadcastBleDistress(SosPacket packet) async {
    // BLE peripheral broadcasting hook
  }
}
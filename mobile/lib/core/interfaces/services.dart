import 'dart:async';

/// Core interfaces for the Decoupled Architecture

/// Represents a single SOS distress packet
class SosPacket {
  final String did;
  final String h3Index;
  final int timestamp;
  final String type;
  final bool isSynced;

  SosPacket({
    required this.did,
    required this.h3Index,
    required this.timestamp,
    required this.type,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'did': did,
      'h3_index': h3Index,
      'timestamp': timestamp,
      'type': type,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory SosPacket.fromMap(Map<String, dynamic> map) {
    return SosPacket(
      did: map['did'],
      h3Index: map['h3_index'],
      timestamp: map['timestamp'],
      type: map['type'],
      isSynced: map['is_synced'] == 1,
    );
  }
}

/// 1. Map & Hazard Interface
abstract class IHazardMapService {
  /// Fetches active hazard zones (H3 Indices)
  Future<List<String>> fetchActiveHazardZones({double? lat, double? lon});

  /// Hooks for external providers (Google Maps, OSM Tiles)
  void setMapProvider(String providerName);
  
  /// Triggered when GPS coordinates fall within a hazard H3 hex
  void onHazardZoneEntered(String h3Index);
}

/// 2. SOS Mesh Engine Interface
abstract class ISosMeshService {
  /// Triggers an SOS in Victim Mode
  Future<SosPacket> triggerSos();

  /// Starts the silent background peer relay (Mule Mode)
  Future<void> startSilentRelayScanner();

  /// Stops the silent background peer relay (Mule Mode)
  Future<void> stopSilentRelayScanner();
  
  /// Fallback extension stubs
  void setSmsGatewayFallback();
  void setLoRaRadioFallback();
}

/// 3. Database & Caching Interface
abstract class IDatabaseService {
  /// Initializes local storage
  Future<void> initDatabase();

  /// Saves an SOS packet locally (for offline queueing)
  Future<void> saveSosPacket(SosPacket packet);

  /// Retrieves unsynced packets
  Future<List<SosPacket>> getUnsyncedPackets();

  /// Marks packets as synced after successful server delivery
  Future<void> markPacketsAsSynced(List<String> dids);
  
  /// Hazard Zone Caching
  Future<void> cacheHazardZones(List<String> h3Indices);
  Future<List<String>> getCachedHazardZones();
}

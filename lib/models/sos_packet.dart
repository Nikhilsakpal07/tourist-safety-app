import 'dart:convert';

class SosPacket {
  final String id;
  final String did;
  final String h3Index;
  final int timestamp;
  final String emergencyType;
  final String signature;
  final int isRelayed;

  SosPacket({
    required this.id,
    required this.did,
    required this.h3Index,
    required this.timestamp,
    required this.emergencyType,
    required this.signature,
    this.isRelayed = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'did': did,
    'h3_index': h3Index,
    'timestamp': timestamp,
    'emergency_type': emergencyType,
    'signature': signature,
    'is_relayed': isRelayed,
  };

  factory SosPacket.fromMap(Map<String, dynamic> map) => SosPacket(
    id: map['id'] as String,
    did: map['did'] as String,
    h3Index: map['h3_index'] as String,
    timestamp: map['timestamp'] as int,
    emergencyType: map['emergency_type'] as String,
    signature: map['signature'] as String,
    isRelayed: map['is_relayed'] as int? ?? 0,
  );

  String toJsonString() => jsonEncode(toMap());
}
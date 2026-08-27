import 'dart:convert';

class TouristPermit {
  final String did;
  final String touristName;
  final String permitId;
  final int validUntil;
  final String emergencyContact;
  final String signature;

  TouristPermit({
    required this.did,
    required this.touristName,
    required this.permitId,
    required this.validUntil,
    required this.emergencyContact,
    this.signature = '',
  });

  /// The raw payload string that gets cryptographically signed
  String toSignablePayload() {
    return '$did|$touristName|$permitId|$validUntil|$emergencyContact';
  }

  Map<String, dynamic> toJson() => {
    'did': did,
    'name': touristName,
    'permitId': permitId,
    'expiry': validUntil,
    'contact': emergencyContact,
    'sig': signature,
  };

  factory TouristPermit.fromJson(Map<String, dynamic> json) => TouristPermit(
    did: json['did'] as String,
    touristName: json['name'] as String,
    permitId: json['permitId'] as String,
    validUntil: json['expiry'] as int,
    emergencyContact: json['contact'] as String,
    signature: json['sig'] as String? ?? '',
  );

  String toQrString() => jsonEncode(toJson());

  factory TouristPermit.fromQrString(String raw) =>
      TouristPermit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
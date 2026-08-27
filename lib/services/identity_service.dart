import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:posaic_app/models/permit_model.dart';

class IdentityService {
  final Ed25519 _signAlgorithm = Ed25519();
  // Standard ChaCha20-Poly1305 AEAD algorithm
  final Cipher _cipherAlgorithm = Chacha20.poly1305Aead();

  // Pre-shared Authority Secret Key for prototype (32 bytes)
  static final List<int> _preSharedAuthorityKey =
      utf8.encode('POSAIC_TOURISM_OFFLINE_KEY_2026_');

  // Cached DID for seamless multi-view access
  static String? _cachedDid;

  /// Generates or retrieves the device's decentralized identifier (DID)
  static Future<String> getOrCreateDID() async {
    if (_cachedDid != null) return _cachedDid!;
    final service = IdentityService();
    final keyPair = await service.generateDeviceIdentity();
    _cachedDid = await service.getDidFromKeyPair(keyPair);
    return _cachedDid!;
  }

  Future<SimpleKeyPair> generateDeviceIdentity() async {
    return await _signAlgorithm.newKeyPair();
  }

  Future<String> getDidFromKeyPair(SimpleKeyPair keyPair) async {
    final pubKey = await keyPair.extractPublicKey();
    final hexPub = base64Url.encode(pubKey.bytes);
    return 'did:key:z$hexPub';
  }

  /// 1. Signs permit with Authority Private Key
  /// 2. Encrypts payload with Authority AEAD Key
  Future<String> issueEncryptedPermitQr({
    required SimpleKeyPair authorityKeyPair,
    required String touristDid,
    required String touristName,
    required String permitId,
    required int expiryEpochSeconds,
    required String emergencyContact,
  }) async {
    final basePermit = TouristPermit(
      did: touristDid,
      touristName: touristName,
      permitId: permitId,
      validUntil: expiryEpochSeconds,
      emergencyContact: emergencyContact,
    );

    // Step A: Cryptographic Sign
    final rawBytes = utf8.encode(basePermit.toSignablePayload());
    final signature =
        await _signAlgorithm.sign(rawBytes, keyPair: authorityKeyPair);

    final signedPermit = TouristPermit(
      did: touristDid,
      touristName: touristName,
      permitId: permitId,
      validUntil: expiryEpochSeconds,
      emergencyContact: emergencyContact,
      signature: base64Encode(signature.bytes),
    );

    // Step B: Authenticated Encryption
    final plainTextBytes = utf8.encode(signedPermit.toQrString());
    final secretKey = SecretKey(_preSharedAuthorityKey);
    final secretBox =
        await _cipherAlgorithm.encrypt(plainTextBytes, secretKey: secretKey);

    // Package cipher payload + nonce + mac into single JSON QR string
    final encryptedPackage = {
      'c': base64Encode(secretBox.cipherText),
      'n': base64Encode(secretBox.nonce),
      'm': base64Encode(secretBox.mac.bytes),
    };

    return jsonEncode(encryptedPackage);
  }

  /// 1. Decrypts payload using shared secret
  /// 2. Verifies signature against Authority Public Key
  Future<({bool isValid, TouristPermit? permit, String message})>
      decryptAndVerifyPermitOffline({
    required String qrRawString,
    required PublicKey authorityPublicKey,
  }) async {
    try {
      final Map<String, dynamic> encryptedMap = jsonDecode(qrRawString);
      final cipherBytes = base64Decode(encryptedMap['c'] as String);
      final nonceBytes = base64Decode(encryptedMap['n'] as String);
      final macBytes = base64Decode(encryptedMap['m'] as String);

      final secretBox = SecretBox(
        cipherBytes,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );

      final secretKey = SecretKey(_preSharedAuthorityKey);
      final decryptedBytes =
          await _cipherAlgorithm.decrypt(secretBox, secretKey: secretKey);
      final decryptedJson = utf8.decode(decryptedBytes);

      final permit = TouristPermit.fromQrString(decryptedJson);

      // Verify Ed25519 signature
      final payloadBytes = utf8.encode(permit.toSignablePayload());
      final signatureBytes = base64Decode(permit.signature);
      final signature =
          Signature(signatureBytes, publicKey: authorityPublicKey);

      final isValidSignature =
          await _signAlgorithm.verify(payloadBytes, signature: signature);
      final isNotExpired =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) <= permit.validUntil;

      if (!isValidSignature) {
        return (
          isValid: false,
          permit: permit,
          message: 'SIGNATURE FORGED / TAMPERED'
        );
      }
      if (!isNotExpired) {
        return (isValid: false, permit: permit, message: 'PERMIT EXPIRED');
      }

      return (
        isValid: true,
        permit: permit,
        message: 'VERIFIED CRYPTOGRAPHICALLY (OFFLINE)'
      );
    } catch (_) {
      return (
        isValid: false,
        permit: null,
        message: 'DECRYPTION FAILED: UNAUTHORIZED / CORRUPTED QR'
      );
    }
  }
}
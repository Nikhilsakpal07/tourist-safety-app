import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:posaic_app/services/identity_service.dart';
import 'package:posaic_app/models/permit_model.dart';

class PermitQrView extends StatefulWidget {
  const PermitQrView({super.key});

  @override
  State<PermitQrView> createState() => _PermitQrViewState();
}

class _PermitQrViewState extends State<PermitQrView> {
  final IdentityService _identityService = IdentityService();
  String? _encryptedQrPayload;
  TouristPermit? _previewPermit;
  PublicKey? _authorityPublicKey;
  String _verificationStatus = 'Pending Verification';
  bool? _isValid;

  @override
  void initState() {
    super.initState();
    _bootstrapEncryptedPermit();
  }

  Future<void> _bootstrapEncryptedPermit() async {
    final authorityKeyPair = await _identityService.generateDeviceIdentity();
    _authorityPublicKey = await authorityKeyPair.extractPublicKey();

    final userKeyPair = await _identityService.generateDeviceIdentity();
    final userDid = await _identityService.getDidFromKeyPair(userKeyPair);

    _previewPermit = TouristPermit(
      did: userDid,
      touristName: 'Nikhil (Explorer)',
      permitId: 'PERMIT-2026-X89',
      validUntil: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400,
      emergencyContact: '+91 98765 43210',
    );

    final encryptedQrString = await _identityService.issueEncryptedPermitQr(
      authorityKeyPair: authorityKeyPair,
      touristDid: userDid,
      touristName: _previewPermit!.touristName,
      permitId: _previewPermit!.permitId,
      expiryEpochSeconds: _previewPermit!.validUntil,
      emergencyContact: _previewPermit!.emergencyContact,
    );

    setState(() {
      _encryptedQrPayload = encryptedQrString;
    });
  }

  Future<void> _verifyEncryptedOffline() async {
    if (_encryptedQrPayload == null || _authorityPublicKey == null) return;

    final result = await _identityService.decryptAndVerifyPermitOffline(
      qrRawString: _encryptedQrPayload!,
      authorityPublicKey: _authorityPublicKey!,
    );

    setState(() {
      _isValid = result.isValid;
      _verificationStatus = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_encryptedQrPayload == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Encrypted Permit Vault')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: _encryptedQrPayload!,
                        version: QrVersions.auto,
                        size: 200.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _previewPermit!.touristName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Permit ID: ${_previewPermit!.permitId}',
                      style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: Encrypted with AES-256-GCM',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _verifyEncryptedOffline,
              icon: const Icon(Icons.lock_open),
              label: const Text('Simulate Ranger Decrypt & Verify (Offline)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _verificationStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isValid == true
                    ? Colors.greenAccent
                    : (_isValid == false ? Colors.redAccent : Colors.amberAccent),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../core/interfaces/services.dart';

class SosView extends StatefulWidget {
  final ISosMeshService meshService;

  const SosView({Key? key, required this.meshService}) : super(key: key);

  @override
  _SosViewState createState() => _SosViewState();
}

class _SosViewState extends State<SosView> {
  bool _isSending = false;
  bool _isMuleModeActive = false;

  void _triggerSos() async {
    setState(() {
      _isSending = true;
    });
    
    try {
      final packet = await widget.meshService.triggerSos();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('🆘 SOS Transmitted'),
            content: Text(
              'Your distress beacon has been broadcasted.\n\n'
              'Details:\n'
              'DID: ${packet.did}\n'
              'H3 Hex: ${packet.h3Index}\n'
              'Time: ${DateTime.fromMillisecondsSinceEpoch(packet.timestamp)}\n\n'
              'Nearby mules and cell towers are listening.'
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
            ],
          )
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to trigger SOS: $e')),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _toggleMuleMode() async {
    if (_isMuleModeActive) {
      await widget.meshService.stopSilentRelayScanner();
      if (mounted) {
        setState(() {
          _isMuleModeActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silent Relay (Mule Mode) Disabled')),
        );
      }
      return;
    }

    try {
      await widget.meshService.startSilentRelayScanner();
      if (mounted) {
        setState(() {
          _isMuleModeActive = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silent Relay (Mule Mode) Enabled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start Mule Mode: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Mesh Engine'),
        backgroundColor: Colors.red[800],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'VICTIM MODE',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _isSending ? null : _triggerSos,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _isSending ? Colors.grey : Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      spreadRadius: 10,
                      blurRadius: 20,
                    )
                  ],
                ),
                child: Center(
                  child: Text(
                    _isSending ? 'SENDING...' : 'SOS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 60),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              'MULE MODE (BACKGROUND)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _toggleMuleMode,
              icon: Icon(_isMuleModeActive ? Icons.stop : Icons.bluetooth_audio),
              label: Text(_isMuleModeActive ? 'Disable Silent Relay Scanner' : 'Enable Silent Relay Scanner'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMuleModeActive ? Colors.grey : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Mule mode listens for nearby SOS beacons over BLE and stores them locally to forward when internet is available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          ],
        ),
      ),
    );
  }
}

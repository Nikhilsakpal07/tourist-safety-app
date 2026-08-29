import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:posaic_app/models/sos_packet.dart';

class CloudService {
  // Use http://10.0.2.2:8000 for Android Emulator
  // Use http://127.0.0.1:8000 for Desktop / Chrome Web
  // Use http://<YOUR_LAN_IP>:8000 (e.g. 192.168.1.X) for physical devices on Wi-Fi
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Fetches active dynamic hazard H3 hex cells computed by the FastAPI authority backend
  static Future<List<String>> fetchDynamicHazardHexes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/v1/zones/active'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> cells = data['h3_cells'] ?? [];
        return cells.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Fallback to local offline cache if backend is unreachable
    }
    return [];
  }

  /// Alias for backward compatibility
  static Future<List<String>> fetchActiveHazards() => fetchDynamicHazardHexes();

  /// Pushes queued/direct distress packets to the cloud authority database
  static Future<bool> syncSosPacketsToCloud(List<SosPacket> packets) async {
    if (packets.isEmpty) return true;

    try {
      final payload = packets.map((p) => {
        'id': p.id,
        'did': p.did,
        'h3_index': p.h3Index,
        'timestamp': p.timestamp,
        'emergency_type': p.emergencyType,
        'signature': p.signature,
      }).toList();

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/mesh/sync-sos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
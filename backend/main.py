import http.server
import socketserver
import json
import time
from urllib.parse import urlparse

PORT = 8000
received_packets = {}

class MockFastAPIHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == "/api/v1/zones/active":
            # Mock H3 hex indices (e.g. San Francisco)
            zones = [
                "88283082a1fffff", 
                "88283082a3fffff", 
                "88283082a9fffff"
            ]
            response = {
                "zones": zones, 
                "resolution": 8, 
                "timestamp": int(time.time())
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode('utf-8'))
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == "/api/v1/mesh/sync-sos":
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                channel = data.get('channel', 'UNKNOWN')
                packets = data.get('packets', [])
                
                new_inserts = 0
                for packet in packets:
                    did = packet.get('did')
                    timestamp = packet.get('timestamp')
                    dedup_key = f"{did}_{timestamp}"
                    
                    if dedup_key not in received_packets:
                        received_packets[dedup_key] = {
                            "packet": packet,
                            "channel": channel,
                            "received_at": int(time.time())
                        }
                        new_inserts += 1
                        
                        # --- Print alert to terminal ---
                        print("\n" + "="*50)
                        print(f"🚨 SOS BEACON RECEIVED VIA {channel} 🚨")
                        print(f"Victim DID : {did}")
                        print(f"H3 Hex Cell: {packet.get('h3_index')}")
                        print(f"Timestamp  : {timestamp}")
                        print("="*50 + "\n")
                        
                response = {
                    "status": "success",
                    "processed": len(packets),
                    "new_inserts": new_inserts,
                    "total_unique": len(received_packets)
                }
                
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response).encode('utf-8'))
                
            except json.JSONDecodeError:
                self.send_error(400, "Bad Request: Invalid JSON")
        else:
            self.send_error(404, "Not Found")

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), MockFastAPIHandler) as httpd:
        print(f"Starting lightweight backend server at http://127.0.0.1:{PORT}")
        print("Listening for /api/v1/zones/active (GET) and /api/v1/mesh/sync-sos (POST)...")
        httpd.serve_forever()

import base64
import time
import requests
from typing import List, Dict, Any, Set
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
import h3

app = FastAPI(
    title="POSAIC Dynamic Autonomous Safety & Hazard Authority",
    version="3.0.0"
)

# Enable CORS for Mobile Apps, Emulators & Web Dashboards
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 1. Authority Master Signing Keys (Ed25519)
AUTHORITY_PRIVATE_KEY = ed25519.Ed25519PrivateKey.generate()
AUTHORITY_PUBLIC_KEY = AUTHORITY_PRIVATE_KEY.public_key()
AUTHORITY_PUBLIC_KEY_BYTES = AUTHORITY_PUBLIC_KEY.public_bytes_raw()

# 2. Pre-shared 256-bit symmetric key for dynamic QR permit encryption
PRESHARED_SECRET = b"POSAIC_TOURISM_OFFLINE_KEY_2026_"
chacha = ChaCha20Poly1305(PRESHARED_SECRET)

# Dynamic state tracking
DYNAMIC_HAZARDS: Set[str] = set()
ACTIVE_EMERGENCIES: Dict[str, Dict[str, Any]] = {}


# --- Data Models ---
class PermitRequest(BaseModel):
    tourist_name: str
    tourist_did: str
    emergency_contact: str
    validity_hours: int = 24


class SosPacketIn(BaseModel):
    id: str
    did: str
    h3_index: str
    timestamp: int
    emergency_type: str
    signature: str


# --- 100% Dynamic Web Hazard Harvester (Zero Hardcoded Coordinates) ---
def fetch_external_live_hazards(bbox: tuple = (18.85, 72.75, 19.35, 73.15)) -> Set[str]:
    """
    Dynamically discovers and aggregates hazards purely from live web APIs:
    1. Open-Meteo: Real-time precipitation and wind gusts.
    2. USGS: Live real-time seismic disturbances and ground instability triggers.
    3. OpenStreetMap (Overpass API): Live geographic hazard features (cliffs, ravines, protected wilderness, water bodies).
    """
    hazard_hexes: Set[str] = set()
    min_lat, min_lon, max_lat, max_lon = bbox

    # 1. Live Weather Conditions Trigger (Open-Meteo API)
    has_severe_weather = False
    try:
        center_lat = (min_lat + max_lat) / 2
        center_lon = (min_lon + max_lon) / 2
        weather_url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={center_lat}&longitude={center_lon}"
            f"&current=precipitation,rain,wind_speed_10m,weather_code"
            f"&timezone=auto"
        )
        res = requests.get(weather_url, timeout=5).json()
        current = res.get("current", {})
        rain = current.get("precipitation", 0)
        wind = current.get("wind_speed_10m", 0)

        # Flag flood/storm conditions dynamically
        has_severe_weather = rain > 1.5 or wind > 30.0
    except Exception as e:
        print(f"[WARN] Weather API query failed: {e}")

    # 2. Live Global Seismicity & Fault Shift Trigger (USGS API)
    try:
        usgs_url = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson"
        res = requests.get(usgs_url, timeout=5).json()
        for feature in res.get("features", []):
            coords = feature.get("geometry", {}).get("coordinates", [])
            if len(coords) >= 2:
                lon, lat = coords[0], coords[1]
                # If disturbance falls inside the operational boundary
                if min_lat <= lat <= max_lat and min_lon <= lon <= max_lon:
                    center_hex = h3.latlng_to_cell(lat, lon, res=8)
                    hazard_hexes.update(h3.grid_disk(center_hex, 1))
    except Exception as e:
        print(f"[WARN] USGS Seismicity query failed: {e}")

    # 3. Dynamic Physical Hazard Extraction via OpenStreetMap Overpass API
    try:
        overpass_url = "https://overpass-api.de/api/interpreter"
        query = f"""
        [out:json][timeout:10];
        (
          node["natural"="cliff"]({min_lat},{min_lon},{max_lat},{max_lon});
          node["natural"="wetland"]({min_lat},{min_lon},{max_lat},{max_lon});
          way["boundary"="protected_area"]({min_lat},{min_lon},{max_lat},{max_lon});
          way["natural"="water"]({min_lat},{min_lon},{max_lat},{max_lon});
        );
        out center 40;
        """
        response = requests.post(overpass_url, data={"data": query}, timeout=10)
        if response.status_code == 200:
            osm_data = response.json()
            for element in osm_data.get("elements", []):
                lat = element.get("lat") or element.get("center", {}).get("lat")
                lon = element.get("lon") or element.get("center", {}).get("lon")
                if lat and lon:
                    tags = element.get("tags", {})
                    is_water = tags.get("natural") in ["water", "wetland"]
                    # If high wind/rain, automatically convert all live water bodies to flood hazards
                    if not is_water or has_severe_weather:
                        hex_id = h3.latlng_to_cell(lat, lon, res=8)
                        hazard_hexes.add(hex_id)
    except Exception as e:
        print(f"[WARN] Overpass OSM query failed: {e}")

    return hazard_hexes


@app.on_event("startup")
def startup_event():
    """Dynamically ingests hazards from public APIs on startup."""
    global DYNAMIC_HAZARDS
    DYNAMIC_HAZARDS = fetch_external_live_hazards()
    print(f"[INIT] Dynamically discovered {len(DYNAMIC_HAZARDS)} active H3 hazard hexes from OSM, Weather & USGS feeds.")


# --- API Endpoints ---

@app.get("/")
def root():
    return {
        "service": "POSAIC Dynamic Hazard & SOS Authority",
        "status": "ONLINE",
        "dynamic_hazard_hexes_count": len(DYNAMIC_HAZARDS),
        "total_active_emergencies": len(ACTIVE_EMERGENCIES),
    }


@app.get("/api/v1/authority/public-key")
def get_authority_public_key():
    """Provides Authority Ed25519 public key for offline cryptographic verification."""
    return {
        "algorithm": "Ed25519",
        "public_key_base64": base64.b64encode(AUTHORITY_PUBLIC_KEY_BYTES).decode("utf-8"),
    }


@app.get("/api/v1/zones/active")
def get_active_hazard_hexes():
    """Serves pure dynamic H3 hazard cells fetched live from the web."""
    return {
        "h3_resolution": 8,
        "count": len(DYNAMIC_HAZARDS),
        "h3_cells": list(DYNAMIC_HAZARDS),
    }


@app.post("/api/v1/zones/refresh")
def refresh_hazard_zones(background_tasks: BackgroundTasks):
    """Triggers an on-demand async reload of all dynamic web hazard sources."""
    def refresh_task():
        global DYNAMIC_HAZARDS
        DYNAMIC_HAZARDS = fetch_external_live_hazards()

    background_tasks.add_task(refresh_task)
    return {"status": "REFRESH_SCHEDULED", "message": "Harvesting live geo-hazards from public web feeds."}


@app.post("/api/v1/permits/issue")
def issue_permit(req: PermitRequest):
    """Issues and cryptographically signs a digital tourist permit."""
    permit_id = f"PERMIT-2026-{int(time.time() * 1000) % 1000000}"
    expiry_epoch = int(time.time()) + (req.validity_hours * 3600)

    payload_str = f"{req.tourist_did}|{req.tourist_name}|{permit_id}|{expiry_epoch}|{req.emergency_contact}"
    signature_bytes = AUTHORITY_PRIVATE_KEY.sign(payload_str.encode("utf-8"))
    signature_b64 = base64.b64encode(signature_bytes).decode("utf-8")

    permit_dict = {
        "did": req.tourist_did,
        "name": req.tourist_name,
        "permitId": permit_id,
        "expiry": expiry_epoch,
        "contact": req.emergency_contact,
        "sig": signature_b64,
    }

    nonce = int(time.time() * 1000).to_bytes(12, "big")
    raw_json = str(permit_dict).replace("'", '"').encode("utf-8")
    ciphertext = chacha.encrypt(nonce, raw_json, None)

    return {
        "status": "ISSUED",
        "permit": permit_dict,
        "encrypted_qr_string": {
            "c": base64.b64encode(ciphertext).decode("utf-8"),
            "n": base64.b64encode(nonce).decode("utf-8"),
            "m": "",
        },
    }


@app.post("/api/v1/mesh/sync-sos")
def sync_sos_relays(packets: List[SosPacketIn]):
    """
    Ingests and deduplicates SOS distress packets by victim DID.
    Distinguishes direct cellular pushes from multi-hop BLE mesh arrivals.
    """
    new_victims = 0
    now = int(time.time())

    for pkt in packets:
        victim_key = pkt.did

        if victim_key not in ACTIVE_EMERGENCIES:
            ACTIVE_EMERGENCIES[victim_key] = {
                "incident_id": pkt.id,
                "victim_did": pkt.did,
                "last_known_h3": pkt.h3_index,
                "emergency_type": pkt.emergency_type,
                "first_reported_epoch": pkt.timestamp,
                "last_synced_epoch": now,
                "relay_hop_confirmations": 1,
                "reception_channel": "DIRECT_CELLULAR" if pkt.timestamp >= now - 5 else "BLE_STORE_AND_FORWARD_MESH",
                "status": "SEARCH_AND_RESCUE_ACTIVE",
            }
            new_victims += 1
        else:
            ACTIVE_EMERGENCIES[victim_key]["last_known_h3"] = pkt.h3_index
            ACTIVE_EMERGENCIES[victim_key]["last_synced_epoch"] = now
            ACTIVE_EMERGENCIES[victim_key]["relay_hop_confirmations"] += 1
            if pkt.timestamp < now - 10:
                ACTIVE_EMERGENCIES[victim_key]["reception_channel"] = "BLE_STORE_AND_FORWARD_MESH"

    return {
        "status": "SUCCESS",
        "new_emergencies_registered": new_victims,
        "total_active_emergencies": len(ACTIVE_EMERGENCIES),
    }


@app.get("/api/v1/incidents/active")
def get_active_incidents():
    """Live authority command feed of active incidents."""
    emergencies_list = list(ACTIVE_EMERGENCIES.values())
    return {
        "total_active_emergencies": len(emergencies_list),
        "emergencies": emergencies_list,
    }
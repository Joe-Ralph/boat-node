# BoatNode — Developer README

## What this repo contains
- `BoatNode_v0.1.cpp` — full Arduino sketch (ESP32) implementing:
  - Wi-Fi pairing SoftAP (`/pair`, `/reset`) and rescue SoftAP (`/status`, `/request_fix`, `/beacon`)
  - RGB LED state machine (includes **green blink** when LoRaWAN reachable but no mesh)
  - LoRa mesh (SX1276 / RFM95 via RadioLib)
  - LoRaWAN OTAA fallback/bridge (LMIC)
  - GPS parsing (TinyGPSPlus, UART2)
  - Battery ADC monitoring, buzzer control
- Wiring diagrams (PNG): `BoatNode_Wiring_v1.png`, `BoatNode_ElectricalSchematic_v2.png`
- User manual PDF: `BoatNode_User_Manual_v0.1.pdf`

---

## Quick goals
- Proof-of-concept boat telemetry node.
- Pair via phone app to assign `boat_id`. Radios remain off until paired.
- Mesh-first forwarding; LoRaWAN uplink fallback and bridge by nodes that are joined.

---

## Build & dependencies
- **Platform**: ESP32 (DevKit WROOM). Use Arduino IDE or PlatformIO.
- **Libraries**:
  - `RadioLib`
  - `TinyGPSPlus`
  - `MCCI LMIC` (mcci-catena/arduino-lmic)
  - `Preferences` (part of ESP32 core)

**Example `platformio.ini`**
```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
lib_deps =
  RadioLib
  TinyGPSPlus
  mcci-catena/arduino-lmic
build_flags = -DCORE_DEBUG_LEVEL=ARDUHAL_LOG_LEVEL_INFO
monitor_speed = 115200
```
## Pin mapping (default in code) — verify before wiring
- SPI (VSPI): `SCK=18`, `MISO=19`, `MOSI=23`
- LoRa:
  - `NSS/CS = GPIO5`
  - `DIO0 = GPIO26`
  - `RST  = GPIO14`
- GPS: `GPS TX -> ESP RX2 = GPIO16`
- Button (to GND): `GPIO0` (INPUT_PULLUP)
- Battery ADC: `GPIO34` (ADC1)
- RGB LED (common-cathode): `R=GPIO15`, `G=GPIO4`, `B=GPIO13`
- Buzzer control -> `GPIO27` (1k -> NPN base)
- Optional PowerBoost STAT -> `GPIO35`

> Change these `PIN_*` constants at the top of `BoatNode_v0.1.cpp` if your wiring differs.

---

## Configurable parameters (in code)
Edit values near the top of the sketch:
- `MESH_FREQ_MHZ`, `MESH_SF`, `MESH_TX_DBM`, `MESH_STALE_MS`
- `REPORT_SEC`, `REPORT_JITTER_S`
- LoRaWAN OTAA keys: `APPEUI`, `DEVEUI`, `APPKEY` (must replace)
- Wi-Fi AP PSK: `PAIR_AP_PSK`
- ADC divider constants: `ADC_R_TOP`, `ADC_R_BOT` (if you change resistors)

**Note:** LMIC channel setup is for IN865. Adapt channels to your gateway/network.

---

## High-level code layout
1. **Includes & config** — libraries and constants.
2. **Pin definitions** — single place to change hardware mapping.
3. **Objects** — `SX1276 lora`, `TinyGPSPlus gps`, `WebServer http`, `Preferences prefs`.
4. **Globals / state** — pairing flag, boat id, caches, timers.
5. **Utility functions** — CRC16, ADC read, battery percent.
6. **NVS (pairing)** — `loadPairing()`, `savePairing()`, `clearPairing()`.
7. **LED state machine** — `ledUpdate()`, `updateLedByComms()`.
8. **Wi-Fi endpoints** — `startPairingAP()`, `/pair`, `/reset`; rescue endpoints `/status`, `/beacon`, `/request_fix`.
9. **LMIC glue** — LMIC callbacks and `lorawanInit()`.
10. **RadioLib mesh** — init, send/receive, simple flood with dedupe.
11. **Payload build & bridge** — `buildPkt()` and `bridgeToWAN()`.
12. **setup() / loop()** — initialization, GPS loop, mesh handling, periodic send scheduler, LED updates.

---

## Pairing protocol (concise)
- Device starts **unpaired** → starts SoftAP `BOAT-PAIR-XXXX`.
- App connects to SoftAP (PSK `pairme-1234` by default) and POSTs:
  ```json
  { "boat_id": "B1234" }
  ``` to http://192.168.4.1/pair.
- Device returns `{"ok":true,"boat_id":"B1234"}` and shows long-blue for 3s, starts radios.
- Factory reset: POST /reset or clear NVS.

**Security note:** SoftAP pairing is low-security by design. For production add OTP or printed sticker code.

## Operative behaviour summary
- **Before pairing**: SoftAP only; LED double-blue.
- **After pairing**: long-blue then radios initialize.
- **Periodic behavior:** Every `REPORT_SEC` the node builds a compact GPS packet:
  - If mesh recently heard → send to mesh (mesh-first).
  - Else if LoRaWAN joined → send as LoRaWAN uplink.
  - Else attempt mesh send anyway.
- **Bridge behaviour:** Nodes that are WAN-joined bridge received mesh packets upstream (rate-limited).
- **Rescue:** button starts rescue SoftAP for 10 minutes. App can request beacon/beep or fresh GPS.

---

## LED mapping (user-facing)
- **Double short blue (repeat):** Not paired, ready to pair.
- **Long blue (3s):** Pairing successful.
- **Solid green:** LoRaWAN reachable **and** mesh active.
- **Blinking green:** LoRaWAN reachable but **no** mesh heard recently (new state).
- **Blinking red:** Mesh active but LoRaWAN not reachable.
- **Solid red:** No mesh and no LoRaWAN (no communication).

---

## Testing checklist (bench)
1. Power node with PowerBoost + 18650. Confirm double-blue on first boot.
2. Pair via phone:
   - Connect to `BOAT-PAIR-XXXX` (PSK `pairme-1234`).
   - `curl -X POST -d '{"boat_id":"1234"}' http://192.168.4.1/pair`
   - Expect `{"ok":true}` and long-blue.
3. GPS fix: verify `gps.location.isValid()` in serial logs.
4. Mesh send/receive: test two nodes nearby for flood and dedupe.
5. LoRaWAN join: confirm `EV_JOINED` after OTAA if gateway/NS set up.
6. LED states: simulate WAN & mesh combos and verify LED responses.
7. Battery ADC: compare measured voltage with ADC-derived percent.

---

## Production considerations & TODOs
- Persist `seqno` to NVS to survive reboots (avoid reuse).
- Separate LMIC and RadioLib into tasks or guard SPI access; avoid radio collisions.
- Improve mesh collision avoidance (CSMA/backoff).
- Add secure pairing (OTP or printed device code).
- Add OTA update path (careful—use Wi-Fi for firmware updates).

---

## Common pitfalls
- **TP4056 without power-path** will cause instability while charging. Use PowerBoost 1000C or TP5100-style module.
- **Antenna placement** – must be outside, vertical, and away from metal.
- **LMIC channels** must match the network server/gateway settings.

---

## Quick edits (where to change behavior)
- `REPORT_SEC`, `REPORT_JITTER_S` — reporting cadence.
- `MESH_SF`, `MESH_TX_DBM` — link budget and range tuning.
- `MESH_STALE_MS` — how long you consider mesh “recent” (affects LED and send logic).
- `PAIR_AP_PSK` — pairing password.
- `APPEUI/DEVEUI/APPKEY` — LoRaWAN keys.

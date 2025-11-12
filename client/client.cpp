/*
  Boat Node v0.1 - Full firmware with comments

  Features:
    - Pairing via Wi-Fi SoftAP (/pair endpoint). Boat ID persisted to NVS.
    - RGB LED state machine:
        * Double short blue repeating = not paired (pairing mode)
        * Long blue (3s) = paired success
        * Solid green = LoRaWAN reachable AND mesh active
        * Blinking green = LoRaWAN reachable, NO mesh heard recently
        * Blinking red = mesh active, LoRaWAN NOT reachable
        * Solid red = neither mesh nor LoRaWAN reachable
    - LoRa mesh (SX1276 / RFM95) flood with dedupe and hop count
    - LoRaWAN OTAA fallback / bridge (LMIC) for nodes joined to network
    - GPS via UART2 (TinyGPSPlus)
    - Wi-Fi Rescue SoftAP (/status, /request_fix, /beacon)
    - Battery ADC reading via resistor divider
    - Buzzer driven through NPN from GPIO
    - All radios remain off until device is paired (pairing enables radios)

  Hardware assumptions (match wiring to pins below):
    - PowerBoost 1000C supplies 5V to ESP32 VIN
    - ESP32 onboard 3.3V powers LoRa module
    - LoRa RFM95 / SX1276 connected via SPI
    - GPS (NEO-6M/8M) TX -> ESP32 RX2 (GPIO16)
    - RGB LED is common-cathode (HIGH = LED on). Invert logic if common-anode.

  Author: Generated for user (v0.1)
*/

#include <Arduino.h>
#include <SPI.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <RadioLib.h>
#include <TinyGPSPlus.h>

// LMIC headers require C linkage
extern "C" {
  #include <lmic.h>
  #include <hal/hal.h>
}

/* =========================
   ========== CONFIG =======
   ========================= */

/* Frequency / region:
   Using IN865 region example (India). Adjust frequencies for your country.
*/
const float MESH_FREQ_MHZ = 865.2; // primary mesh frequency
const uint8_t MESH_SF = 9;         // mesh default SF
const uint8_t MESH_SF_RETRY = 11;  // higher SF for retry
const int8_t MESH_TX_DBM = 14;     // transmit power (respect local limits)
const uint32_t MESH_STALE_MS = 10UL * 60UL * 1000UL; // 10 minutes window

// Reporting timing
const uint16_t REPORT_SEC = 120;       // base reporting interval (seconds)
const uint16_t REPORT_JITTER_S = 20;   // jitter window (seconds)

/* LoRaWAN OTAA keys.
   LMIC expects APPEUI and DEVEUI in little-endian order in the os_get* callbacks,
   APPKEY in big-endian. Replace these before deployment.
*/
static const u1_t PROGMEM APPEUI[8] =  { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
static const u1_t PROGMEM DEVEUI[8] =  { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
static const u1_t PROGMEM APPKEY[16] = { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                                         0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const uint8_t LORAWAN_FPORT = 10; // port for bridged mesh packets

/* Wi-Fi pairing / rescue */
const char* PAIR_AP_PREFIX = "BOAT-PAIR-";
const char* PAIR_AP_PSK = "pairme-1234"; // optional PSK for pairing AP
const uint32_t PAIR_TIMEOUT_MS = 10UL * 60UL * 1000UL;
const uint32_t RESCUE_TTL_MS   = 10UL * 60UL * 1000UL;

/* =========================
   ========== PINS =========
   =========================
   Edit these if your wiring differs.
*/
const int PIN_LORA_NSS   = 5;   // CS / NSS for RFM95
const int PIN_LORA_DIO0  = 26;  // DIO0 interrupt
const int PIN_LORA_RST   = 14;  // reset
// SPI uses VSPI default: SCK=18, MISO=19, MOSI=23

const int PIN_GPS_RX     = 16;  // GPS TX -> ESP32 RX2 (GPIO16)
const int PIN_BTN        = 0;   // Rescue / Pair button (to GND)
const int PIN_BATT_ADC   = 34;  // ADC1 channel for battery divider
const int PIN_PBOOST_STAT= 35;  // optional STAT pin from PowerBoost

// RGB LED pins (common-cathode assumed; HIGH = ON)
const int PIN_RGB_R      = 15;
const int PIN_RGB_G      = 4;
const int PIN_RGB_B      = 13;

const int PIN_BUZZER_CTRL = 27; // GPIO controlling NPN base (through 1k)

// small status LED (optional)
const int PIN_LED_STATUS  = 2;

/* ADC divider constants
   Choose resistors so that full battery voltage (4.2V) maps below ADC ref (~3.3V)
   Example used: Rtop=10k, Rbot=37k -> scale factor = (Rtop + Rbot) / Rbot
*/
const float ADC_VREF = 3.30;
const float ADC_R_TOP = 10000.0;
const float ADC_R_BOT = 37000.0;
const float ADC_SCALE = (ADC_R_TOP + ADC_R_BOT) / ADC_R_BOT;

/* =========================
   ======= LIB OBJECTS =====
   ========================= */
SX1276 lora = new Module(PIN_LORA_NSS, PIN_LORA_DIO0, PIN_LORA_RST, /*SCK*/ 18);
TinyGPSPlus gps;
HardwareSerial GPSSerial(2);   // UART2 for GPS
WebServer http(80);
Preferences prefs;

/* LMIC pinmap used by LMIC library */
const lmic_pinmap lmic_pins = {
  .nss = PIN_LORA_NSS,
  .rxtx = LMIC_UNUSED_PIN,
  .rst = PIN_LORA_RST,
  .dio = { PIN_LORA_DIO0, LMIC_UNUSED_PIN, LMIC_UNUSED_PIN },
  .rxtx_rx_active = 0,
  .rssi_cal = 0,
  .spi_freq = 8000000,
};

/* =========================
   ======= GLOBALS =========
   ========================= */
bool paired = false;         // true after successful pairing
String boatId = "";          // stored boat id (string)
uint16_t boatId_u16 = 0;     // numeric id used in payloads

volatile bool wanJoined = false;  // LMIC join status
bool meshHeardRecently = false;   // true if we heard mesh packets within MESH_STALE_MS
uint32_t lastMeshHeardMs = 0;

uint32_t nextSendAtMs = 0;   // scheduler for periodic reporting
uint16_t seqno = 0;          // packet sequence number

bool pairingAPon = false;
uint32_t pairingAPOffAt = 0;

bool rescueAPon = false;
uint32_t rescueAPOffAt = 0;

/* Dedupe cache for mesh flooding */
struct Seen { uint16_t src; uint16_t seq; uint32_t ts; };
const int SEEN_MAX = 64;
Seen seen[SEEN_MAX];

/* Simple rate limit for bridging to WAN */
unsigned long lastBridgeAt = 0;

/* =========================
   ====== PAYLOAD TYPE =====
   =========================
   Binary compact packet described previously.
*/
#pragma pack(push,1)
struct Pkt {
  uint16_t src;
  uint16_t seq;
  int32_t lat1e7;
  int32_t lon1e7;
  uint16_t spd_cms;
  uint16_t hdg_cdeg;
  uint8_t batt_pc;
  uint8_t hops;
  uint16_t crc;
};
#pragma pack(pop)

/* =========================
   ===== LED STATE MACHINE =
   ========================= */
enum LedState {
  LED_OFF,
  LED_GREEN_SOLID,
  LED_GREEN_BLINK,   // new: LoRaWAN reachable but NO mesh
  LED_RED_SOLID,
  LED_RED_BLINK,
  LED_BLUE_PAIRING,
  LED_BLUE_PAIRED
};
volatile LedState ledState = LED_OFF;
uint32_t ledStamp = 0; // timestamp for long-blue duration

/* =========================
   ===== Utility functions =
   ========================= */

/* CRC-16 (CCITT) for payload integrity */
uint16_t crc16_ccitt(const uint8_t* data, size_t len) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < len; ++i) {
    crc ^= (uint16_t)data[i] << 8;
    for (int j = 0; j < 8; ++j) {
      if (crc & 0x8000) crc = (crc << 1) ^ 0x1021;
      else crc <<= 1;
    }
  }
  return crc;
}

/* seen cache operations */
int findSeen(uint16_t s, uint16_t q) {
  for (int i = 0; i < SEEN_MAX; ++i)
    if (seen[i].src == s && seen[i].seq == q) return i;
  return -1;
}
void rememberSeen(uint16_t s, uint16_t q) {
  int idx = -1; uint32_t oldest = UINT32_MAX;
  for (int i=0;i<SEEN_MAX;i++){
    if (seen[i].ts == 0) { idx = i; break; }
    if (seen[i].ts < oldest) { oldest = seen[i].ts; idx = i; }
  }
  if (idx >= 0) { seen[idx].src = s; seen[idx].seq = q; seen[idx].ts = millis(); }
}

/* read battery voltage via ADC and divider */
float readBatteryVoltage() {
  uint16_t raw = analogRead(PIN_BATT_ADC); // ADC reading 0..4095 (12-bit)
  float v = (raw / 4095.0f) * ADC_VREF * ADC_SCALE;
  return v;
}
uint8_t batteryPercentFromVoltage(float v) {
  if (v < 3.2f) return 0;
  if (v > 4.15f) return 100;
  return (uint8_t) round((v - 3.2f) / (4.15f - 3.2f) * 100.0);
}

/* ========== NVS pairing (Preferences) ========== */
/* Store boat id and paired flag; called infrequently (pair/reset). */
const char* NVS_NS = "boat_cfg";
const char* NVS_KEY_BOATID = "boat_id";
const char* NVS_KEY_PAIRED = "paired";

void loadPairing() {
  prefs.begin(NVS_NS, true);
  if (prefs.isKey(NVS_KEY_PAIRED) && prefs.getBool(NVS_KEY_PAIRED, false)) {
    paired = true;
    boatId = prefs.getString(NVS_KEY_BOATID, "");
    // convert to uint16 (assumes numeric string)
    boatId_u16 = (uint16_t) strtoul(boatId.c_str(), NULL, 0);
  } else {
    paired = false;
    boatId = "";
    boatId_u16 = 0;
  }
  prefs.end();
}
void savePairing(const String &bid) {
  prefs.begin(NVS_NS, false);
  prefs.putBool(NVS_KEY_PAIRED, true);
  prefs.putString(NVS_KEY_BOATID, bid);
  prefs.end();
  paired = true;
  boatId = bid;
  boatId_u16 = (uint16_t) strtoul(boatId.c_str(), NULL, 0);
}
void clearPairing() {
  prefs.begin(NVS_NS, false);
  prefs.clear();
  prefs.end();
  paired = false;
  boatId = "";
  boatId_u16 = 0;
}

/* =========================
   ====== LED functions =====
   ========================= */

/* drive RGB pins (common-cathode) */
void ledSetPins(bool r, bool g, bool b) {
  digitalWrite(PIN_RGB_R, r ? HIGH : LOW);
  digitalWrite(PIN_RGB_G, g ? HIGH : LOW);
  digitalWrite(PIN_RGB_B, b ? HIGH : LOW);
}

/* update LED pattern — called frequently in loop() */
void ledUpdate() {
  uint32_t t = millis();
  switch (ledState) {
    case LED_GREEN_SOLID: ledSetPins(false,true,false); break;
    case LED_GREEN_BLINK:
      // 400 ms on / 400 ms off gives visible blink
      if ((t / 400) % 2 == 0) ledSetPins(false,true,false);
      else ledSetPins(false,false,false);
      break;
    case LED_RED_SOLID: ledSetPins(true,false,false); break;
    case LED_RED_BLINK:
      if ((t / 500) % 2 == 0) ledSetPins(true,false,false);
      else ledSetPins(false,false,false);
      break;
    case LED_BLUE_PAIRING: {
      // double-short-blink pattern repeating: on(100) off(100) on(100) off(600)
      uint32_t cycle = t % 900;
      if (cycle < 100) ledSetPins(false,false,true);
      else if (cycle < 200) ledSetPins(false,false,false);
      else if (cycle < 300) ledSetPins(false,false,true);
      else ledSetPins(false,false,false);
      break;
    }
    case LED_BLUE_PAIRED:
      // long blue for 3 seconds then let status control
      if (t - ledStamp < 3000) ledSetPins(false,false,true);
      break;
    default: ledSetPins(false,false,false); break;
  }
}

/* set LED according to comms; called periodically */
void updateLedByComms() {
  if (!paired) return;
  if (wanJoined) {
    // if WAN joined, prefer green. If mesh present -> steady green.
    // If WAN joined but no mesh recently -> blinking green (new requirement).
    if ((millis() - lastMeshHeardMs) < MESH_STALE_MS) ledState = LED_GREEN_SOLID;
    else ledState = LED_GREEN_BLINK;
  } else {
    // WAN not joined
    if ((millis() - lastMeshHeardMs) < MESH_STALE_MS) ledState = LED_RED_BLINK;
    else ledState = LED_RED_SOLID;
  }
}

/* =========================
   ===== Pairing / Wi-Fi ===
   ========================= */

/* build pairing SSID from efuse MAC */
String makePairSSID() {
  uint64_t mac = ESP.getEfuseMac();
  uint16_t shortid = (uint16_t)(mac & 0xFFFF);
  char buf[24]; snprintf(buf, sizeof(buf), "%s%04X", PAIR_AP_PREFIX, shortid);
  return String(buf);
}

/* pairing HTTP handler (POST /pair)
   Expect body: {"boat_id":"1234"} (simple string parsing).
   On success: save pairing and show long-blue.
*/
void handlePair() {
  if (!pairingAPon) { http.send(403,"application/json","{\"ok\":false,\"err\":\"pairing-off\"}"); return; }
  if (http.method() != HTTP_POST) { http.send(405); return; }
  String body = http.arg("plain");
  int i = body.indexOf("\"boat_id\"");
  if (i < 0) { http.send(400,"application/json","{\"ok\":false}"); return; }
  int col = body.indexOf(':', i);
  int q1 = body.indexOf('"', col);
  int q2 = body.indexOf('"', q1+1);
  if (q1 < 0 || q2 < 0) { http.send(400,"application/json","{\"ok\":false}"); return; }
  String newId = body.substring(q1+1, q2);
  if (newId.length() < 1) { http.send(400,"application/json","{\"ok\":false}"); return; }
  savePairing(newId);
  http.send(200,"application/json", String("{\"ok\":true,\"boat_id\":\"") + newId + "\"}");
  // visual feedback: long blue
  ledState = LED_BLUE_PAIRED;
  ledStamp = millis();
  // schedule pairing AP shutdown soon
  pairingAPOffAt = millis() + 3000;
}

/* factory reset pairing */
void handleReset() {
  clearPairing();
  http.send(200,"application/json","{\"ok\":true}");
  delay(200);
  ESP.restart();
}

/* start pairing SoftAP and HTTP endpoints */
void startPairingAP() {
  if (pairingAPon) return;
  String ssid = makePairSSID();
  // start AP (channel 1), visible open/PSK per config
  WiFi.softAP(ssid.c_str(), PAIR_AP_PSK, 1, false, 4, true);
  http.on("/pair", HTTP_POST, handlePair);
  http.on("/reset", HTTP_POST, handleReset);
  http.begin();
  pairingAPon = true;
  pairingAPOffAt = millis() + PAIR_TIMEOUT_MS;
  // show pairing LED pattern
  ledState = LED_BLUE_PAIRING;
}

/* stop pairing AP */
void stopPairingAP() {
  if (!pairingAPon) return;
  http.stop();
  WiFi.softAPdisconnect(true);
  pairingAPon = false;
}

/* Rescue AP handlers (post-pair)
   /status -> returns JSON with battery, GPS, link states
   /request_fix -> attempts to fetch fresh GPS fix for up to 10 s
   /beacon -> triggers short beep/LED for proximity finding
*/
void handleStatus() {
  float v = readBatteryVoltage();
  String out = "{";
  out += "\"id\":\"" + boatId + "\"";
  out += ",\"battery\":" + String((int)batteryPercentFromVoltage(v));
  out += ",\"voltage\":" + String(v,2);
  out += ",\"gps_valid\":" + String(gps.location.isValid() ? "true":"false");
  out += ",\"lat\":" + String(gps.location.lat(),6);
  out += ",\"lon\":" + String(gps.location.lng(),6);
  out += ",\"wan_joined\":" + String(wanJoined ? "true":"false");
  out += ",\"mesh_recent\":" + String(meshHeardRecently ? "true":"false");
  out += "}";
  http.send(200,"application/json", out);
}

void handleRequestFix() {
  unsigned long start = millis();
  bool ok = false;
  while (millis() - start < 10000UL) { // wait up to 10 s
    while (GPSSerial.available()) gps.encode(GPSSerial.read());
    if (gps.location.isValid() && gps.location.age() < 5000UL) { ok = true; break; }
    delay(200);
  }
  if (ok) http.send(200,"application/json","{\"ok\":true}");
  else http.send(500,"application/json","{\"ok\":false}");
}

void handleBeacon() {
  // short visual/audible cue to help locate
  digitalWrite(PIN_RGB_B, HIGH);
  tone(PIN_BUZZER_CTRL, 2000, 200);
  delay(220);
  digitalWrite(PIN_RGB_B, LOW);
  http.send(200,"application/json","{\"ok\":true}");
}

void startRescueAP() {
  if (rescueAPon) { rescueAPOffAt = millis() + RESCUE_TTL_MS; return; }
  String ssid = "BOAT-" + boatId;
  WiFi.softAP(ssid.c_str(), PAIR_AP_PSK, 1, false, 4, true);
  http.on("/status", HTTP_GET, handleStatus);
  http.on("/request_fix", HTTP_POST, handleRequestFix);
  http.on("/beacon", HTTP_POST, handleBeacon);
  http.begin();
  rescueAPon = true;
  rescueAPOffAt = millis() + RESCUE_TTL_MS;
}

/* =========================
   ===== LoRaWAN (LMIC) ====
   ========================= */
/* Provide LMIC with keys */
void os_getArtEui(u1_t* buf) { memcpy(buf, APPEUI, 8); }
void os_getDevEui(u1_t* buf) { memcpy(buf, DEVEUI, 8); }
void os_getDevKey(u1_t* buf) { memcpy(buf, APPKEY, 16); }

/* LMIC event handler */
void onLmicEvent(ev_t ev) {
  switch (ev) {
    case EV_JOINED: wanJoined = true; break;
    case EV_JOIN_FAILED: wanJoined = false; break;
    case EV_TXCOMPLETE: break;
    default: break;
  }
}

/* Initialize LMIC / start join */
void lorawanInit() {
  os_init();
  LMIC_reset();
  // configure IN865 channels (example). Adapt to your NS/gateway plan.
  for (uint8_t i = 0; i < 9; ++i) LMIC_disableChannel(i);
  LMIC_setupChannel(0, 865062500, DR_RANGE_MAP(DR_SF12, DR_SF7), 0);
  LMIC_setupChannel(1, 865402500, DR_RANGE_MAP(DR_SF12, DR_SF7), 0);
  LMIC_setupChannel(2, 865985000, DR_RANGE_MAP(DR_SF12, DR_SF7), 0);
  LMIC_startJoining();
}

/* Wrapper to send raw bytes as LoRaWAN uplink (FPORT configured) */
bool lorawanSend(const uint8_t* buf, uint8_t len, bool confirmed=false) {
  if (!wanJoined) return false;
  if (LMIC.opmode & OP_TXRXPEND) return false; // tx pending
  LMIC_setTxData2(LORAWAN_FPORT, (xref2u1_t)buf, len, confirmed ? 1 : 0);
  return true;
}

/* =========================
   ===== LoRa mesh (RadioLib)
   ========================= */
bool meshInit() {
  int st = lora.begin(MESH_FREQ_MHZ, 125.0, MESH_SF, 5, 0x34, MESH_TX_DBM, 8, 0);
  if (st != RADIOLIB_ERR_NONE) return false;
  lora.setCRC(true);
  return true;
}
void setMeshSF(uint8_t sf) { lora.setSpreadingFactor(sf); }
bool meshSend(const uint8_t* buf, size_t len) { return lora.transmit((uint8_t*)buf, len) == RADIOLIB_ERR_NONE; }
bool meshReceive(uint8_t* out, size_t &len) {
  if (lora.available()) {
    int r = lora.receive(out, len);
    if (r > 0) { len = r; return true; }
  }
  return false;
}

/* Bridge received mesh packet to LoRaWAN (rate-limited) */
void bridgeToWAN(const Pkt &p) {
  unsigned long now = millis();
  if (now - lastBridgeAt < 2000UL) return; // 2 s crude rate limit
  if (LMIC.opmode & OP_TXRXPEND) return;
  LMIC_setTxData2(LORAWAN_FPORT, (xref2u1_t)&p, sizeof(Pkt), 0);
  lastBridgeAt = now;
}

/* =========================
   ====== Build payload =====
   ========================= */
void buildPkt(Pkt &p) {
  p.src = boatId_u16;
  p.seq = ++seqno;
  if (gps.location.isValid()) {
    p.lat1e7 = (int32_t) llround(gps.location.lat() * 1e7);
    p.lon1e7 = (int32_t) llround(gps.location.lng() * 1e7);
  } else {
    p.lat1e7 = 0; p.lon1e7 = 0;
  }
  p.spd_cms = (uint16_t) llround(gps.speed.mps() * 100.0);
  p.hdg_cdeg = (uint16_t) llround(fmod(max(0.0, gps.course.deg()), 360.0) * 100.0);
  p.batt_pc = batteryPercentFromVoltage(readBatteryVoltage());
  p.hops = 0;
  p.crc = 0;
  p.crc = crc16_ccitt((uint8_t*)&p, sizeof(Pkt) - 2);
}

/* Initialize radios when pairing is finished */
void initRadiosAfterPairing() {
  if (!meshInit()) {
    // indicate mesh init error (short blink pattern)
    for (int i=0;i<4;i++) { ledState = LED_RED_BLINK; ledUpdate(); delay(160); }
  }
  lorawanInit(); // starts OTAA join in background
}

/* =========================
   ===== Setup & Loop ======
   ========================= */
void setup() {
  Serial.begin(115200);
  delay(100);

  // pins
  pinMode(PIN_RGB_R, OUTPUT); pinMode(PIN_RGB_G, OUTPUT); pinMode(PIN_RGB_B, OUTPUT);
  pinMode(PIN_BTN, INPUT_PULLUP);
  pinMode(PIN_BUZZER_CTRL, OUTPUT); digitalWrite(PIN_BUZZER_CTRL, LOW);
  pinMode(PIN_LED_STATUS, OUTPUT);
  analogReadResolution(12);

  // GPS UART
  GPSSerial.begin(9600, SERIAL_8N1, PIN_GPS_RX, -1);

  // load pairing info
  loadPairing();

  // if not paired, start pairing AP and visual pairing pattern
  if (!paired) {
    startPairingAP();
  } else {
    // show long-blue then initialize radios
    ledState = LED_BLUE_PAIRED;
    ledStamp = millis();
    initRadiosAfterPairing();
  }

  // schedule first periodic send with jitter
  nextSendAtMs = millis() + (REPORT_SEC * 1000UL) + random(0, REPORT_JITTER_S * 500);

  // clear seen cache
  for (int i=0;i<SEEN_MAX;i++) seen[i].ts = 0;
}

/* main loop:
   - LMIC background
   - GPS ingestion
   - pairing/rescue AP lifecycle
   - button handling
   - mesh receive & flood
   - periodic send decision (mesh-first, fallback to LoRaWAN)
   - LED updates
*/
void loop() {
  // let LMIC do background work
  os_runloop_once();

  // read any incoming GPS bytes
  while (GPSSerial.available()) gps.encode(GPSSerial.read());

  // pairing AP auto-stop
  if (pairingAPon && (long)(millis() - pairingAPOffAt) > 0) {
    stopPairingAP();
    if (paired) initRadiosAfterPairing(); // start radios after pairing
  }

  // rescue AP handling
  if (rescueAPon) {
    http.handleClient();
    if ((long)(millis() - rescueAPOffAt) > 0) {
      http.stop();
      WiFi.softAPdisconnect(true);
      rescueAPon = false;
    }
  }

  // button: long press behaviour avoided; single press triggers rescue AP if paired
  static uint32_t btnLast = 0;
  if (digitalRead(PIN_BTN) == LOW) {
    if (millis() - btnLast > 1000) {
      if (paired) {
        startRescueAP();
      }
      tone(PIN_BUZZER_CTRL, 2000, 150); // audible ack
      btnLast = millis();
    }
  }

  // mesh receive loop: dedupe, flood, and optionally bridge to WAN
  uint8_t buf[128]; size_t blen = sizeof(buf);
  if (paired && meshReceive(buf, blen)) {
    lastMeshHeardMs = millis();
    meshHeardRecently = true;
    if (blen == sizeof(Pkt)) {
      Pkt* rp = (Pkt*)buf;
      uint16_t saved = rp->crc; rp->crc = 0;
      if (saved == crc16_ccitt((uint8_t*)rp, sizeof(Pkt)-2)) {
        if (findSeen(rp->src, rp->seq) < 0) {
          rememberSeen(rp->src, rp->seq);
          // rebroadcast if hop budget remains
          if (rp->hops < 4) {
            rp->hops++;
            delay(random(200,600)); // randomize to reduce collisions
            meshSend((uint8_t*)rp, sizeof(Pkt));
          }
          // if node is joined to LoRaWAN, bridge upstream
          if (wanJoined) bridgeToWAN(*rp);
        }
      }
    }
  }

  // periodic send scheduler
  if ((long)(millis() - nextSendAtMs) >= 0) {
    uint32_t jitterMs = random(0, REPORT_JITTER_S * 1000UL);
    nextSendAtMs = millis() + REPORT_SEC * 1000UL + jitterMs;

    if (paired) {
      Pkt p; memset(&p, 0, sizeof(p));
      buildPkt(p);

      // update mesh-heard flag
      meshHeardRecently = (millis() - lastMeshHeardMs) < MESH_STALE_MS;

      if (meshHeardRecently) {
        // send to mesh; local network will flood/relay
        meshSend((uint8_t*)&p, sizeof(p));
      } else {
        // no mesh heard recently -> prefer LoRaWAN uplink if joined
        if (wanJoined) {
          lorawanSend((uint8_t*)&p, sizeof(p), false);
        } else {
          // still attempt mesh (maybe a distant node will pick it up)
          meshSend((uint8_t*)&p, sizeof(p));
        }
      }
    }
  }

  // LED state management
  // after showing long-blue for pairing, decide normal LED by comms
  if (ledState == LED_BLUE_PAIRED && (millis() - ledStamp) > 3000) {
    updateLedByComms();
  }
  // periodic comm-based updates
  static uint32_t lastCommsUpdate = 0;
  if ((millis() - lastCommsUpdate) > 5000) {
    updateLedByComms();
    lastCommsUpdate = millis();
  }
  ledUpdate();

  // tiny yield
  delay(10);
}

/* End of sketch.
   Notes:
   - OTAA keys must be set.
   - For production, add robust error logging, persistent seqno, and FreeRTOS tasks to isolate LMIC from mesh radio operations.
   - Duty-cycle and regulatory constraints must be considered (reduce reporting in busy deployments).
*/
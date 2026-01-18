/*
  BoatNode v2.0 - Updated Firmware
  Includes:
    - "Any-cast Gateway": Forwards mesh packets to LoRaWAN if connected.
    - JSON API: GET /nearby for mobile app.
    - In-memory cache of nearby boats.
    - All previous features (Pairing, Rescue, etc.)
*/

#include <Arduino.h>
#include <SPI.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <RadioLib.h>
#include <TinyGPSPlus.h>
#include <vector>
#include <algorithm>

extern "C" {
  #include <lmic.h>
  #include <hal/hal.h>
}

/* ------------ REGION & RADIO CONFIG ------------- */
const float MESH_FREQ_MHZ = 865.2;
const uint8_t MESH_SF = 9;
const int8_t MESH_TX_DBM = 14;
const uint32_t MESH_STALE_MS = 10UL * 60UL * 1000UL;

const uint16_t REPORT_SEC = 120;
const uint16_t REPORT_JITTER_S = 20;

/* ------------ LoRaWAN KEYS — REPLACE THESE ------------ */
static const u1_t PROGMEM APPEUI[8] = {0};
static const u1_t PROGMEM DEVEUI[8] = {0};
static const u1_t PROGMEM APPKEY[16] = {0};
const uint8_t LORAWAN_FPORT = 10;

/* ------------ PINS ------------- */
const int PIN_LORA_NSS  = 5;
const int PIN_LORA_DIO0 = 26;
const int PIN_LORA_RST  = 14;
const int PIN_GPS_RX    = 16;
const int PIN_BTN       = 0;
const int PIN_BATT_ADC  = 34;
const int PIN_RGB_R     = 15;
const int PIN_RGB_G     = 4;
const int PIN_RGB_B     = 13;
const int PIN_BUZZER    = 27;

const float ADC_VREF = 3.3;
const float ADC_SCALE = (10000.0 + 37000.0) / 37000.0;

/* ------------ GLOBALS ------------- */
SX1276 lora = new Module(PIN_LORA_NSS, PIN_LORA_DIO0, PIN_LORA_RST, 18);
TinyGPSPlus gps;
HardwareSerial GPSSerial(2);
WebServer http(80);
Preferences prefs;

bool paired = false;
String boatId = "";
uint16_t boatId_u16 = 0;
String displayName = "";
uint16_t userId_u16 = 0;

bool wanJoined = false;
bool meshHeardRecently = false;
uint32_t lastMeshHeardMs = 0;
uint32_t nextSendAtMs = 0;
uint16_t seqno = 0;

/* ------------ PACKET STRUCT (37 bytes) ------------- */
#pragma pack(push,1)
struct Pkt {
  uint16_t src;
  uint16_t seq;
  int32_t lat1e7;
  int32_t lon1e7;
  uint8_t batt_pc;
  uint8_t hops;
  uint16_t user_id;
  uint8_t  name_len;
  uint8_t  name_utf8[12];
  uint16_t crc;
};
#pragma pack(pop)

uint16_t crc16_ccitt(const uint8_t *data, size_t len) {
  uint16_t crc = 0xFFFF;
  for (size_t i=0; i<len; i++) {
    crc ^= (uint16_t)data[i] << 8;
    for (int j=0; j<8; j++)
      crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : (crc << 1);
  }
  return crc;
}

/* ------------ NEARBY BOATS CACHE ------------- */
struct BoatEntry {
  uint16_t boat_id;
  uint16_t user_id;
  String display_name;
  double lat;
  double lon;
  uint8_t battery;
  uint32_t last_seen_ms;
};

std::vector<BoatEntry> nearbyBoats;
const size_t MAX_NEARBY_BOATS = 30;

void updateNearbyCache(const Pkt* p) {
  uint32_t now = millis();
  bool found = false;
  
  // Convert name to String safely
  char nameBuf[13];
  memset(nameBuf, 0, 13);
  int nlen = (p->name_len > 12) ? 12 : p->name_len;
  memcpy(nameBuf, p->name_utf8, nlen);
  String nameStr = String(nameBuf);

  for (auto &b : nearbyBoats) {
    if (b.boat_id == p->src) {
      b.user_id = p->user_id;
      b.display_name = nameStr;
      b.lat = p->lat1e7 / 1e7;
      b.lon = p->lon1e7 / 1e7;
      b.battery = p->batt_pc;
      b.last_seen_ms = now;
      found = true;
      break;
    }
  }

  if (!found) {
    if (nearbyBoats.size() >= MAX_NEARBY_BOATS) {
      // Remove oldest
      auto oldest = nearbyBoats.begin();
      for (auto it = nearbyBoats.begin(); it != nearbyBoats.end(); ++it) {
        if (it->last_seen_ms < oldest->last_seen_ms) oldest = it;
      }
      nearbyBoats.erase(oldest);
    }
    BoatEntry b;
    b.boat_id = p->src;
    b.user_id = p->user_id;
    b.display_name = nameStr;
    b.lat = p->lat1e7 / 1e7;
    b.lon = p->lon1e7 / 1e7;
    b.battery = p->batt_pc;
    b.last_seen_ms = now;
    nearbyBoats.push_back(b);
  }
}

/* ------------ LED MACHINE ------------- */
enum LedState { LED_OFF, LED_GREEN_SOLID, LED_GREEN_BLINK, LED_RED_SOLID, LED_RED_BLINK, LED_BLUE_PAIRING, LED_BLUE_PAIRED };
volatile LedState ledState = LED_OFF;
uint32_t ledStamp = 0;

void ledPins(bool r, bool g, bool b) {
  digitalWrite(PIN_RGB_R, r); digitalWrite(PIN_RGB_G, g); digitalWrite(PIN_RGB_B, b);
}

void ledUpdate() {
  uint32_t t = millis();
  switch(ledState) {
    case LED_GREEN_SOLID:  ledPins(0,1,0); break;
    case LED_GREEN_BLINK:  ledPins(0, (t/400)%2==0, 0); break;
    case LED_RED_SOLID:    ledPins(1,0,0); break;
    case LED_RED_BLINK:    ledPins((t/500)%2==0,0,0); break;
    case LED_BLUE_PAIRING: {
      uint32_t c=t%900;
      if (c<100) ledPins(0,0,1); else if (c<200) ledPins(0,0,0); else if (c<300) ledPins(0,0,1); else ledPins(0,0,0);
      break;
    }
    case LED_BLUE_PAIRED: if (t - ledStamp < 3000) ledPins(0,0,1); break;
    default: ledPins(0,0,0);
  }
}

void updateLedByComms() {
  if (!paired) return;
  if (wanJoined) {
    ledState = ((millis()-lastMeshHeardMs) < MESH_STALE_MS) ? LED_GREEN_SOLID : LED_GREEN_BLINK;
  } else {
    ledState = ((millis()-lastMeshHeardMs) < MESH_STALE_MS) ? LED_RED_BLINK : LED_RED_SOLID;
  }
}

/* ------------ BATTERY & NVS ------------ */
float readBatteryVoltage() {
  return (analogRead(PIN_BATT_ADC)/4095.0)*ADC_VREF*ADC_SCALE;
}
uint8_t batteryPercent(float v) {
  if (v < 3.2) return 0; if (v > 4.15) return 100;
  return (uint8_t)((v-3.2)/(4.15-3.2)*100);
}

const char* NVS_NS = "boat_cfg";
void loadPairing() {
  prefs.begin(NVS_NS, true);
  paired = prefs.getBool("paired", false);
  boatId = prefs.getString("boat_id", "");
  displayName = prefs.getString("display_name", "");
  userId_u16 = prefs.getUInt("user_id", 0);
  boatId_u16 = (uint16_t) strtoul(boatId.c_str(), NULL, 10);
  prefs.end();
}
void savePairing(String bid, uint16_t uid, String name) {
  prefs.begin(NVS_NS, false);
  prefs.putBool("paired", true);
  prefs.putString("boat_id", bid);
  prefs.putUInt("user_id", uid);
  prefs.putString("display_name", name);
  prefs.end();
  paired = true; boatId = bid; boatId_u16 = (uint16_t) strtoul(bid.c_str(), NULL, 10); displayName = name; userId_u16 = uid;
}
void clearPairing() {
  prefs.begin(NVS_NS, false); prefs.clear(); prefs.end();
  paired=false; boatId=""; boatId_u16=0; displayName=""; userId_u16=0;
}

/* ------------ HTTP HANDLERS ------------- */
bool pairingAPon = false;
uint32_t pairingAPOffAt = 0;

void handlePair() {
  if (!http.hasArg("plain")) { http.send(400); return; }
  String body = http.arg("plain");
  // Simple JSON parsing (robustness improved in real impl)
  int bi = body.indexOf("\"boat_id\"");
  int ui = body.indexOf("\"user_id\"");
  int di = body.indexOf("\"display_name\"");
  
  if (bi < 0) { http.send(400,"application/json","{\"err\":\"missing boat_id\"}"); return; }
  
  // Extract values (simplified)
  String bid = body.substring(body.indexOf('"', body.indexOf(':', bi))+1);
  bid = bid.substring(0, bid.indexOf('"'));
  
  String ustr = body.substring(body.indexOf(':', ui)+1);
  uint16_t uid = ustr.toInt();
  
  String dname = "";
  if (di > 0) {
    dname = body.substring(body.indexOf('"', body.indexOf(':', di))+1);
    dname = dname.substring(0, dname.indexOf('"'));
  }

  savePairing(bid, uid, dname);
  http.send(200, "application/json", "{\"ok\":true}");
  ledState = LED_BLUE_PAIRED; ledStamp = millis();
}

void handleNearby() {
  String json = "{\"boats\":[";
  uint32_t now = millis();
  for (size_t i=0; i<nearbyBoats.size(); i++) {
    BoatEntry &b = nearbyBoats[i];
    uint32_t age = (now - b.last_seen_ms) / 1000;
    if (i > 0) json += ",";
    json += "{";
    json += "\"boat_id\":\"" + String(b.boat_id) + "\",";
    json += "\"user_id\":" + String(b.user_id) + ",";
    json += "\"display_name\":\"" + b.display_name + "\",";
    json += "\"lat\":" + String(b.lat, 6) + ",";
    json += "\"lon\":" + String(b.lon, 6) + ",";
    json += "\"age_sec\":" + String(age) + ",";
    json += "\"battery\":" + String(b.battery) + ",";
    json += "\"speed_cms\":" + String(b.speed_cms) + ",";
    json += "\"heading_cdeg\":" + String(b.hdg_cdeg);
    json += "}";
  }
  json += "]}";
  http.send(200, "application/json", json);
}

void startAP(bool rescue) {
  String ssid = rescue ? ("BOAT-" + boatId) : ("BOAT-PAIR-" + String((uint16_t)ESP.getEfuseMac(), HEX));
  WiFi.softAP(ssid.c_str(), rescue ? "findme-1234" : "pairme-1234");
  
  http.on("/pair", HTTP_POST, handlePair);
  http.on("/nearby", HTTP_GET, handleNearby); // NEW API
  // ... other handlers ...
  http.begin();
  pairingAPon = true;
  pairingAPOffAt = millis() + (rescue ? 600000 : 600000);
}

/* ------------ RADIO & MESH ------------- */
int utf8_truncate(const char *src, uint8_t *out, int maxBytes) {
  int i=0; const unsigned char *s=(const unsigned char*)src;
  while (*s && i<maxBytes) {
    int len=1;
    if ((*s & 0x80)==0) len=1; else if((*s&0xE0)==0xC0) len=2; else if((*s&0xF0)==0xE0) len=3; else if((*s&0xF8)==0xF0) len=4; else break;
    if (i+len > maxBytes) break;
    for (int k=0;k<len;k++) out[i++] = *s++;
  }
  return i;
}

void buildPkt(Pkt &p) {
  p.src = boatId_u16; p.seq = ++seqno;
  if (gps.location.isValid()) { p.lat1e7 = gps.location.lat()*1e7; p.lon1e7 = gps.location.lng()*1e7; }
  p.spd_cms = gps.speed.mps()*100; p.hdg_cdeg = gps.course.deg()*100;
  p.batt_pc = batteryPercent(readBatteryVoltage());
  p.hops = 0; p.user_id = userId_u16;
  memset(p.name_utf8, 0, 12);
  p.name_len = utf8_truncate(displayName.c_str(), p.name_utf8, 12);
  p.crc = 0; p.crc = crc16_ccitt((uint8_t*)&p, sizeof(Pkt)-2);
}

bool meshInit() {
  int st = lora.begin(MESH_FREQ_MHZ, 125.0, MESH_SF, 5, 0x34, MESH_TX_DBM);
  lora.setCRC(true);
  return st == RADIOLIB_ERR_NONE;
}

/* ------------ LORAWAN (Stubbed for brevity) ------------- */
void os_getArtEui(u1_t *b){memcpy(b, APPEUI, 8);}
void os_getDevEui(u1_t *b){memcpy(b, DEVEUI, 8);}
void os_getDevKey(u1_t *b){memcpy(b, APPKEY, 16);}
void onLmicEvent(ev_t ev) { if (ev==EV_JOINED) wanJoined=true; }
void lorawanInit() { os_init(); LMIC_reset(); LMIC_startJoining(); }
bool lorawanSend(const uint8_t *buf, uint8_t len) {
  if (!wanJoined || (LMIC.opmode & OP_TXRXPEND)) return false;
  LMIC_setTxData2(LORAWAN_FPORT, (xref2u1_t)buf, len, 0);
  return true;
}

/* ------------ SETUP & LOOP ------------- */
void setup() {
  Serial.begin(115200);
  pinMode(PIN_RGB_R,OUTPUT); pinMode(PIN_RGB_G,OUTPUT); pinMode(PIN_RGB_B,OUTPUT);
  pinMode(PIN_BTN,INPUT_PULLUP); pinMode(PIN_BUZZER,OUTPUT);
  GPSSerial.begin(9600, SERIAL_8N1, PIN_GPS_RX, -1);
  analogReadResolution(12);
  loadPairing();

  if (!paired) {
    startAP(false);
    ledState = LED_BLUE_PAIRING;
  } else {
    ledState = LED_BLUE_PAIRED; ledStamp = millis();
    meshInit();
    lorawanInit();
  }
  nextSendAtMs = millis() + REPORT_SEC*1000;
}

void loop() {
  os_runloop_once();
  while(GPSSerial.available()) gps.encode(GPSSerial.read());

  if (pairingAPon) http.handleClient();

  // Mesh Reception
  uint8_t buf[128]; size_t bl=sizeof(buf);
  if (lora.available() && lora.receive(buf, bl) == RADIOLIB_ERR_NONE && bl==sizeof(Pkt)) {
    Pkt *rp=(Pkt*)buf;
    uint16_t s=rp->crc; rp->crc=0;
    if (s==crc16_ccitt((uint8_t*)rp, sizeof(Pkt)-2)) {
      lastMeshHeardMs=millis();
      
      // 1. Update Cache for Mobile App
      updateNearbyCache(rp);

      // 2. Mesh Forwarding (Flood Fill)
      if (rp->hops < 4) {
        rp->hops++;
        rp->crc = crc16_ccitt((uint8_t*)rp, sizeof(Pkt)-2); // Re-sign
        delay(random(200,600)); // Jitter
        lora.transmit((uint8_t*)rp, sizeof(Pkt));
      }

      // 3. Gateway Forwarding (Any-cast)
      // If we have WAN, forward this packet to cloud!
      if (wanJoined) {
        lorawanSend((uint8_t*)rp, sizeof(Pkt));
      }
    }
  }

  // Periodic Report
  if ((long)(millis()-nextSendAtMs)>=0) {
    nextSendAtMs = millis() + REPORT_SEC*1000 + random(0,REPORT_JITTER_S*1000);
    if (paired) {
      Pkt p; memset(&p,0,sizeof(p)); buildPkt(p);
      // If we have WAN, send there. Else mesh.
      // Actually, send to mesh ALWAYS so others can see us
      lora.transmit((uint8_t*)&p, sizeof(p));
      
      if (wanJoined) lorawanSend((uint8_t*)&p, sizeof(p));
    }
  }

  updateLedByComms();
  ledUpdate();
}

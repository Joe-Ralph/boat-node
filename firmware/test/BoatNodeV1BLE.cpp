/**
 * BoatNode V1 - BLE + LoRa Implementation
 * Replaces WiFi AP with BLE for pairing and data.
 * Adds LoRaWAN/Mesh functionality using MCCI LMIC.
 * Hardware: ESP32 DOIT DevKit V1, RFM95 (LoRa), NEO-6M (GPS), SSD1306 (OLED)
 */

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <SPI.h>
#include <TinyGPS++.h>
#include <Wire.h>
#include <hal/hal.h>
#include <lmic.h>

// --- Configuration ---
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

TinyGPSPlus gps;
HardwareSerial gpsSerial(1); // UART 1 for GPS

// BLE UUIDs (Must match Flutter App)
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_DATA_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8" // Read/Notify
#define CHAR_CMD_UUID "8246d623-6447-4ec6-8c46-d2432924151a"  // Write

BLEServer *pServer = NULL;
BLECharacteristic *pDataChar = NULL;
BLECharacteristic *pCmdChar = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Global State
String boatId = "1001";
String boatName = "Boat-Init";
String userId = "0";
float batteryLevel = 95.5; // Mock
String loraStatus = "Init";
int meshHops = 0;

// Config Persistence (Mock for now)
void saveConfig(String bid, String uid, String name) {
  boatId = bid;
  userId = uid;
  boatName = name;
  Serial.println("Config Saved: " + bid + ", " + uid + ", " + name);
}

// --- Display Helper ---
void updateDashboard(String status) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);

  // Header
  display.setCursor(0, 0);
  display.print("BN_BLE ");
  if (deviceConnected)
    display.print("[C]");
  else
    display.print("[ ]");

  display.setCursor(80, 0);
  display.print("Sat:");
  display.print(gps.satellites.value());

  // GPS
  display.setCursor(0, 15);
  display.print("Lat:");
  display.print(gps.location.lat(), 5);
  display.setCursor(0, 25);
  display.print("Lon:");
  display.print(gps.location.lng(), 5);

  // Info
  display.setCursor(0, 38);
  display.print("ID:");
  display.print(boatId);
  display.print(" Bat:");
  display.print((int)batteryLevel);
  // display.print("%");

  // Status
  display.drawLine(0, 50, 128, 50, WHITE);
  display.setCursor(0, 54);
  display.print(status.substring(0, 20)); // Truncate

  display.display();
}

// --- LoRa / LMIC Constants & Globals ---
// LoRaWAN Keys (Little Endian for OTAA)
const char *deviceEUI_str = "0000000000000000"; // Replace with real keys
const char *appKey_str = "00000000000000000000000000000000";
const char *appEUI_str = "0000000000000000";

// Mesh Packet Structure
struct __attribute__((packed)) Pkt {
  uint16_t src;
  uint16_t seq;
  int32_t lat1e7;
  int32_t lon1e7;
  uint8_t batt_pc;
  uint8_t hops;
  uint16_t user_id;
  uint8_t name_len;
  uint8_t name_utf8[12];
  uint16_t crc;
};

Pkt myPacket;
uint16_t globalSeq = 0;
static osjob_t sendjob;

// Pin Mapping
const lmic_pinmap lmic_pins = {
    .nss = 5,
    .rxtx = LMIC_UNUSED_PIN,
    .rst = 14,
    .dio = {2, 4, LMIC_UNUSED_PIN},
};

// --- LoRa Helper Functions ---
uint16_t calculateCRC(byte *data, byte len) {
  uint16_t crc = 0xFFFF;
  for (int i = 0; i < len; i++) {
    crc ^= data[i];
    for (int j = 0; j < 8; j++) {
      if (crc & 0x0001)
        crc = (crc >> 1) ^ 0xA001;
      else
        crc >>= 1;
    }
  }
  return crc;
}

byte nibble(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return 0;
}

void stringToBytes(const char *str, byte *buffer, int length, boolean reverse) {
  for (int i = 0; i < length; i++) {
    byte val = (nibble(str[i * 2]) << 4) | nibble(str[i * 2 + 1]);
    if (reverse)
      buffer[length - 1 - i] = val;
    else
      buffer[i] = val;
  }
}

void os_getArtEui(u1_t *buf) { stringToBytes(appEUI_str, buf, 8, true); }
void os_getDevEui(u1_t *buf) { stringToBytes(deviceEUI_str, buf, 8, true); }
void os_getDevKey(u1_t *buf) { stringToBytes(appKey_str, buf, 16, false); }

void preparePacket() {
  myPacket.src = (uint16_t)boatId.toInt();
  myPacket.seq = globalSeq++;

  if (gps.location.isValid()) {
    myPacket.lat1e7 = (int32_t)(gps.location.lat() * 10000000.0);
    myPacket.lon1e7 = (int32_t)(gps.location.lng() * 10000000.0);
  } else {
    myPacket.lat1e7 = 0;
    myPacket.lon1e7 = 0;
  }

  myPacket.batt_pc = (uint8_t)batteryLevel;
  myPacket.hops = 0;
  myPacket.user_id = (uint16_t)userId.toInt();

  myPacket.name_len = boatName.length();
  if (myPacket.name_len > 12)
    myPacket.name_len = 12; // Safety cap
  memset(myPacket.name_utf8, 0, 12);
  memcpy(myPacket.name_utf8, boatName.c_str(), myPacket.name_len);

  myPacket.crc = calculateCRC((byte *)&myPacket, sizeof(Pkt) - 2);
}

void onEvent(ev_t ev) {
  switch (ev) {
  case EV_JOINING:
    loraStatus = "LoRa Joining...";
    updateDashboard(loraStatus);
    break;
  case EV_JOINED:
    loraStatus = "LoRa Joined";
    updateDashboard(loraStatus);
    LMIC_setLinkCheckMode(0);
    break;
  case EV_TXCOMPLETE:
    loraStatus = "LoRa Sent (Sleep 30s)";
    updateDashboard(loraStatus);

    // Schedule next packet in 30 seconds
    os_setTimedCallback(
        &sendjob, os_getTime() + sec2osticks(30), [](osjob_t *j) {
          preparePacket();
          LMIC_setTxData2(1, (uint8_t *)&myPacket, sizeof(Pkt), 0);
          // updateDashboard("LoRa Transmitting..."); // Avoid too many updates
        });
    break;
  case EV_JOIN_FAILED:
    loraStatus = "LoRa Join Fail";
    updateDashboard(loraStatus);
    break;
  default:
    break;
  }
}

// --- BLE Callbacks ---
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    Serial.println("BLE Connected");
    updateDashboard("BLE Connected");
  };

  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
    Serial.println("BLE Disconnected");
    updateDashboard("BLE Disconnected");
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() > 0) {
      String msg = String(value.c_str());
      Serial.print("Rx Cmd: ");
      Serial.println(msg);

      if (msg.startsWith("SET_ID:")) {
        int firstColon = msg.indexOf(':');
        int secondColon = msg.indexOf(':', firstColon + 1);
        int thirdColon = msg.indexOf(':', secondColon + 1);

        if (secondColon > 0 && thirdColon > 0) {
          String newId = msg.substring(firstColon + 1, secondColon);
          String newUser = msg.substring(secondColon + 1, thirdColon);
          String newName = msg.substring(thirdColon + 1);

          saveConfig(newId, newUser, newName);
          updateDashboard("Paired: " + newName);
        }
      } else if (msg == "START_JOURNEY") {
        Serial.println("Journey Started via BLE");
        // Force immediate packet logic or status update if needed
      } else if (msg == "END_JOURNEY") {
        Serial.println("Journey Ended via BLE");
      }
    }
  }
};

void setup() {
  Serial.begin(115200);

  // 1. OLED Init
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("OLED Allocation Failed"));
  }
  display.display();
  delay(1000);
  display.clearDisplay();
  updateDashboard("Booting...");

  // 2. GPS Init
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  // 3. BLE Init
  BLEDevice::init("BoatNode-BLE");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Data Char (Notify)
  pDataChar = pService->createCharacteristic(
      CHAR_DATA_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pDataChar->addDescriptor(new BLE2902());

  // Cmd Char (Write)
  pCmdChar = pService->createCharacteristic(CHAR_CMD_UUID,
                                            BLECharacteristic::PROPERTY_WRITE);
  pCmdChar->setCallbacks(new MyCallbacks());

  pService->start();

  // Advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();

  Serial.println("BLE Ready, Advertising...");

  // 4. LMIC Init
  os_init();
  LMIC_reset();

  updateDashboard("Starting LoRa...");
  preparePacket();
  LMIC_setTxData2(1, (uint8_t *)&myPacket, sizeof(Pkt), 0);
}

void loop() {
  // Run LMIC Loop
  os_runloop_once();

  // Parse GPS
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }

  // Notify BLE Client periodically
  if (deviceConnected) {
    static uint32_t lastNotify = 0;
    if (millis() - lastNotify > 1000) {
      String data = "SAT:" + String(gps.satellites.value()) +
                    ",LAT:" + String(gps.location.lat(), 6) +
                    ",LON:" + String(gps.location.lng(), 6) +
                    ",BAT:" + String((int)batteryLevel) + ",LORA:" + loraStatus;

      pDataChar->setValue(data.c_str());
      pDataChar->notify();
      lastNotify = millis();
    }
  }

  // Handle Disconnect Logic
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("Restart advertising");
    oldDeviceConnected = deviceConnected;
    updateDashboard("Disconnected");
  }

  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // UI Refresh
  static uint32_t lastUi = 0;
  if (millis() - lastUi > 2000) {
    updateDashboard(deviceConnected ? "BLE Active" : loraStatus);
    lastUi = millis();
  }
}

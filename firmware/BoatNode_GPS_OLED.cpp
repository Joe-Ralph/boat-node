#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <TinyGPS++.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// --- DISPLAY CONFIGURATION (0.96" OLED) ---
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define SCREEN_ADDRESS 0x3C // Check if your module uses 0x3C or 0x3D

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// --- GPS CONFIGURATION ---
static const int RXPin = 23; // User Hardware: GPIO 23
static const int TXPin = -1; // Not used
static const uint32_t GPSBaud = 9600;

TinyGPSPlus gps;
HardwareSerial gpsSerial(1);

// --- WIFI & SERVER CONFIGURATION ---
const char* AP_SSID = "BOAT-PAIR-1234";
const char* AP_PASS = "pairme-1234";

WebServer server(80);

// --- STATE VARIABLES ---
bool isPaired = false;
String pairedBoatId = "";
String pairedUserId = "";
String pairedBoatName = "";

int batteryLevel = 85;
bool wifiConnected = true;
bool loraConnected = false;
int meshConnectedCount = 3;

long serialUpdateTimer = 0; // Timer for serial debug

// --- FUNCTION PROTOTYPES ---
void drawMinimalUI();
void printGpsData();

// --- SERVER HANDLERS ---
void handleRoot() {
  Serial.println("GET /");
  server.send(200, "text/plain", "BoatNode GPS OLED Firmware Running");
}

void handlePair() {
  Serial.println("POST /pair");
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method Not Allowed");
    return;
  }

  if (server.hasArg("boat_id") && server.hasArg("user_id") && server.hasArg("name")) {
    pairedBoatId = server.arg("boat_id");
    pairedUserId = server.arg("user_id");
    pairedBoatName = server.arg("name");
    isPaired = true;
    
    Serial.println("Paired with Boat ID: " + pairedBoatId);
    server.send(200, "text/plain", "Pairing Successful");
  } else {
    server.send(400, "text/plain", "Missing Arguments");
  }
}

void handleReset() {
  Serial.println("POST /reset");
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method Not Allowed");
    return;
  }
  
  isPaired = false;
  pairedBoatId = "";
  pairedUserId = "";
  pairedBoatName = "";
  
  Serial.println("Device Unpaired/Reset");
  server.send(200, "text/plain", "Device Reset Successful");
}

void handleStatus() {
  Serial.println("GET /status");
  StaticJsonDocument<300> doc;
  
  doc["id"] = "1234"; 
  doc["name"] = isPaired ? pairedBoatName : "Unpaired Boat";
  doc["battery"] = batteryLevel;
  
  JsonObject connection = doc.createNestedObject("connection");
  connection["wifi"] = wifiConnected;
  connection["lora"] = loraConnected;
  connection["mesh"] = meshConnectedCount;
  
  JsonObject lastFix = doc.createNestedObject("lastFix");
  
  if (gps.location.isValid()) {
    lastFix["lat"] = gps.location.lat();
    lastFix["lng"] = gps.location.lng();
    doc["gpsStatus"] = "LOCKED";
  } else {
    lastFix["lat"] = 0.0;
    lastFix["lng"] = 0.0;
    doc["gpsStatus"] = "SEARCHING";
  }

  if (gps.time.isValid()) {
    char timeBuffer[16];
    sprintf(timeBuffer, "%02d:%02d:%02d", gps.time.hour(), gps.time.minute(), gps.time.second());
    lastFix["time"] = String(timeBuffer);
  } else {
    lastFix["time"] = "00:00:00";
  }
  
  lastFix["satellites"] = gps.satellites.value();
  lastFix["hdop"] = gps.hdop.value();

  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleNearby() {
  Serial.println("GET /nearby");
  StaticJsonDocument<1024> doc;
  JsonArray boats = doc.createNestedArray("boats");

  // Mock Boat 1
  JsonObject boat1 = boats.createNestedObject();
  boat1["boat_id"] = "101";
  boat1["user_id"] = 55;
  boat1["display_name"] = "Kumar";
  boat1["lat"] = 13.0850;
  boat1["lon"] = 80.2700;
  boat1["age_sec"] = 15;
  boat1["battery"] = 85;
  boat1["speed_cms"] = 0;
  boat1["heading_cdeg"] = 0;

  // Mock Boat 2
  JsonObject boat2 = boats.createNestedObject();
  boat2["boat_id"] = "102";
  boat2["user_id"] = 0;
  boat2["display_name"] = "";
  boat2["lat"] = 13.0800;
  boat2["lon"] = 80.2750;
  boat2["age_sec"] = 120;
  boat2["battery"] = 60;
  boat2["speed_cms"] = 150;
  boat2["heading_cdeg"] = 18000;

  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleSerialInput() {
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    
    if (command.startsWith("BAT:")) {
      int newLevel = command.substring(4).toInt();
      if (newLevel >= 0 && newLevel <= 100) {
        batteryLevel = newLevel;
        Serial.println("Battery updated to: " + String(batteryLevel));
      }
    } else if (command.startsWith("WIFI:")) {
      int status = command.substring(5).toInt();
      wifiConnected = (status == 1);
      Serial.println("WiFi status updated to: " + String(wifiConnected));
    } else if (command.startsWith("LORA:")) {
      int status = command.substring(5).toInt();
      loraConnected = (status == 1);
      Serial.println("LoRa status updated to: " + String(loraConnected));
    } else if (command.startsWith("MESH:")) {
      int count = command.substring(5).toInt();
      if (count >= 0) {
        meshConnectedCount = count;
        Serial.println("Mesh count updated to: " + String(meshConnectedCount));
      }
    }
  }
}

// --- SETUP & LOOP ---
void setup() {
  Serial.begin(115200);
  Serial.println(F("\n--- BoatNode GPS OLED Minimal Firmware ---"));

  // 1. Initialize GPS
  gpsSerial.begin(GPSBaud, SERIAL_8N1, RXPin, TXPin);
  Serial.println("GPS Serial Started on Pin " + String(RXPin));

  // 2. Initialize OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println(F("SSD1306 allocation failed."));
    // Don't halt, just continue without display
  } else {
    display.clearDisplay();
    display.setTextSize(2);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(10, 25);
    display.println(F("BOAT NODE"));
    display.display();
    delay(1000);
  }

  // 3. Initialize WiFi
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.println("AP Started: " + String(AP_SSID));
  Serial.print("IP Address: ");
  Serial.println(WiFi.softAPIP());

  // 4. Initialize Server
  server.on("/", handleRoot);
  server.on("/pair", handlePair);
  server.on("/reset", handleReset);
  server.on("/status", handleStatus);
  server.on("/nearby", handleNearby);
  server.begin();
  Serial.println("Web Server Started");
}

void loop() {
  // Process GPS data
  while (gpsSerial.available() > 0) {
    if (gps.encode(gpsSerial.read())) {
      drawMinimalUI();
    }
  }
  
  // Timed Serial Update - 2000ms
  if (millis() - serialUpdateTimer >= 2000) {
    printGpsData();
    serialUpdateTimer = millis();
  }

  server.handleClient();
  handleSerialInput();
}

// --- UI FUNCTIONS ---
void drawMinimalUI() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  
  // 1. Top Bar: Status + Satellites
  display.setTextSize(1);
  display.setCursor(0, 0);
  if (gps.location.isValid()) {
    display.print(F("GPS: LOCKED"));
  } else {
    display.print(F("GPS: SEARCHING"));
  }
  
  display.setCursor(90, 0);
  display.print(F("SAT:"));
  display.print(gps.satellites.value());
  
  display.drawLine(0, 10, 128, 10, SSD1306_WHITE);

  // 2. Time (Center, Large)
  display.setTextSize(2);
  display.setCursor(16, 20);
  if (gps.time.isValid()) {
    char timeBuf[10];
    sprintf(timeBuf, "%02d:%02d:%02d", gps.time.hour(), gps.time.minute(), gps.time.second());
    display.print(timeBuf);
  } else {
    display.print(F("--:--:--"));
  }

  // 3. Location (Bottom)
  display.setTextSize(1);
  display.setCursor(0, 45);
  display.print(F("Lat: "));
  if (gps.location.isValid()) {
    display.print(gps.location.lat(), 6);
  } else {
    display.print(F("-.------"));
  }
  
  display.setCursor(0, 55);
  display.print(F("Lng: "));
  if (gps.location.isValid()) {
    display.print(gps.location.lng(), 6);
  } else {
    display.print(F("-.------"));
  }

  display.display();
}

void printGpsData() {
  Serial.print(F("TIME: "));
  Serial.print(gps.time.value());
  
  if (gps.location.isValid()) {
    Serial.print(F(" | STATUS: LOCKED"));
    Serial.print(F(" | LAT: ")); Serial.print(gps.location.lat(), 6);
    Serial.print(F(" | LNG: ")); Serial.print(gps.location.lng(), 6);
  } else {
    Serial.print(F(" | STATUS: SEARCHING..."));
  }
  Serial.println();
}

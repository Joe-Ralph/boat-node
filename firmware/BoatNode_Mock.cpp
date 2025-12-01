#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>

// --- Configuration ---
const char* AP_SSID = "BOAT-PAIR-1234";
const char* AP_PASS = "pairme-1234";

// --- State ---
bool isPaired = false;
String pairedBoatId = "";
String pairedUserId = "";
String pairedBoatName = "";

// Mock Battery Level
int batteryLevel = 85;

// Mock Location
float mockLat = 13.0827;
float mockLon = 80.2707;

// Mock Connectivity Status
bool wifiConnected = true;
bool loraConnected = false;
int meshConnectedCount = 3;

// --- Web Server ---
WebServer server(80);

// --- Helper Functions ---
void handleRoot() {
  Serial.println("GET /");
  server.send(200, "text/plain", "BoatNode Mock Firmware Running");
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
  StaticJsonDocument<200> doc;
  
  doc["id"] = "1234"; // Hardcoded Device ID
  doc["name"] = isPaired ? pairedBoatName : "Unpaired Boat";
  doc["battery"] = batteryLevel;
  
  JsonObject connection = doc.createNestedObject("connection");
  connection["wifi"] = wifiConnected;
  connection["lora"] = loraConnected;
  connection["mesh"] = meshConnectedCount;
  
  JsonObject lastFix = doc.createNestedObject("lastFix");
  lastFix["lat"] = mockLat;
  lastFix["lng"] = mockLon;
  lastFix["time"] = "10:00 AM"; // Mock time

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
    } else if (command.startsWith("LOC:")) {
      int commaIndex = command.indexOf(',');
      if (commaIndex > 0) {
        String latStr = command.substring(4, commaIndex);
        String lonStr = command.substring(commaIndex + 1);
        mockLat = latStr.toFloat();
        mockLon = lonStr.toFloat();
        Serial.println("Location updated to: " + String(mockLat, 6) + ", " + String(mockLon, 6));
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

void setup() {
  Serial.begin(115200);
  
  // Setup Access Point
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.println("AP Started: " + String(AP_SSID));
  Serial.print("IP Address: ");
  Serial.println(WiFi.softAPIP());

  // Setup Routes
  server.on("/", handleRoot);
  server.on("/pair", handlePair);
  server.on("/reset", handleReset);
  server.on("/status", handleStatus);
  server.on("/nearby", handleNearby);

  server.begin();
  Serial.println("Web Server Started");
}

void loop() {
  server.handleClient();
  handleSerialInput();
}

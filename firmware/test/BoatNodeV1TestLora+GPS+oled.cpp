/**
 * =================================================================================
 * NEDUVAAI BOAT TRACKER - MILESTONE 1 (HYBRID MESH NODE PROTOTYPE)
 * =================================================================================
 * * HARDWARE PINOUT MAPPING
 * ---------------------------------------------------------------------------------
 * COMPONENT       | PIN NAME      | ESP32 PIN    | NOTES
 * ---------------------------------------------------------------------------------
 * RFM95 (LoRa)    | 3.3V          | 3V3          | DO NOT USE 5V
 * | GND           | GND          |
 * | NSS (CS)      | GPIO 5       | Chip Select
 * | SCK           | GPIO 18      | SPI Clock
 * | MOSI          | GPIO 23      | SPI Data
 * | MISO          | GPIO 19      | SPI Data
 * | DIO0          | GPIO 2       | IRQ: TxDone/RxDone
 * | DIO1          | GPIO 4       | IRQ: RxTimeout (Vital)
 * | RESET         | GPIO 14      |
 * ---------------------------------------------------------------------------------
 * NEO-6M (GPS)    | VCC           | 3V3 or 5V    | Check module specs
 * | GND           | GND          |
 * | TX            | GPIO 16      | GPS TX -> ESP32 RX (UART1)
 * | RX            | GPIO 17      | GPS RX <- ESP32 TX (UART1)
 * ---------------------------------------------------------------------------------
 * OLED (0.96")    | VCC           | 3V3          |
 * | GND           | GND          |
 * | SDA           | GPIO 21      | I2C Data
 * | SCL           | GPIO 22      | I2C Clock
 * ---------------------------------------------------------------------------------
 * * REQUIRED LIBRARIES (Add to platformio.ini):
 * - mcci-catena/MCCI LoRaWAN LMIC library @ 4.1.1
 * - mikalhart/TinyGPSPlus @ ^1.0.3
 * - adafruit/Adafruit SSD1306 @ ^2.5.7
 * - adafruit/Adafruit GFX Library @ ^1.11.5
 * =================================================================================
 */

#include <Arduino.h>
#include <lmic.h>
#include <hal/hal.h>
#include <SPI.h>
#include <TinyGPS++.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "BluetoothSerial.h"

// =========================================================================
//  1. KEYS & CONFIGURATION
// =========================================================================
const char* deviceEUI_str = ""; 
const char* appKey_str    = ""; 
const char* appEUI_str    = "0000000000000000"; 

// Hardware Objects
BluetoothSerial SerialBT;
TinyGPSPlus gps;
HardwareSerial gpsSerial(1); // UART 1
Adafruit_SSD1306 display(128, 64, &Wire, -1); // 128x64 OLED (No reset pin)

// =========================================================================
//  2. MESH PACKET STRUCTURE (BINARY)
// =========================================================================
// "packed" prevents the compiler from adding gaps between variables
struct __attribute__((packed)) Pkt {
  uint16_t src;         // Mesh Node ID (Mock: 0x0001)
  uint16_t seq;         // Sequence Number
  int32_t lat1e7;       // Latitude * 10,000,000
  int32_t lon1e7;       // Longitude * 10,000,000
  uint8_t batt_pc;      // Battery % (Mock: 98)
  uint8_t hops;         // Mesh Hops (Mock: 0)
  uint16_t user_id;     // User ID (Mock: 101)
  uint8_t  name_len;    // Name Length
  uint8_t  name_utf8[12]; // Name String
  uint16_t crc;         // CRC Checksum
};

Pkt myPacket;           // The packet instance
uint16_t globalSeq = 0; // Sequence counter

// =========================================================================
//  3. PIN MAPPING (LMIC)
// =========================================================================
const lmic_pinmap lmic_pins = {
    .nss = 5,                       
    .rxtx = LMIC_UNUSED_PIN,
    .rst = 14,                      
    .dio = {2, 4, LMIC_UNUSED_PIN}, // DIO0=2, DIO1=4
};

// =========================================================================
//  4. HELPER FUNCTIONS
// =========================================================================

// Calculates a simple CRC16 to verify data integrity
uint16_t calculateCRC(byte* data, byte len) {
    uint16_t crc = 0xFFFF;
    for (int i = 0; i < len; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 0x0001) crc = (crc >> 1) ^ 0xA001;
            else crc >>= 1;
        }
    }
    return crc;
}

// Updates the OLED Dashboard and Bluetooth Logs
void updateDashboard(String status, bool txActive) {
    // 1. Update OLED
    display.clearDisplay();
    
    // Header
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.setCursor(0,0);
    display.print("NEDUVAAI MESH");
    display.setCursor(90, 0);
    display.print("Sat:"); display.print(gps.satellites.value());

    // Coordinates
    display.setCursor(0, 15);
    display.print("Lat:"); 
    if(gps.location.isValid()) display.print(gps.location.lat(), 5);
    else display.print("Searching...");

    display.setCursor(0, 25);
    display.print("Lon:"); 
    if(gps.location.isValid()) display.print(gps.location.lng(), 5);
    else display.print("Searching...");

    // Status Footer
    display.drawLine(0, 45, 128, 45, WHITE);
    display.setCursor(0, 50);
    display.print(status);
    
    if (txActive) display.fillRect(115, 50, 10, 10, WHITE); // Blink square

    display.display();

    // 2. Update Serial & Bluetooth
    Serial.println(status);
    if(SerialBT.hasClient()) SerialBT.println(status);
}

// LMIC Byte Conversions
byte nibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return 0;
}
void stringToBytes(const char* str, byte* buffer, int length, boolean reverse) {
  for (int i = 0; i < length; i++) {
    byte val = (nibble(str[i * 2]) << 4) | nibble(str[i * 2 + 1]);
    if (reverse) buffer[length - 1 - i] = val; else buffer[i] = val;                      
  }
}
void os_getArtEui (u1_t* buf) { stringToBytes(appEUI_str, buf, 8, true); }
void os_getDevEui (u1_t* buf) { stringToBytes(deviceEUI_str, buf, 8, true); }
void os_getDevKey (u1_t* buf) { stringToBytes(appKey_str, buf, 16, false); }

// =========================================================================
//  5. MAIN LOGIC
// =========================================================================
static osjob_t sendjob;
String loraStatus = "Init";

void preparePacket() {
    // Fill Header
    myPacket.src = 0x0001;        // Mock Node ID
    myPacket.seq = globalSeq++;
    
    // Fill GPS (Real Data)
    if (gps.location.isValid()) {
        myPacket.lat1e7 = (int32_t)(gps.location.lat() * 10000000.0);
        myPacket.lon1e7 = (int32_t)(gps.location.lng() * 10000000.0);
    } else {
        myPacket.lat1e7 = 0;
        myPacket.lon1e7 = 0;
    }

    // Fill Mock Data for Mesh
    myPacket.batt_pc = 98; 
    myPacket.hops = 0;     
    myPacket.user_id = 101;
    
    // Fill Name
    String boatName = "Boat-01";
    myPacket.name_len = boatName.length();
    memset(myPacket.name_utf8, 0, 12);
    memcpy(myPacket.name_utf8, boatName.c_str(), boatName.length());

    // CRC Calculation (Must be last)
    myPacket.crc = calculateCRC((byte*)&myPacket, sizeof(Pkt) - 2);
}

void onEvent (ev_t ev) {
    switch(ev) {
        case EV_JOINING: 
            loraStatus = "Joining Network..."; 
            updateDashboard(loraStatus, false);
            break;
        case EV_JOINED:  
            loraStatus = "Joined! (Ready)";
            updateDashboard(loraStatus, false);
            LMIC_setLinkCheckMode(0);
            break;
        case EV_TXCOMPLETE: 
            loraStatus = "Packet Sent (Sleep 30s)";
            updateDashboard(loraStatus, false);
            
            // Schedule next packet in 30 seconds
            os_setTimedCallback(&sendjob, os_getTime()+sec2osticks(30), [](osjob_t* j){
                preparePacket();
                LMIC_setTxData2(1, (uint8_t*)&myPacket, sizeof(Pkt), 0);
                updateDashboard("Transmitting...", true);
            });
            break;
        case EV_JOIN_FAILED:
            loraStatus = "Join Failed! (Retry)";
            updateDashboard(loraStatus, false);
            break;
        default: break;
    }
}

void setup() {
    // 1. Serial & Bluetooth Init
    Serial.begin(115200);
    SerialBT.begin("Neduvaai-Mesh-Node");
    
    // 2. GPS Init (RX=16, TX=17)
    gpsSerial.begin(9600, SERIAL_8N1, 16, 17);
    
    // 3. OLED Init
    if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) { 
        Serial.println(F("OLED Allocation Failed"));
    }
    display.display(); delay(1000); display.clearDisplay();
    updateDashboard("Booting System...", false);

    // 4. LMIC Init
    os_init();
    LMIC_reset();
    
    // 5. Start Join Process
    updateDashboard("Starting LoRa...", false);
    preparePacket();
    LMIC_setTxData2(1, (uint8_t*)&myPacket, sizeof(Pkt), 0);
}

void loop() { 
    os_runloop_once(); 
    
    // GPS Parsing Loop (Must run frequently)
    while (gpsSerial.available() > 0) {
        gps.encode(gpsSerial.read());
    }
    
    // UI Refresh (Every 1 second)
    static uint32_t lastUpdate = 0;
    if (millis() - lastUpdate > 1000) {
        // Only refresh if not mid-transmission to avoid flickering
        if (loraStatus != "Transmitting...") {
            updateDashboard(loraStatus, false);
        }
        lastUpdate = millis();
    }
}
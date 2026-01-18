/**
 * =================================================================================
 * NEDUVAAI BOAT TRACKER - NODE FIRMWARE (ESP32 + RFM95W)
 * =================================================================================
 * * HARDWARE PINOUT (Standard Wiring for Neduvaai)
 * -----------------------------------------------------------
 * RFM95 Module      |   ESP32 Pin      |   Description
 * -----------------------------------------------------------
 * 3.3V              |   3V3            |   Power (DO NOT USE 5V!)
 * GND / ANA-GND     |   GND            |   Ground
 * * NSS (CS)        |   GPIO 5         |   Chip Select
 * SCK               |   GPIO 18        |   SPI Clock
 * MOSI              |   GPIO 23        |   SPI Data IN
 * MISO              |   GPIO 19        |   SPI Data OUT
 * * DIO0            |   GPIO 2         |   Interrupt: TxDone / RxDone
 * DIO1              |   GPIO 4         |   Interrupt: RxTimeout (Vital!)
 * RESET             |   GPIO 14        |   Reset Pin
 * * ANTENNA SAFETY CHECKLIST:
 * 1. Measure resistance between Center Pin & Outer Ring of SMA.
 * 2. If BEEP (0 ohms) -> STOP. You have a SHORT. Fix before powering.
 * 3. If SILENCE (Open) -> Safe to power.
 * * =================================================================================
 */

#include <Arduino.h>
#include <lmic.h>
#include <hal/hal.h>
#include <SPI.h>
#include "BluetoothSerial.h"

// =========================================================================
//  1. KEYS (INSERTED)
// =========================================================================
const char* deviceEUI_str = ""; 
const char* appKey_str    = ""; 

// App EUI: 0000000000000000
const char* appEUI_str    = "0000000000000000"; 

// Create Bluetooth Object
BluetoothSerial SerialBT;

// =========================================================================
//  2. PIN MAPPING (MATCHING THE PINOUT ABOVE)
// =========================================================================
const lmic_pinmap lmic_pins = {
    .nss = 5,                       
    .rxtx = LMIC_UNUSED_PIN,
    .rst = 14,                      
    .dio = {2, 4, LMIC_UNUSED_PIN}, // DIO0=2, DIO1=4
};

// =========================================================================
//  3. HELPER FUNCTIONS (REQUIRED BY LMIC)
// =========================================================================
byte nibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return 0;
}

void stringToBytes(const char* str, byte* buffer, int length, boolean reverse) {
  for (int i = 0; i < length; i++) {
    byte val = (nibble(str[i * 2]) << 4) | nibble(str[i * 2 + 1]);
    if (reverse) buffer[length - 1 - i] = val; 
    else buffer[i] = val;                      
  }
}

// These look up the keys defined at the top
void os_getArtEui (u1_t* buf) { stringToBytes(appEUI_str, buf, 8, true); }
void os_getDevEui (u1_t* buf) { stringToBytes(deviceEUI_str, buf, 8, true); }
void os_getDevKey (u1_t* buf) { stringToBytes(appKey_str, buf, 16, false); }

// =========================================================================
//  4. DEBUGGING (SEND TO PHONE AND CABLE)
// =========================================================================
void debug(String msg) {
    Serial.println(msg);      // Send to Serial Monitor
    if (SerialBT.hasClient()) {
        SerialBT.println(msg); // Send to Android Phone
    }
}

// =========================================================================
//  5. EVENT HANDLER & LOGIC
// =========================================================================
static osjob_t sendjob;

void onEvent (ev_t ev) {
    switch(ev) {
        case EV_JOINING: 
            debug("📡 [BT] Joining Network..."); 
            break;
        case EV_JOINED:  
            debug("✅ [BT] JOINED SUCCESS!"); 
            debug("   (Link Check Disabled for Stability)");
            LMIC_setLinkCheckMode(0); // Good for weak signals
            break;
        case EV_TXCOMPLETE: 
            debug("📤 [BT] Uplink Sent (Sleep 30s)");
            // Schedule next transmission in 30 seconds
            os_setTimedCallback(&sendjob, os_getTime()+sec2osticks(30), [](osjob_t* j){
                // Send a simple heartbeat packet
                uint8_t payload[] = "Boat01_Active";
                LMIC_setTxData2(1, payload, sizeof(payload)-1, 0);
            });
            break;
        case EV_JOIN_FAILED: 
            debug("❌ [BT] Join Failed (Check Antenna/Gateway)"); 
            break;
        case EV_TXSTART:
            debug("⚡ [BT] Transmitting...");
            break;
        default: break;
    }
}

void setup() {
    Serial.begin(115200);
    
    // Start Bluetooth
    SerialBT.begin("Neduvaai-Tracker"); 
    Serial.println("\n------------------------------------------------");
    Serial.println("   NEDUVAAI TRACKER - BLUETOOTH MODE ENABLED");
    Serial.println("   1. Pair phone with 'Neduvaai-Tracker'");
    Serial.println("   2. Open Serial Bluetooth Terminal App");
    Serial.println("------------------------------------------------\n");

    os_init();
    LMIC_reset();
    
    // Start initial join
    debug("🚀 System Started. Attempting Join...");
    uint8_t payload[] = "Hello_Neduvaai";
    LMIC_setTxData2(1, payload, sizeof(payload)-1, 0);
}

void loop() { 
    os_runloop_once(); 
}
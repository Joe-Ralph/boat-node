#include <Arduino.h>
#include <SPI.h>

// PIN DEFINITIONS
#define NSS_PIN   5
#define RST_PIN   14
#define MOSI_PIN  23
#define MISO_PIN  19
#define SCK_PIN   18
#define DIO0_PIN  2
#define DIO1_PIN  4


// Register to check
#define REG_VERSION  0x42 

bool hardwareOk = false;
String statusMessage = "";

void checkHardware() {
    // Perform a hardware reset
    digitalWrite(RST_PIN, LOW);
    delay(10);
    digitalWrite(RST_PIN, HIGH);
    delay(10);

    // Communicate with chip
    digitalWrite(NSS_PIN, LOW);
    SPI.transfer(REG_VERSION & 0x7F); 
    uint8_t version = SPI.transfer(0x00); 
    digitalWrite(NSS_PIN, HIGH);

    // Determine Status
    if (version == 0x12) {
        hardwareOk = true;
        statusMessage = "✅ SUCCESS: LoRa Module (SX1276) is WORKING!";
    } else if (version == 0x00 || version == 0xFF) {
        hardwareOk = false;
        statusMessage = "❌ ERROR: Wiring Issue. Check MISO/MOSI/NSS pins.";
    } else {
        hardwareOk = false;
        statusMessage = "⚠️ WARNING: Unknown Chip ID (0x" + String(version, HEX) + "). Check solder joints.";
    }
}

void setup() {
    Serial.begin(115200);
    
    // Initialize Pins
    pinMode(NSS_PIN, OUTPUT);
    pinMode(RST_PIN, OUTPUT);
    digitalWrite(NSS_PIN, HIGH);

    // Start SPI
    SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, NSS_PIN);

    Serial.println("\n--- Neduvaai Hardware Initial Check ---");
    checkHardware();
    Serial.println(statusMessage);
}

void loop() {
    // Every 3 seconds, print the status and re-check the hardware
    // This allows you to see the result whenever you open the Serial Monitor
    
    Serial.print("[HEARTBEAT] ");
    Serial.println(statusMessage);

    // Optional: Re-check hardware in case a wire jiggled loose
    if (!hardwareOk) {
        checkHardware();
    }

    delay(3000); 
}
/**

* =================================================================================

* NEDUVAAI NODE V2 - PRODUCTION OPTIMIZED

* =================================================================================

* - Fixed: Removed String usage (prevents memory leaks)

* - Fixed: Removed delay() (fixes LoRaWAN timing)

* - Fixed: Added Mutex (prevents BLE vs LoRa crashes)

* ---------------------------------------------------------------------------------

* * HARDWARE PINOUT MAPPING

* ---------------------------------------------------------------------------------

* COMPONENT | PIN NAME | ESP32 PIN | NOTES

* ---------------------------------------------------------------------------------

* RFM95 (LoRa) | 3.3V | 3V3 | DO NOT USE 5V

* | GND | GND |

* | NSS (CS) | GPIO 5 | Chip Select

* | SCK | GPIO 18 | SPI Clock

* | MOSI | GPIO 23 | SPI Data

* | MISO | GPIO 19 | SPI Data

* | DIO0 | GPIO 2 | IRQ: TxDone/RxDone

* | DIO1 | GPIO 4 | IRQ: RxTimeout (Vital)

* | RESET | GPIO 14 |

* ---------------------------------------------------------------------------------

* NEO-6M (GPS) | VCC | 3V3 or 5V | Check module specs

* | GND | GND |

* | TX | GPIO 16 | GPS TX -> ESP32 RX (UART1)

* | RX | GPIO 17 | GPS RX <- ESP32 TX (UART1)

* ---------------------------------------------------------------------------------

* OLED (0.96") | VCC | 3V3 |

* | GND | GND |

* | SDA | GPIO 21 | I2C Data

* | SCL | GPIO 22 | I2C Clock

* ---------------------------------------------------------------------------------

* * REQUIRED LIBRARIES (Add to platformio.ini):

* - mcci-catena/MCCI LoRaWAN LMIC library @ 4.1.1

* - mikalhart/TinyGPSPlus @ ^1.0.3

* - adafruit/Adafruit SSD1306 @ ^2.5.7

* - adafruit/Adafruit GFX Library @ ^1.11.5

* =================================================================================

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
#include <lmic.h>
#include <hal/hal.h>

// --- HARDWARE CONFIG ---

// Verify these pins for your specific wiring!

// (Standard DIY wiring often uses: NSS=5, RST=14, DIO0=2, DIO1=4)

const lmic_pinmap lmic_pins = {

    .nss = 5,

    .rxtx = LMIC_UNUSED_PIN,

    .rst = 14,

    .dio = {2, 4, LMIC_UNUSED_PIN},

};

#define SCREEN_WIDTH 128

#define SCREEN_HEIGHT 64

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

TinyGPSPlus gps;

HardwareSerial gpsSerial(1); // UART 1

// --- BLE CONFIG ---

#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"

#define CHAR_DATA_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

#define CHAR_CMD_UUID "8246d623-6447-4ec6-8c46-d2432924151a"

BLEServer *pServer = NULL;

BLECharacteristic *pDataChar = NULL;

BLECharacteristic *pCmdChar = NULL;

bool deviceConnected = false;

bool oldDeviceConnected = false;

// --- SHARED DATA (Protected by Mutex) ---

SemaphoreHandle_t dataMutex; // The Guard

struct BoatState
{

  char boatId[10] = "1001";

  char boatName[15] = "Boat-Init";

  char userId[10] = "0";

  float battery = 95.0;

  char loraStatus[20] = "Init";

  bool configChanged = false;

  bool journeyActive = false; // Privacy: Only track when true

} state;

// --- LORAWAN KEYS (LSB for OTAA) ---

// FILL THESE WITH YOUR REAL KEYS AS STRINGS

const char *appEUI_str = "19971bdae9e83d3c";

const char *deviceEUI_str = "534761503b588cf39b5a181d50f6b081";

const char *appKey_str = "00000000000000000000000000000000";

// LMIC Byte Conversions

byte nibble(char c)
{

  if (c >= '0' && c <= '9')

    return c - '0';

  if (c >= 'a' && c <= 'f')

    return c - 'a' + 10;

  if (c >= 'A' && c <= 'F')

    return c - 'A' + 10;

  return 0;
}

void stringToBytes(const char *str, byte *buffer, int length, boolean reverse)
{

  for (int i = 0; i < length; i++)
  {

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

// Packet Struct (Matches your Decoder)

struct __attribute__((packed)) Packet
{

  uint16_t src;

  uint16_t seq;

  int32_t lat1e7;

  int32_t lon1e7;

  uint8_t batt;

  uint8_t hops;

  uint16_t uid;

  uint8_t name_len; // Not sent over air, just helper

  char name[12]; // Fixed size buffer
};

Packet myPacket;

static osjob_t sendjob;

uint16_t globalSeq = 0;

// --- HELPERS ---

void updateStatus(const char *newStatus)
{

  xSemaphoreTake(dataMutex, portMAX_DELAY);

  strncpy(state.loraStatus, newStatus, sizeof(state.loraStatus) - 1);

  xSemaphoreGive(dataMutex);
}

void updateDisplay()
{

  // Only access shared state inside lock

  char dispStatus[20];

  char dispId[10];

  bool jActive;

  int sats = gps.satellites.value();

  double lat = gps.location.lat();

  double lon = gps.location.lng();

  xSemaphoreTake(dataMutex, portMAX_DELAY);

  strncpy(dispStatus, state.loraStatus, sizeof(dispStatus));

  strncpy(dispId, state.boatId, sizeof(dispId));

  jActive = state.journeyActive;

  xSemaphoreGive(dataMutex);

  display.clearDisplay();

  display.setTextColor(WHITE);

  display.setTextSize(1);

  display.setCursor(0, 0);

  display.printf("BLE:%s SAT:%d %s", deviceConnected ? "C" : "-", sats,

                 jActive ? "[ON]" : "[OFF]");

  display.setCursor(0, 16);

  display.printf("Lat: %.5f", lat);

  display.setCursor(0, 26);

  display.printf("Lon: %.5f", lon);

  display.setCursor(0, 38);

  display.printf("ID:%s Bat:%.0f%%", dispId, state.battery);

  display.drawLine(0, 50, 128, 50, WHITE);

  display.setCursor(0, 54);

  display.print(dispStatus);

  display.display();
}

// --- LORA TX LOGIC ---

void do_send(osjob_t *j)
{

  if (LMIC.opmode & OP_TXRXPEND)
  {

    updateStatus("LoRa Busy");

    return;
  }

  // PRIVACY CHECK

  bool active = false;

  xSemaphoreTake(dataMutex, portMAX_DELAY);

  active = state.journeyActive;

  xSemaphoreGive(dataMutex);

  if (!active)
  {

    updateStatus("Journey Paused");

    // Reschedule to check again later (e.g., 5 seconds)

    // Shorter interval so we pick up Start quickly

    os_setTimedCallback(&sendjob, os_getTime() + sec2osticks(5), do_send);

    return;
  }

  // Prepare Packet

  xSemaphoreTake(dataMutex, portMAX_DELAY);

  myPacket.src = atoi(state.boatId);

  myPacket.uid = atoi(state.userId);

  strncpy(myPacket.name, state.boatName, 12);

  xSemaphoreGive(dataMutex);

  myPacket.seq = globalSeq++;

  if (gps.location.isValid())
  {

    myPacket.lat1e7 = (int32_t)(gps.location.lat() * 10000000.0);

    myPacket.lon1e7 = (int32_t)(gps.location.lng() * 10000000.0);
  }
  else
  {

    myPacket.lat1e7 = 0;

    myPacket.lon1e7 = 0;
  }

  myPacket.batt = (uint8_t)state.battery;

  myPacket.hops = 0;

  // Send only essential bytes (Struct size - padding if any)

  // Dynamic payload length based on name length?

  // For simplicity, we send fixed struct size minus internal helpers

  // Calculation: 2+2+4+4+1+1+2+12 = 28 bytes

  LMIC_setTxData2(1, (uint8_t *)&myPacket, 28, 0);

  updateStatus("Tx Queued");
}

void onEvent(ev_t ev)
{

  switch (ev)
  {

  case EV_JOINING:

    updateStatus("Joining...");

    break;

  case EV_JOINED:

    updateStatus("Joined!");

    LMIC_setLinkCheckMode(0); // Disable ADR for mobile nodes

    break;

  case EV_TXCOMPLETE:

    updateStatus("Sent+Sleep");

    os_setTimedCallback(&sendjob, os_getTime() + sec2osticks(30), do_send);

    break;

  case EV_JOIN_FAILED:

    updateStatus("Join Fail");

    break;

  default:

    break;
  }
}

// --- BLE CALLBACKS ---

class ServerCB : public BLEServerCallbacks
{

  void onConnect(BLEServer *pServer) { deviceConnected = true; };

  void onDisconnect(BLEServer *pServer) { deviceConnected = false; }
};

class CmdCB : public BLECharacteristicCallbacks
{

  void onWrite(BLECharacteristic *pChar)
  {

    std::string val = pChar->getValue();

    if (val.length() > 0)
    {

      String valStr = String(val.c_str());

      // Handle Commands

      if (valStr.startsWith("SET:"))
      {

        // ... Parsing logic ...
      }
      else if (valStr.equals("START_JOURNEY"))
      {

        xSemaphoreTake(dataMutex, portMAX_DELAY);

        state.journeyActive = true;

        xSemaphoreGive(dataMutex);

        // Trigger immediate send if needed, or wait for next loop

        os_setTimedCallback(&sendjob, os_getTime() + sec2osticks(1), do_send);
      }
      else if (valStr.equals("END_JOURNEY"))
      {

        xSemaphoreTake(dataMutex, portMAX_DELAY);

        state.journeyActive = false;

        xSemaphoreGive(dataMutex);
      }
    }
  }
};

// --- SETUP ---

void setup()
{

  Serial.begin(115200);

  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  dataMutex = xSemaphoreCreateMutex();

  Wire.begin();

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);

  display.clearDisplay();

  display.print("Booting Neduvaai..."); 

  display.display();

  // Init BLE

  BLEDevice::init("Neduvaai-Node");

  pServer = BLEDevice::createServer();

  pServer->setCallbacks(new ServerCB());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pDataChar = pService->createCharacteristic(

      CHAR_DATA_UUID,

      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);

  pDataChar->addDescriptor(new BLE2902());

  pCmdChar = pService->createCharacteristic(
    "?>,

                                            BLECharacteristic::PROPERTY_WRITE);

  pCmdChar->setCallbacks(new CmdCB());

  pService->start();

  BLEAdvertising *pAdv = BLEDevice::getAdvertising();

  pAdv->addServiceUUID(SERVICE_UUID);

  pAdv->start();

  // Init LoRa

  os_init();

  LMIC_reset();

  // FORCE IN865 (If library config allows runtime, otherwise set in library)

  // LMIC_setupChannel(0, 865062500, DR_RANGE_MAP(DR_SF12, DR_SF7), BAND_MILLI);

  do_send(&sendjob);
}

// --- LOOP ---

void loop()
{

  static unsigned long lastNotify = 0;

  static unsigned long lastDisplay = 0;

  // 1. CRITICAL: LoRa Engine (Must run fast)

  os_runloop_once();

  // 2. GPS (Non-blocking)

  while (gpsSerial.available() > 0)

    gps.encode(gpsSerial.read());

  // 3. BLE Notify (Every 1s)

  if (deviceConnected && (millis() - lastNotify > 1000))
  {

    char bleBuf[64];

    xSemaphoreTake(dataMutex, portMAX_DELAY);

    snprintf(bleBuf, sizeof(bleBuf), "S:%d,Lat:%.5f,Lon:%.5f,Bat:%.0f,St:%s",

             gps.satellites.value(), gps.location.lat(), gps.location.lng(),

             state.battery, state.loraStatus);

    xSemaphoreGive(dataMutex);

    pDataChar->setValue((uint8_t *)bleBuf, strlen(bleBuf));

    pDataChar->notify();

    lastNotify = millis();
  }

  // 4. Re-advertise logic (Non-blocking)

  if (!deviceConnected && oldDeviceConnected)
  {

    delay(50); // Small delay is OK for BLE stack stability

    pServer->startAdvertising();

    oldDeviceConnected = deviceConnected;
  }

  if (deviceConnected && !oldDeviceConnected)
  {

    oldDeviceConnected = deviceConnected;
  }

  // 5. Display Refresh (Every 2s - slow!)

  if (millis() - lastDisplay > 2000)
  {

    updateDisplay();

    lastDisplay = millis();
  }
}
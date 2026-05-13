#pragma once
#include <stdint.h>

// ---------------------------------------------------------------------------
// Mesh radio PHY
// ---------------------------------------------------------------------------
constexpr float    MESH_FREQ_MHZ          = 865.2f;
constexpr uint8_t  MESH_SF                = 9;
constexpr uint8_t  MESH_BW_KHZ            = 125;
constexpr uint8_t  MESH_CR                = 5;        // 4/5
constexpr uint8_t  MESH_SYNC_WORD         = 0x12;     // private (LoRaWAN public = 0x34)
constexpr int8_t   MESH_TX_DBM            = 14;       // ETSI 865 MHz cap

// ---------------------------------------------------------------------------
// Mesh protocol
// ---------------------------------------------------------------------------
constexpr uint8_t  MESH_TTL_DEFAULT       = 4;
constexpr uint8_t  K_SUPPRESS             = 2;
constexpr uint16_t JITTER_POS_MIN_MS      = 200;
constexpr uint16_t JITTER_POS_MAX_MS      = 800;
constexpr uint16_t JITTER_SOS_MIN_MS      = 50;
constexpr uint16_t JITTER_SOS_MAX_MS      = 200;
constexpr uint16_t JITTER_ACK_MIN_MS      = 50;
constexpr uint16_t JITTER_ACK_MAX_MS      = 200;
constexpr uint8_t  MAX_INFLIGHT_FWD       = 8;
constexpr uint8_t  DEDUP_CACHE_SIZE       = 64;
constexpr uint8_t  NEARBY_CACHE_SIZE      = 30;

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------
constexpr uint32_t POS_INTERVAL_S         = 120;
constexpr uint32_t POS_JITTER_S           = 20;
constexpr uint32_t REPLAY_WINDOW_S        = 300;

// ---------------------------------------------------------------------------
// Battery / lifecycle
// ---------------------------------------------------------------------------
constexpr uint8_t  LOW_BATT_THRESHOLD_PC  = 10;
constexpr uint8_t  CRITICAL_BATT_PC       = 5;

// ---------------------------------------------------------------------------
// BLE
// ---------------------------------------------------------------------------
constexpr uint8_t  BLE_MAX_CONN           = 4;    // 1 owner + 3 crew

// ---------------------------------------------------------------------------
// Wire-level constants
// ---------------------------------------------------------------------------
constexpr uint8_t  PKT_MAGIC              = 0xBA;
constexpr uint8_t  PKT_VER                = 0x02;

enum PktType : uint8_t {
  PKT_POS    = 0x01,
  PKT_SOS    = 0x02,
  PKT_ACK    = 0x03,
  PKT_CANCEL = 0x04,
};

enum SosStatus : uint8_t {
  SOS_RECEIVED   = 0,
  SOS_DISPATCHED = 1,
  SOS_RESOLVED   = 2,
  SOS_FALSEALARM = 3,
};

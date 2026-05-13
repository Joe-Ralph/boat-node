#include "ble/auth.h"
#include "mesh/hmac_util.h"
#include <string.h>

#ifdef ARDUINO
  #include <Arduino.h>
  #include <esp_system.h>      // esp_random
#else
  // Host-side stub. Tests inject a deterministic seed via esp_random_stub_set().
  #include <stdlib.h>
  static uint32_t (*g_random)() = nullptr;
  void esp_random_stub_set(uint32_t (*fn)()) { g_random = fn; }
  static uint32_t esp_random() { return g_random ? g_random() : (uint32_t)rand(); }
#endif

namespace {
constexpr uint32_t STRANGER_IDLE_MS = 10000;
}

BleAuth::Conn* BleAuth::find(uint16_t h) {
  for (auto& c : conns_) {
    if (c.active && c.handle == h) return &c;
  }
  return nullptr;
}

BleAuth::Conn* BleAuth::slot() {
  for (auto& c : conns_) {
    if (!c.active) return &c;
  }
  return nullptr;
}

void BleAuth::on_connect(uint16_t conn_handle) {
  Conn* c = slot();
  if (!c) return;        // queue full; caller should reject
  c->active       = true;
  c->handle       = conn_handle;
  c->tier         = BleTier::STRANGER;
  c->connected_ms = 0;   // populated when challenge is read
  // Seed challenge eagerly.
  for (uint8_t i = 0; i < 16; i += 4) {
    uint32_t r = esp_random();
    c->challenge[i + 0] = (r >>  0) & 0xFF;
    c->challenge[i + 1] = (r >>  8) & 0xFF;
    c->challenge[i + 2] = (r >> 16) & 0xFF;
    c->challenge[i + 3] = (r >> 24) & 0xFF;
  }
}

void BleAuth::on_disconnect(uint16_t conn_handle) {
  Conn* c = find(conn_handle);
  if (c) *c = {};
}

bool BleAuth::challenge_for(uint16_t conn_handle, uint8_t out[16]) {
  Conn* c = find(conn_handle);
  if (!c) return false;
  memcpy(out, c->challenge, 16);
#ifdef ARDUINO
  c->connected_ms = millis();
#else
  c->connected_ms = 0;
#endif
  return true;
}

BleTier BleAuth::verify_response(uint16_t conn_handle, BleTier hint,
                                 const uint8_t proof[8],
                                 const uint8_t hmac_secret[16],
                                 const uint8_t crew_token[8]) {
  Conn* c = find(conn_handle);
  if (!c) return BleTier::STRANGER;

  const uint8_t* key = nullptr;
  size_t         key_len = 0;
  switch (hint) {
    case BleTier::OWNER: key = hmac_secret; key_len = 16; break;
    case BleTier::CREW:  key = crew_token;  key_len = 8;  break;
    case BleTier::STRANGER:
    default:
      return BleTier::STRANGER;
  }
  if (!key) return BleTier::STRANGER;

  // BLE proofs are 8 bytes per spec §"Auth handshake" (mesh HMAC trunc is 4).
  uint8_t expected[32] = {0};
  hmac_sha256_full(key, key_len, c->challenge, 16, expected);

  uint8_t diff = 0;
  for (int i = 0; i < 8; ++i) diff |= (expected[i] ^ proof[i]);
  if (diff != 0) return BleTier::STRANGER;

  c->tier = hint;
  return hint;
}

BleTier BleAuth::tier(uint16_t conn_handle) const {
  for (const auto& c : conns_) {
    if (c.active && c.handle == conn_handle) return c.tier;
  }
  return BleTier::STRANGER;
}

uint8_t BleAuth::reap_stale(uint32_t now_ms, uint16_t* out_handles, uint8_t cap) {
  uint8_t n = 0;
  for (auto& c : conns_) {
    if (!c.active || c.tier != BleTier::STRANGER) continue;
    if (c.connected_ms == 0) continue;        // challenge never read
    if (now_ms - c.connected_ms < STRANGER_IDLE_MS) continue;
    if (n < cap) out_handles[n++] = c.handle;
  }
  return n;
}

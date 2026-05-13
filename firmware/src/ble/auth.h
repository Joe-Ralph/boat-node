#pragma once
#include <stdint.h>
#include "ble/acl.h"

// Per-connection BLE authentication state.
// Each connection starts as STRANGER. Phone reads AUTH_CHALLENGE (16 random
// bytes), writes AUTH_RESPONSE = {tier_hint, HMAC_SHA256(token, challenge)[:8]},
// device verifies and promotes the tier on success.
//
// State is bench-tested (hardware-bound). The ACL matrix it consults lives
// in ble/acl.h and is unit-tested host-side.

class BleAuth {
public:
  static constexpr uint8_t MAX = 4;        // BLE_MAX_CONN

  // Lifecycle: GATT callbacks notify connect / disconnect.
  void on_connect(uint16_t conn_handle);
  void on_disconnect(uint16_t conn_handle);

  // Fill `out` with a fresh 16-byte challenge for this connection.
  // Returns false if conn_handle is unknown.
  bool challenge_for(uint16_t conn_handle, uint8_t out[16]);

  // Verify the phone's response. Looks up the connection's challenge,
  // computes HMAC(token, challenge)[:8] internally, compares (consteq).
  // On success promotes tier_ to `hint`. Returns final tier.
  BleTier verify_response(uint16_t conn_handle,
                          BleTier hint,
                          const uint8_t proof[8],
                          const uint8_t hmac_secret[16],
                          const uint8_t crew_token[8]);

  BleTier tier(uint16_t conn_handle) const;

  // Drives idle disconnect after 10 s if tier == STRANGER.
  // Returns count of connections to disconnect; caller iterates handles.
  uint8_t reap_stale(uint32_t now_ms, uint16_t* out_handles, uint8_t cap);

private:
  struct Conn {
    bool     active;
    uint16_t handle;
    uint8_t  challenge[16];
    BleTier  tier;
    uint32_t connected_ms;
  };
  Conn conns_[MAX] = {};

  Conn* find(uint16_t h);
  Conn* slot();
};

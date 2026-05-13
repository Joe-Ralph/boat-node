#pragma once

// NVS (Preferences) key layout. Namespace: "boat_cfg".
// Secrets (hmac_secret, crew_token, lorawan_devkey) have internal-only readers.
// NEVER expose via BLE characteristic read.

namespace nvs_keys {
constexpr const char* NS                          = "boat_cfg";

constexpr const char* PAIRED                      = "paired";
constexpr const char* MESH_SRC_ID                 = "mesh_src_id";
constexpr const char* BOAT_ID                     = "boat_id";
constexpr const char* USER_ID                     = "user_id";
constexpr const char* DISPLAY_NAME                = "display_name";

constexpr const char* HMAC_SECRET                 = "hmac_secret";    // 16 B blob
constexpr const char* CREW_TOKEN                  = "crew_token";     // 8 B blob

constexpr const char* RELAY_MODE                  = "relay_mode";
constexpr const char* LAST_SOS_SEQ                = "last_sos_seq";
constexpr const char* LAST_JOURNEY_TOGGLE_USER    = "last_jt_user";

constexpr const char* LORAWAN_DEVKEY              = "lw_devkey";      // 16 B
constexpr const char* LORAWAN_APPEUI              = "lw_appeui";      // 8 B
constexpr const char* LORAWAN_DEVEUI              = "lw_deveui";      // 8 B

constexpr const char* LAST_SHUTDOWN_REASON        = "shutdown_rsn";
}  // namespace nvs_keys

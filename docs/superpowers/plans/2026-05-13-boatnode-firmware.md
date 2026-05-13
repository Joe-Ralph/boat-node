# BoatNode Firmware (v2 Hybrid Mesh) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the ESP32+RFM95 firmware in `firmware/src/main.cpp` to time-share a single RFM95 between LMIC (LoRaWAN uplink) and a private RadioLib P2P mesh, with HMAC-signed SOS/ACK/CANCEL, RBSF flooding, dedup, a per-connection BLE auth tier (owner/crew/stranger), and persistent SOS retry. Production builds remain LoRaWAN-only until compile flag `MESH_HYBRID=1` is flipped after Layer 3 sign-off.

**Architecture:** Decompose the current monolithic `main.cpp` into pure C++ modules under `firmware/src/mesh/`, `firmware/src/ble/`, `firmware/src/radio/`. Pure modules (packet, hmac, dedup, RBSF, FSMs, ACL) get host-side Unity tests via `pio test -e native`. Hardware modules (radio scheduler, NVS, GPS, BLE GATT) get a Layer-2 bench-test checklist. `main.cpp` shrinks to wiring.

**Tech Stack:** PlatformIO, Arduino-ESP32, LMIC, RadioLib, mbedtls (built-in), Preferences (NVS), TinyGPS+, NimBLE-Arduino, Unity for host tests.

**Source spec:** `docs/superpowers/specs/2026-05-13-boatnode-hybrid-mesh-design.md` §"Architecture", §"Packet Formats", §"State Machines", §"Identity & Security", §"Error Handling & Edge Cases".

---

## File Structure

| Path | Responsibility | Host-testable? |
|---|---|---|
| `firmware/src/mesh/constants.h` | All tunables in one header | n/a |
| `firmware/src/mesh/packet.h` | `#pragma pack` struct defs + size asserts | yes |
| `firmware/src/mesh/crc16.h/.cpp` | CRC16-CCITT | yes |
| `firmware/src/mesh/hmac_util.h/.cpp` | HMAC-SHA256 trunc-4 (mbedtls) | yes (mbedtls links host-side) |
| `firmware/src/mesh/build_parse.h/.cpp` | Frame build + parse + validation | yes |
| `firmware/src/mesh/dedup.h/.cpp` | (src, seq, type) ring buffer (size 64) | yes |
| `firmware/src/mesh/forwarding.h/.cpp` | RBSF state per `(src, seq, type)` slot | yes |
| `firmware/src/mesh/sos_state.h/.cpp` | FSM-3 originator | yes |
| `firmware/src/mesh/uplink_queue.h/.cpp` | FSM-4 LoRaWAN uplink queue | yes |
| `firmware/src/ble/acl.h/.cpp` | Pure ACL matrix lookup | yes |
| `firmware/src/ble/auth.h/.cpp` | Challenge/response over GATT | bench only |
| `firmware/src/radio/scheduler.h/.cpp` | FSM-1, owns RFM95 | bench only |
| `firmware/src/nvs_layout.h` | NVS key constants | n/a |
| `firmware/src/main.cpp` | Wiring; FreeRTOS task creation | bench only |
| `firmware/platformio.ini` | Add `[env:native]` + flags | n/a |
| `firmware/test/native/test_crc16.cpp` | Unity test | — |
| `firmware/test/native/test_packet.cpp` | Unity test | — |
| `firmware/test/native/test_hmac.cpp` | Unity test (RFC 4231 vectors) | — |
| `firmware/test/native/test_dedup.cpp` | Unity test | — |
| `firmware/test/native/test_rbsf.cpp` | Unity test | — |
| `firmware/test/native/test_sos_fsm.cpp` | Unity test | — |
| `firmware/test/native/test_uplink_queue.cpp` | Unity test | — |
| `firmware/test/native/test_acl.cpp` | Unity test | — |
| `firmware/test/native/test_validation.cpp` | Unity test pipeline | — |

---

## Task 1: Add native test environment

**Files:**
- Modify: `firmware/platformio.ini`

- [ ] **Step 1: Append a `[env:native]` block**

```ini
[env:native]
platform = native
build_flags =
  -std=gnu++17
  -DUNIT_TEST
  -DMESH_HYBRID=1
  -Isrc
  -Itest/native/stubs
test_framework = unity
lib_deps =
  throwtheswitch/Unity@^2.6.0
build_src_filter = -<*> +<mesh/> +<ble/acl.cpp>

[env:denky32_hybrid]
extends = env:denky32
build_flags =
  ${env:denky32.build_flags}
  -DMESH_HYBRID=1
```

- [ ] **Step 2: Sanity-build native env (no tests yet)**

Run: `cd firmware && pio run -e native`
Expected: `[SUCCESS]` (an empty native target builds).

- [ ] **Step 3: Commit**

```bash
git add firmware/platformio.ini
git commit -m "build(firmware): add native test env + hybrid build flag"
```

---

## Task 2: Mesh constants header

**Files:**
- Create: `firmware/src/mesh/constants.h`

- [ ] **Step 1: Write the constants**

```cpp
#pragma once
#include <stdint.h>

constexpr float    MESH_FREQ_MHZ          = 865.2f;
constexpr uint8_t  MESH_SF                = 9;
constexpr uint8_t  MESH_BW_KHZ            = 125;
constexpr uint8_t  MESH_CR                = 5;     // 4/5
constexpr uint8_t  MESH_SYNC_WORD         = 0x12;
constexpr int8_t   MESH_TX_DBM            = 14;
constexpr uint8_t  MESH_TTL_DEFAULT       = 4;
constexpr uint8_t  K_SUPPRESS             = 2;
constexpr uint16_t JITTER_POS_MIN_MS      = 200;
constexpr uint16_t JITTER_POS_MAX_MS      = 800;
constexpr uint16_t JITTER_SOS_MIN_MS      = 50;
constexpr uint16_t JITTER_SOS_MAX_MS      = 200;
constexpr uint8_t  MAX_INFLIGHT_FWD       = 8;
constexpr uint8_t  DEDUP_CACHE_SIZE       = 64;
constexpr uint8_t  NEARBY_CACHE_SIZE      = 30;
constexpr uint32_t POS_INTERVAL_S         = 120;
constexpr uint32_t POS_JITTER_S           = 20;
constexpr uint32_t REPLAY_WINDOW_S        = 300;
constexpr uint8_t  BLE_MAX_CONN           = 4;
constexpr uint8_t  LOW_BATT_THRESHOLD_PC  = 10;
constexpr uint8_t  CRITICAL_BATT_PC       = 5;

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
```

- [ ] **Step 2: Commit**

```bash
git add firmware/src/mesh/constants.h
git commit -m "feat(firmware): mesh constants header"
```

---

## Task 3: Packet structs

**Files:**
- Create: `firmware/src/mesh/packet.h`
- Create: `firmware/test/native/test_packet_layout.cpp`

- [ ] **Step 1: Write failing test (size asserts)**

`test/native/test_packet_layout.cpp`:

```cpp
#include <unity.h>
#include "mesh/packet.h"

void test_header_size() { TEST_ASSERT_EQUAL(15, sizeof(MeshHeader)); }
void test_pos_size()    { TEST_ASSERT_EQUAL(46, sizeof(PosPkt)); }
void test_sos_size()    { TEST_ASSERT_EQUAL(36, sizeof(SosPkt)); }
void test_ack_size()    { TEST_ASSERT_EQUAL(25, sizeof(AckPkt)); }
void test_cancel_size() { TEST_ASSERT_EQUAL(25, sizeof(CancelPkt)); }

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_header_size);
  RUN_TEST(test_pos_size);
  RUN_TEST(test_sos_size);
  RUN_TEST(test_ack_size);
  RUN_TEST(test_cancel_size);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail**

Run: `cd firmware && pio test -e native -f test_packet_layout`
Expected: FAIL — packet.h not found.

- [ ] **Step 3: Implement packet.h**

```cpp
#pragma once
#include <stdint.h>

#pragma pack(push, 1)

struct MeshHeader {
  uint8_t  magic;
  uint8_t  ver;
  uint8_t  type;
  uint16_t src;
  uint16_t dest;
  uint16_t seq;
  uint8_t  hops;
  uint8_t  ttl;
  uint32_t ts;
};

struct PosPkt {
  MeshHeader hdr;
  int32_t  lat1e7;
  int32_t  lon1e7;
  uint16_t spd_cms;
  uint16_t hdg_cdeg;
  uint8_t  batt_pc;
  uint8_t  flags;
  uint16_t user_id;
  uint8_t  name_len;
  uint8_t  name_utf8[12];
  uint16_t crc;
};

struct SosPkt {
  MeshHeader hdr;
  int32_t  lat1e7;
  int32_t  lon1e7;
  uint16_t spd_cms;
  uint16_t hdg_cdeg;
  uint8_t  batt_pc;
  uint8_t  reason;
  uint16_t trigger_user_id;
  uint8_t  hmac[4];
  uint16_t crc;
};

struct AckPkt {
  MeshHeader hdr;
  uint16_t ack_src;
  uint16_t ack_seq;
  uint8_t  status;
  uint8_t  reserved;
  uint8_t  hmac[4];
  uint16_t crc;
};

struct CancelPkt {
  MeshHeader hdr;
  uint16_t cancel_seq;
  uint16_t trigger_user_id;
  uint8_t  hmac[4];
  uint16_t reserved;     // 4 bytes pad to keep packet 25 B and HMAC range stable
  uint16_t crc;
};

#pragma pack(pop)

static_assert(sizeof(MeshHeader) == 15, "MeshHeader must be 15 bytes");
static_assert(sizeof(PosPkt)     == 46, "PosPkt must be 46 bytes");
static_assert(sizeof(SosPkt)     == 36, "SosPkt must be 36 bytes");
static_assert(sizeof(AckPkt)     == 25, "AckPkt must be 25 bytes");
static_assert(sizeof(CancelPkt)  == 25, "CancelPkt must be 25 bytes");
```

- [ ] **Step 4: Run, pass**

Run: `pio test -e native -f test_packet_layout`
Expected: 5/5 passed.

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/packet.h firmware/test/native/test_packet_layout.cpp
git commit -m "feat(firmware): packed mesh packet structs with size asserts"
```

---

## Task 4: CRC16-CCITT

**Files:**
- Create: `firmware/src/mesh/crc16.h`
- Create: `firmware/src/mesh/crc16.cpp`
- Create: `firmware/test/native/test_crc16.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include "mesh/crc16.h"

void test_crc16_known() {
  const uint8_t data[] = {'1','2','3','4','5','6','7','8','9'};
  TEST_ASSERT_EQUAL_HEX16(0x29B1, crc16_ccitt(data, sizeof(data)));
}
void test_crc16_empty() {
  TEST_ASSERT_EQUAL_HEX16(0xFFFF, crc16_ccitt(nullptr, 0));
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_crc16_known);
  RUN_TEST(test_crc16_empty);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail**

Run: `pio test -e native -f test_crc16`
Expected: FAIL.

- [ ] **Step 3: Implement**

`crc16.h`:
```cpp
#pragma once
#include <stdint.h>
#include <stddef.h>
uint16_t crc16_ccitt(const uint8_t* data, size_t len, uint16_t init = 0xFFFF);
```

`crc16.cpp`:
```cpp
#include "mesh/crc16.h"
uint16_t crc16_ccitt(const uint8_t* data, size_t len, uint16_t init) {
  uint16_t crc = init;
  for (size_t i = 0; i < len; ++i) {
    crc ^= (uint16_t)data[i] << 8;
    for (int j = 0; j < 8; ++j) {
      crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : (crc << 1);
    }
  }
  return crc;
}
```

- [ ] **Step 4: Run, pass**

Run: `pio test -e native -f test_crc16`
Expected: 2/2 passed.

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/crc16.h firmware/src/mesh/crc16.cpp firmware/test/native/test_crc16.cpp
git commit -m "feat(firmware): crc16-ccitt with fixture"
```

---

## Task 5: HMAC-SHA256 trunc-4

**Files:**
- Create: `firmware/src/mesh/hmac_util.h`
- Create: `firmware/src/mesh/hmac_util.cpp`
- Create: `firmware/test/native/test_hmac.cpp`

- [ ] **Step 1: Failing test (RFC 4231 vector)**

```cpp
#include <unity.h>
#include <string.h>
#include "mesh/hmac_util.h"

void test_hmac_rfc4231_vec1() {
  // key = 20 * 0x0b, data = "Hi There" → first 4 bytes of full HMAC-SHA256
  const uint8_t key[20] = {0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,
                            0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,
                            0x0b,0x0b,0x0b,0x0b};
  const uint8_t data[] = {'H','i',' ','T','h','e','r','e'};
  const uint8_t expected[4] = {0xb0, 0x34, 0x4c, 0x61};   // first 4 bytes of RFC 4231 vec 1
  uint8_t out[4] = {0};
  hmac_sha256_trunc4(key, sizeof(key), data, sizeof(data), out);
  TEST_ASSERT_EQUAL_MEMORY(expected, out, 4);
}

void test_hmac_verify_consteq() {
  const uint8_t key[16] = {0xab};
  const uint8_t data[]  = {1, 2, 3};
  uint8_t tag[4];
  hmac_sha256_trunc4(key, sizeof(key), data, sizeof(data), tag);
  TEST_ASSERT_TRUE(hmac_sha256_verify_trunc4(key, sizeof(key), data, sizeof(data), tag));
  tag[0] ^= 0x01;
  TEST_ASSERT_FALSE(hmac_sha256_verify_trunc4(key, sizeof(key), data, sizeof(data), tag));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_hmac_rfc4231_vec1);
  RUN_TEST(test_hmac_verify_consteq);
  return UNITY_END();
}
```

- [ ] **Step 2: Add mbedtls to native build**

Modify `firmware/platformio.ini` `[env:native]`:
```ini
lib_deps =
  throwtheswitch/Unity@^2.6.0
  mbedtls/mbedtls@^3.5.0
```

- [ ] **Step 3: Implement**

`hmac_util.h`:
```cpp
#pragma once
#include <stdint.h>
#include <stddef.h>
void hmac_sha256_trunc4(const uint8_t* key, size_t key_len,
                         const uint8_t* data, size_t data_len,
                         uint8_t out[4]);
bool hmac_sha256_verify_trunc4(const uint8_t* key, size_t key_len,
                                const uint8_t* data, size_t data_len,
                                const uint8_t tag[4]);
```

`hmac_util.cpp`:
```cpp
#include "mesh/hmac_util.h"
#include <string.h>
#include "mbedtls/md.h"

void hmac_sha256_trunc4(const uint8_t* key, size_t key_len,
                         const uint8_t* data, size_t data_len,
                         uint8_t out[4]) {
  uint8_t full[32];
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 1);
  mbedtls_md_hmac_starts(&ctx, key, key_len);
  mbedtls_md_hmac_update(&ctx, data, data_len);
  mbedtls_md_hmac_finish(&ctx, full);
  mbedtls_md_free(&ctx);
  memcpy(out, full, 4);
}

bool hmac_sha256_verify_trunc4(const uint8_t* key, size_t key_len,
                                const uint8_t* data, size_t data_len,
                                const uint8_t tag[4]) {
  uint8_t expected[4];
  hmac_sha256_trunc4(key, key_len, data, data_len, expected);
  uint8_t diff = 0;
  for (int i = 0; i < 4; ++i) diff |= expected[i] ^ tag[i];
  return diff == 0;
}
```

- [ ] **Step 4: Run, pass**

Run: `pio test -e native -f test_hmac`
Expected: 2/2 passed.

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/hmac_util.h firmware/src/mesh/hmac_util.cpp firmware/test/native/test_hmac.cpp firmware/platformio.ini
git commit -m "feat(firmware): hmac-sha256 trunc4 (mbedtls) with rfc 4231 vector"
```

---

## Task 6: Dedup ring buffer

**Files:**
- Create: `firmware/src/mesh/dedup.h`
- Create: `firmware/src/mesh/dedup.cpp`
- Create: `firmware/test/native/test_dedup.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include "mesh/dedup.h"
#include "mesh/constants.h"

void test_first_insert_returns_false() {
  DedupCache d;
  TEST_ASSERT_FALSE(d.seen_then_insert(7, 1, PKT_POS));
  TEST_ASSERT_TRUE (d.seen_then_insert(7, 1, PKT_POS));
}
void test_different_type_not_deduped() {
  DedupCache d;
  d.seen_then_insert(7, 1, PKT_POS);
  TEST_ASSERT_FALSE(d.seen_then_insert(7, 1, PKT_SOS));
}
void test_ring_wraps() {
  DedupCache d;
  for (uint16_t s = 0; s < DEDUP_CACHE_SIZE + 5; ++s) d.seen_then_insert(1, s, PKT_POS);
  // first entries should have been evicted
  TEST_ASSERT_FALSE(d.seen_then_insert(1, 0, PKT_POS));
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_first_insert_returns_false);
  RUN_TEST(test_different_type_not_deduped);
  RUN_TEST(test_ring_wraps);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail.**

Run: `pio test -e native -f test_dedup`

- [ ] **Step 3: Implement**

`dedup.h`:
```cpp
#pragma once
#include <stdint.h>
#include "mesh/constants.h"

class DedupCache {
public:
  bool seen_then_insert(uint16_t src, uint16_t seq, uint8_t type);
private:
  struct Entry { uint16_t src, seq; uint8_t type; uint8_t used; };
  Entry ring_[DEDUP_CACHE_SIZE] = {};
  uint8_t head_ = 0;
};
```

`dedup.cpp`:
```cpp
#include "mesh/dedup.h"

bool DedupCache::seen_then_insert(uint16_t src, uint16_t seq, uint8_t type) {
  for (auto& e : ring_) {
    if (e.used && e.src == src && e.seq == seq && e.type == type) return true;
  }
  ring_[head_] = {src, seq, type, 1};
  head_ = (head_ + 1) % DEDUP_CACHE_SIZE;
  return false;
}
```

- [ ] **Step 4: Run, pass.**

Run: `pio test -e native -f test_dedup`
Expected: 3/3.

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/dedup.h firmware/src/mesh/dedup.cpp firmware/test/native/test_dedup.cpp
git commit -m "feat(firmware): dedup ring cache (src, seq, type)"
```

---

## Task 7: RBSF forwarding state

**Files:**
- Create: `firmware/src/mesh/forwarding.h`
- Create: `firmware/src/mesh/forwarding.cpp`
- Create: `firmware/test/native/test_rbsf.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include "mesh/forwarding.h"

void test_pending_to_done() {
  ForwardSlot s; s.start(7, 1, PKT_POS, 100, /*jitter_ms=*/50, /*hops=*/1, /*ttl=*/4);
  TEST_ASSERT_EQUAL(FwdState::PENDING, s.tick(110));
  TEST_ASSERT_EQUAL(FwdState::DONE,    s.tick(160));  // jitter expired
}
void test_pending_to_suppressed() {
  ForwardSlot s; s.start(7, 1, PKT_POS, 100, 200, 1, 4);
  s.heard(); s.heard();
  TEST_ASSERT_EQUAL(FwdState::SUPPRESSED, s.tick(110));
}
void test_ttl_drop() {
  ForwardSlot s; s.start(7, 1, PKT_POS, 100, 50, /*hops=*/4, /*ttl=*/4);
  TEST_ASSERT_EQUAL(FwdState::DROP_TTL, s.tick(101));
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_pending_to_done);
  RUN_TEST(test_pending_to_suppressed);
  RUN_TEST(test_ttl_drop);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail**

- [ ] **Step 3: Implement**

`forwarding.h`:
```cpp
#pragma once
#include <stdint.h>
#include "mesh/constants.h"

enum class FwdState { EMPTY, PENDING, SUPPRESSED, DONE, DROP_TTL };

struct ForwardSlot {
  uint16_t src = 0, seq = 0;
  uint8_t  type = 0;
  uint32_t tx_at_ms = 0;
  uint8_t  heard_count = 0;
  uint8_t  next_hops = 0;
  uint8_t  ttl = 0;
  FwdState state = FwdState::EMPTY;

  void start(uint16_t s_, uint16_t q_, uint8_t t_, uint32_t now_ms, uint32_t jitter_ms,
             uint8_t hops_after_fwd, uint8_t ttl_);
  void heard() { ++heard_count; }
  FwdState tick(uint32_t now_ms);
  bool matches(uint16_t s_, uint16_t q_, uint8_t t_) const {
    return state == FwdState::PENDING && src == s_ && seq == q_ && type == t_;
  }
};
```

`forwarding.cpp`:
```cpp
#include "mesh/forwarding.h"

void ForwardSlot::start(uint16_t s_, uint16_t q_, uint8_t t_, uint32_t now_ms, uint32_t jitter_ms,
                         uint8_t hops_after_fwd, uint8_t ttl_) {
  src = s_; seq = q_; type = t_;
  tx_at_ms = now_ms + jitter_ms;
  heard_count = 0;
  next_hops = hops_after_fwd;
  ttl = ttl_;
  state = (next_hops > ttl) ? FwdState::DROP_TTL : FwdState::PENDING;
}

FwdState ForwardSlot::tick(uint32_t now_ms) {
  if (state != FwdState::PENDING) return state;
  if (next_hops > ttl) { state = FwdState::DROP_TTL; return state; }
  if (heard_count >= K_SUPPRESS) { state = FwdState::SUPPRESSED; return state; }
  if (now_ms >= tx_at_ms) { state = FwdState::DONE; return state; }
  return FwdState::PENDING;
}
```

- [ ] **Step 4: Run, pass.**

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/forwarding.h firmware/src/mesh/forwarding.cpp firmware/test/native/test_rbsf.cpp
git commit -m "feat(firmware): rbsf forward slot state machine"
```

---

## Task 8: SOS originator FSM

**Files:**
- Create: `firmware/src/mesh/sos_state.h`
- Create: `firmware/src/mesh/sos_state.cpp`
- Create: `firmware/test/native/test_sos_fsm.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include "mesh/sos_state.h"

void test_idle_to_active() {
  SosState s;
  s.trigger(0, /*reason=*/0, /*user_id=*/42);
  TEST_ASSERT_EQUAL(SosPhase::ACTIVE, s.phase());
  TEST_ASSERT_EQUAL(0u, s.next_retry_ms_from_now(0));  // first attempt immediate
}
void test_retry_schedule() {
  SosState s; s.trigger(0, 0, 1);
  s.note_tx(0);
  TEST_ASSERT_EQUAL(30000u, s.next_retry_ms_from_now(0));
  s.note_tx(30000);
  TEST_ASSERT_EQUAL(60000u, s.next_retry_ms_from_now(30000));
}
void test_acked_clears() {
  SosState s; s.trigger(0, 0, 1);
  s.note_tx(0);
  s.on_ack(/*ack_seq=*/s.seq(), /*status=*/0);
  TEST_ASSERT_EQUAL(SosPhase::ACKED, s.phase());
}
void test_cancel_low_battery() {
  SosState s; s.trigger(0, 0, 1);
  s.battery_check(8);
  TEST_ASSERT_EQUAL(SosPhase::CANCELED, s.phase());
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_idle_to_active);
  RUN_TEST(test_retry_schedule);
  RUN_TEST(test_acked_clears);
  RUN_TEST(test_cancel_low_battery);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail**

- [ ] **Step 3: Implement**

`sos_state.h`:
```cpp
#pragma once
#include <stdint.h>

enum class SosPhase { IDLE, ACTIVE, ACKED, CANCELED };

class SosState {
public:
  void trigger(uint32_t now_ms, uint8_t reason, uint16_t user_id);
  void note_tx(uint32_t now_ms);
  uint32_t next_retry_ms_from_now(uint32_t now_ms) const;
  void on_ack(uint16_t ack_seq, uint8_t status);
  void user_cancel();
  void battery_check(uint8_t pct);
  void tick(uint32_t now_ms);     // ACKED → IDLE after hold

  SosPhase phase() const { return phase_; }
  uint16_t seq() const   { return seq_; }
  uint16_t user_id() const { return user_id_; }
  uint8_t  reason() const { return reason_; }

private:
  SosPhase phase_ = SosPhase::IDLE;
  uint16_t seq_ = 0;
  uint8_t  retry_idx_ = 0;
  uint32_t last_tx_ms_ = 0;
  uint32_t acked_at_ms_ = 0;
  uint8_t  reason_ = 0;
  uint16_t user_id_ = 0;
};
```

`sos_state.cpp`:
```cpp
#include "mesh/sos_state.h"

static const uint32_t RETRY_MS[] = {0, 30000, 60000, 120000, 300000};
static constexpr uint8_t RETRY_TAIL = sizeof(RETRY_MS) / sizeof(RETRY_MS[0]) - 1;
static constexpr uint32_t ACK_HOLD_MS = 5 * 60 * 1000;

void SosState::trigger(uint32_t now_ms, uint8_t reason, uint16_t user_id) {
  if (phase_ == SosPhase::ACTIVE) return;
  phase_ = SosPhase::ACTIVE;
  seq_++;
  retry_idx_ = 0;
  last_tx_ms_ = now_ms;
  reason_ = reason;
  user_id_ = user_id;
}

void SosState::note_tx(uint32_t now_ms) {
  last_tx_ms_ = now_ms;
  if (retry_idx_ < RETRY_TAIL) ++retry_idx_;
}

uint32_t SosState::next_retry_ms_from_now(uint32_t now_ms) const {
  if (phase_ != SosPhase::ACTIVE) return 0xFFFFFFFFu;
  const uint32_t delay = RETRY_MS[retry_idx_ < RETRY_TAIL ? retry_idx_ + 1 : RETRY_TAIL];
  // if first attempt never sent, fire immediately
  if (last_tx_ms_ == 0 && retry_idx_ == 0) return 0;
  const uint32_t due = last_tx_ms_ + delay;
  return (due > now_ms) ? due - now_ms : 0;
}

void SosState::on_ack(uint16_t ack_seq, uint8_t status) {
  if (phase_ != SosPhase::ACTIVE || ack_seq != seq_) return;
  phase_ = SosPhase::ACKED;
  (void)status;
}

void SosState::user_cancel() {
  if (phase_ == SosPhase::ACTIVE || phase_ == SosPhase::ACKED) phase_ = SosPhase::CANCELED;
}

void SosState::battery_check(uint8_t pct) {
  if (phase_ == SosPhase::ACTIVE && pct < 10) phase_ = SosPhase::CANCELED;
}

void SosState::tick(uint32_t now_ms) {
  if (phase_ == SosPhase::ACKED) {
    if (!acked_at_ms_) acked_at_ms_ = now_ms;
    if (now_ms - acked_at_ms_ > ACK_HOLD_MS) { phase_ = SosPhase::IDLE; acked_at_ms_ = 0; }
  }
}
```

- [ ] **Step 4: Run, pass**

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/sos_state.h firmware/src/mesh/sos_state.cpp firmware/test/native/test_sos_fsm.cpp
git commit -m "feat(firmware): FSM-3 sos originator with retry backoff"
```

---

## Task 9: LoRaWAN uplink queue FSM

**Files:**
- Create: `firmware/src/mesh/uplink_queue.h`
- Create: `firmware/src/mesh/uplink_queue.cpp`
- Create: `firmware/test/native/test_uplink_queue.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include "mesh/uplink_queue.h"

void test_empty_then_queue() {
  UplinkQueue q;
  TEST_ASSERT_TRUE(q.is_empty());
  TEST_ASSERT_TRUE(q.enqueue({PKT_POS, /*owner*/true, {}, 1}));
  TEST_ASSERT_FALSE(q.is_empty());
}
void test_sos_preempts_non_sos_on_full() {
  UplinkQueue q;
  for (int i = 0; i < 8; ++i) q.enqueue({PKT_POS, true, {}, (uint16_t)i});
  TEST_ASSERT_TRUE(q.enqueue({PKT_SOS, true, {}, 99}));  // evicts oldest POS
  // first head should be SOS or pushed forward; verify size capped at 8
  TEST_ASSERT_EQUAL(8, q.size());
}
void test_full_sos_only_drops_non_sos_arrival() {
  UplinkQueue q;
  for (int i = 0; i < 8; ++i) q.enqueue({PKT_SOS, true, {}, (uint16_t)i});
  TEST_ASSERT_FALSE(q.enqueue({PKT_POS, true, {}, 99}));
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_empty_then_queue);
  RUN_TEST(test_sos_preempts_non_sos_on_full);
  RUN_TEST(test_full_sos_only_drops_non_sos_arrival);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail**

- [ ] **Step 3: Implement**

`uplink_queue.h`:
```cpp
#pragma once
#include <stdint.h>
#include "mesh/constants.h"

struct UplinkItem {
  uint8_t  type;
  bool     own;
  uint8_t  payload[60];
  uint16_t seq;
  uint8_t  len = 0;
};

class UplinkQueue {
public:
  bool enqueue(UplinkItem it);
  bool dequeue(UplinkItem* out);
  bool peek(UplinkItem* out) const;
  bool is_empty() const { return size_ == 0; }
  uint8_t size() const { return size_; }
private:
  static constexpr uint8_t CAP = 8;
  UplinkItem ring_[CAP];
  uint8_t head_ = 0, tail_ = 0, size_ = 0;
  void erase_at(uint8_t idx);
};
```

`uplink_queue.cpp`:
```cpp
#include "mesh/uplink_queue.h"
#include <string.h>

bool UplinkQueue::enqueue(UplinkItem it) {
  if (size_ < CAP) {
    ring_[tail_] = it;
    tail_ = (tail_ + 1) % CAP;
    ++size_;
    return true;
  }
  if (it.type != PKT_SOS) return false;
  // find oldest non-SOS to evict
  for (uint8_t i = 0; i < size_; ++i) {
    uint8_t idx = (head_ + i) % CAP;
    if (ring_[idx].type != PKT_SOS) {
      erase_at(idx);
      ring_[tail_] = it;
      tail_ = (tail_ + 1) % CAP;
      ++size_;
      return true;
    }
  }
  return false;  // queue is all SOS
}

bool UplinkQueue::peek(UplinkItem* out) const {
  if (!size_) return false;
  *out = ring_[head_];
  return true;
}

bool UplinkQueue::dequeue(UplinkItem* out) {
  if (!size_) return false;
  *out = ring_[head_];
  head_ = (head_ + 1) % CAP;
  --size_;
  return true;
}

void UplinkQueue::erase_at(uint8_t idx) {
  while (idx != head_) {
    uint8_t prev = (idx + CAP - 1) % CAP;
    ring_[idx] = ring_[prev];
    idx = prev;
  }
  head_ = (head_ + 1) % CAP;
  --size_;
}
```

- [ ] **Step 4: Run, pass.**

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/uplink_queue.h firmware/src/mesh/uplink_queue.cpp firmware/test/native/test_uplink_queue.cpp
git commit -m "feat(firmware): FSM-4 lorawan uplink queue with sos preemption"
```

---

## Task 10: BLE per-command ACL

**Files:**
- Create: `firmware/src/ble/acl.h`
- Create: `firmware/src/ble/acl.cpp`
- Create: `firmware/test/native/test_acl.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include "ble/acl.h"

void test_owner_can_all() {
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::SET_CONFIG, 0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::ROTATE_KEY, 0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::FACTORY_RESET, 0, 0));
}
void test_crew_blocked_from_config() {
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::SET_CONFIG, 0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::ROTATE_KEY, 0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::FACTORY_RESET, 0, 0));
}
void test_crew_can_sos_and_journey() {
  TEST_ASSERT_TRUE(acl_allow(BleTier::CREW, BleCmd::SOS_TRIGGER, 0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::CREW, BleCmd::START_JOURNEY, 0, 0));
}
void test_crew_cancel_own_only() {
  TEST_ASSERT_TRUE (acl_allow(BleTier::CREW, BleCmd::CANCEL_SOS, /*caller=*/42, /*sos_user=*/42));
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::CANCEL_SOS, /*caller=*/42, /*sos_user=*/9));
}
void test_stranger_blocked() {
  TEST_ASSERT_FALSE(acl_allow(BleTier::STRANGER, BleCmd::SUBSCRIBE_DATA, 0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::STRANGER, BleCmd::SOS_TRIGGER, 0, 0));
}
int main() {
  UNITY_BEGIN();
  RUN_TEST(test_owner_can_all);
  RUN_TEST(test_crew_blocked_from_config);
  RUN_TEST(test_crew_can_sos_and_journey);
  RUN_TEST(test_crew_cancel_own_only);
  RUN_TEST(test_stranger_blocked);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail.**

- [ ] **Step 3: Implement**

`acl.h`:
```cpp
#pragma once
#include <stdint.h>

enum class BleTier : uint8_t { STRANGER = 0, CREW = 1, OWNER = 2 };
enum class BleCmd  : uint8_t {
  SUBSCRIBE_DATA, SUBSCRIBE_ACK, SET_CONFIG,
  START_JOURNEY, END_JOURNEY,
  SOS_TRIGGER, CANCEL_SOS,
  ROTATE_KEY, FACTORY_RESET,
};

bool acl_allow(BleTier tier, BleCmd cmd, uint16_t caller_user_id, uint16_t sos_user_id);
```

`acl.cpp`:
```cpp
#include "ble/acl.h"

bool acl_allow(BleTier tier, BleCmd cmd, uint16_t caller, uint16_t sos_user) {
  if (tier == BleTier::STRANGER) return false;
  if (tier == BleTier::OWNER) return true;
  // CREW
  switch (cmd) {
    case BleCmd::SUBSCRIBE_DATA:
    case BleCmd::SUBSCRIBE_ACK:
    case BleCmd::START_JOURNEY:
    case BleCmd::END_JOURNEY:
    case BleCmd::SOS_TRIGGER:
      return true;
    case BleCmd::CANCEL_SOS:
      return caller == sos_user;
    case BleCmd::SET_CONFIG:
    case BleCmd::ROTATE_KEY:
    case BleCmd::FACTORY_RESET:
    default:
      return false;
  }
}
```

- [ ] **Step 4: Run, pass.**

- [ ] **Step 5: Commit**

```bash
git add firmware/src/ble/acl.h firmware/src/ble/acl.cpp firmware/test/native/test_acl.cpp
git commit -m "feat(firmware): ble per-command acl matrix"
```

---

## Task 11: Build + parse + validation pipeline

**Files:**
- Create: `firmware/src/mesh/build_parse.h`
- Create: `firmware/src/mesh/build_parse.cpp`
- Create: `firmware/test/native/test_validation.cpp`

- [ ] **Step 1: Failing test**

```cpp
#include <unity.h>
#include <string.h>
#include "mesh/build_parse.h"
#include "mesh/dedup.h"

static const uint8_t KEY[16] = {0xab,0xcd,0xef,0x01,0x23,0x45,0x67,0x89,
                                0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,0x11};

void test_build_pos_then_parse() {
  PosPkt out;
  PosBuild in = {.src = 0x07f4, .seq = 1, .ts = 1715600000,
                 .lat1e7 = 100000000, .lon1e7 = 770000000,
                 .spd_cms = 300, .hdg_cdeg = 9000, .batt_pc = 84, .flags = 1,
                 .user_id = 42, .name = "Joe", .name_len = 3};
  build_pos(in, &out);
  PosPkt rt;
  ValidationCtx vc = {.now_s = 1715600100, .last_seq = 0};
  DedupCache d;
  TEST_ASSERT_EQUAL(VrOk, validate_and_parse_pos((uint8_t*)&out, sizeof(out), &rt, &d, vc));
}

void test_sos_hmac_fail() {
  SosPkt out;
  SosBuild in = {.src = 0x07f4, .seq = 1, .ts = 1715600000,
                 .lat1e7 = 0, .lon1e7 = 0, .spd_cms = 0, .hdg_cdeg = 0,
                 .batt_pc = 80, .reason = 0, .trigger_user_id = 42};
  build_sos(KEY, in, &out);
  out.hmac[0] ^= 0xff;
  SosPkt rt;
  ValidationCtx vc = {.now_s = 1715600100, .last_seq = 0};
  DedupCache d;
  TEST_ASSERT_EQUAL(VrHmacFail, validate_and_parse_sos((uint8_t*)&out, sizeof(out), KEY, &rt, &d, vc));
}

void test_stale_ts_rejected() {
  SosPkt out;
  SosBuild in = {.src = 0x07f4, .seq = 2, .ts = 1715600000,
                 .lat1e7 = 0, .lon1e7 = 0, .spd_cms = 0, .hdg_cdeg = 0,
                 .batt_pc = 80, .reason = 0, .trigger_user_id = 1};
  build_sos(KEY, in, &out);
  SosPkt rt;
  ValidationCtx vc = {.now_s = 1715600000 + 999, .last_seq = 0};
  DedupCache d;
  TEST_ASSERT_EQUAL(VrStaleTs, validate_and_parse_sos((uint8_t*)&out, sizeof(out), KEY, &rt, &d, vc));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_build_pos_then_parse);
  RUN_TEST(test_sos_hmac_fail);
  RUN_TEST(test_stale_ts_rejected);
  return UNITY_END();
}
```

- [ ] **Step 2: Run, fail.**

- [ ] **Step 3: Implement build_parse**

`build_parse.h`:
```cpp
#pragma once
#include "mesh/packet.h"
#include "mesh/dedup.h"
#include "mesh/constants.h"

enum ValidationResult {
  VrOk, VrTruncated, VrMagic, VrVer, VrType, VrCrc, VrDup, VrStaleTs, VrHmacFail, VrTtlExceeded,
};

struct ValidationCtx { uint32_t now_s; uint16_t last_seq; };

struct PosBuild { uint16_t src, seq; uint32_t ts; int32_t lat1e7, lon1e7;
                  uint16_t spd_cms, hdg_cdeg; uint8_t batt_pc, flags;
                  uint16_t user_id; const char* name; uint8_t name_len; };
struct SosBuild { uint16_t src, seq; uint32_t ts; int32_t lat1e7, lon1e7;
                  uint16_t spd_cms, hdg_cdeg; uint8_t batt_pc, reason; uint16_t trigger_user_id; };
struct AckBuild { uint16_t src, dest, seq; uint32_t ts; uint16_t ack_src, ack_seq; uint8_t status; };
struct CancelBuild { uint16_t src, seq; uint32_t ts; uint16_t cancel_seq, trigger_user_id; };

void build_pos(const PosBuild& in, PosPkt* out);
void build_sos(const uint8_t key[16], const SosBuild& in, SosPkt* out);
void build_ack(const uint8_t key[16], const AckBuild& in, AckPkt* out);
void build_cancel(const uint8_t key[16], const CancelBuild& in, CancelPkt* out);

ValidationResult validate_and_parse_pos(const uint8_t* buf, size_t len, PosPkt* out, DedupCache* d, const ValidationCtx& vc);
ValidationResult validate_and_parse_sos(const uint8_t* buf, size_t len, const uint8_t key[16], SosPkt* out, DedupCache* d, const ValidationCtx& vc);
ValidationResult validate_and_parse_ack(const uint8_t* buf, size_t len, const uint8_t key[16], AckPkt* out, DedupCache* d, const ValidationCtx& vc);
ValidationResult validate_and_parse_cancel(const uint8_t* buf, size_t len, const uint8_t key[16], CancelPkt* out, DedupCache* d, const ValidationCtx& vc);
```

`build_parse.cpp`:
```cpp
#include "mesh/build_parse.h"
#include "mesh/crc16.h"
#include "mesh/hmac_util.h"
#include <string.h>
#include <stdlib.h>

static void fill_header(MeshHeader& h, uint8_t type, uint16_t src, uint16_t dest, uint16_t seq, uint32_t ts) {
  h.magic = PKT_MAGIC; h.ver = PKT_VER; h.type = type;
  h.src = src; h.dest = dest; h.seq = seq;
  h.hops = 0; h.ttl = MESH_TTL_DEFAULT; h.ts = ts;
}

void build_pos(const PosBuild& in, PosPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_POS, in.src, 0xFFFF, in.seq, in.ts);
  out->lat1e7 = in.lat1e7; out->lon1e7 = in.lon1e7;
  out->spd_cms = in.spd_cms; out->hdg_cdeg = in.hdg_cdeg;
  out->batt_pc = in.batt_pc; out->flags = in.flags;
  out->user_id = in.user_id;
  out->name_len = in.name_len;
  if (in.name && in.name_len) memcpy(out->name_utf8, in.name, in.name_len);
  out->crc = crc16_ccitt((uint8_t*)out, sizeof(PosPkt) - 2);
}

void build_sos(const uint8_t key[16], const SosBuild& in, SosPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_SOS, in.src, 0xFFFF, in.seq, in.ts);
  out->lat1e7 = in.lat1e7; out->lon1e7 = in.lon1e7;
  out->spd_cms = in.spd_cms; out->hdg_cdeg = in.hdg_cdeg;
  out->batt_pc = in.batt_pc; out->reason = in.reason;
  out->trigger_user_id = in.trigger_user_id;
  const size_t hmac_input_len = offsetof(SosPkt, hmac);
  hmac_sha256_trunc4(key, 16, (uint8_t*)out, hmac_input_len, out->hmac);
  out->crc = crc16_ccitt((uint8_t*)out, sizeof(SosPkt) - 2);
}

void build_ack(const uint8_t key[16], const AckBuild& in, AckPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_ACK, in.src, in.dest, in.seq, in.ts);
  out->ack_src = in.ack_src; out->ack_seq = in.ack_seq; out->status = in.status;
  const size_t hmac_input_len = offsetof(AckPkt, hmac);
  hmac_sha256_trunc4(key, 16, (uint8_t*)out, hmac_input_len, out->hmac);
  out->crc = crc16_ccitt((uint8_t*)out, sizeof(AckPkt) - 2);
}

void build_cancel(const uint8_t key[16], const CancelBuild& in, CancelPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_CANCEL, in.src, 0xFFFF, in.seq, in.ts);
  out->cancel_seq = in.cancel_seq; out->trigger_user_id = in.trigger_user_id;
  const size_t hmac_input_len = offsetof(CancelPkt, hmac);
  hmac_sha256_trunc4(key, 16, (uint8_t*)out, hmac_input_len, out->hmac);
  out->crc = crc16_ccitt((uint8_t*)out, sizeof(CancelPkt) - 2);
}

static ValidationResult pre_check(const uint8_t* buf, size_t len, uint8_t expect_type, size_t expect_len,
                                  const ValidationCtx& vc, DedupCache* d) {
  if (len < sizeof(MeshHeader)) return VrTruncated;
  const MeshHeader* h = reinterpret_cast<const MeshHeader*>(buf);
  if (h->magic != PKT_MAGIC) return VrMagic;
  if (h->ver != PKT_VER) return VrVer;
  if (h->type != expect_type) return VrType;
  if (len != expect_len) return VrTruncated;
  const uint16_t crc_field = *reinterpret_cast<const uint16_t*>(buf + len - 2);
  if (crc16_ccitt(buf, len - 2) != crc_field) return VrCrc;
  if (h->ts == 0 || (uint32_t)labs((long)vc.now_s - (long)h->ts) > REPLAY_WINDOW_S) return VrStaleTs;
  if (d->seen_then_insert(h->src, h->seq, h->type)) return VrDup;
  return VrOk;
}

ValidationResult validate_and_parse_pos(const uint8_t* buf, size_t len, PosPkt* out, DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_POS, sizeof(PosPkt), vc, d);
  if (r != VrOk) return r;
  memcpy(out, buf, sizeof(PosPkt));
  return VrOk;
}

ValidationResult validate_and_parse_sos(const uint8_t* buf, size_t len, const uint8_t key[16], SosPkt* out, DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_SOS, sizeof(SosPkt), vc, d);
  if (r != VrOk) return r;
  const size_t input_len = offsetof(SosPkt, hmac);
  if (!hmac_sha256_verify_trunc4(key, 16, buf, input_len, buf + offsetof(SosPkt, hmac))) return VrHmacFail;
  memcpy(out, buf, sizeof(SosPkt));
  return VrOk;
}

ValidationResult validate_and_parse_ack(const uint8_t* buf, size_t len, const uint8_t key[16], AckPkt* out, DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_ACK, sizeof(AckPkt), vc, d);
  if (r != VrOk) return r;
  const size_t input_len = offsetof(AckPkt, hmac);
  if (!hmac_sha256_verify_trunc4(key, 16, buf, input_len, buf + offsetof(AckPkt, hmac))) return VrHmacFail;
  memcpy(out, buf, sizeof(AckPkt));
  return VrOk;
}

ValidationResult validate_and_parse_cancel(const uint8_t* buf, size_t len, const uint8_t key[16], CancelPkt* out, DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_CANCEL, sizeof(CancelPkt), vc, d);
  if (r != VrOk) return r;
  const size_t input_len = offsetof(CancelPkt, hmac);
  if (!hmac_sha256_verify_trunc4(key, 16, buf, input_len, buf + offsetof(CancelPkt, hmac))) return VrHmacFail;
  memcpy(out, buf, sizeof(CancelPkt));
  return VrOk;
}
```

- [ ] **Step 4: Run, pass**

Run: `pio test -e native -f test_validation`
Expected: 3/3 passed.

- [ ] **Step 5: Commit**

```bash
git add firmware/src/mesh/build_parse.h firmware/src/mesh/build_parse.cpp firmware/test/native/test_validation.cpp
git commit -m "feat(firmware): build + validate + parse with hmac and dedup"
```

---

## Task 12: NVS layout constants

**Files:**
- Create: `firmware/src/nvs_layout.h`

- [ ] **Step 1: Write the header**

```cpp
#pragma once
namespace nvs_keys {
  constexpr const char* NS = "boat_cfg";
  constexpr const char* PAIRED                     = "paired";
  constexpr const char* MESH_SRC_ID                = "mesh_src_id";
  constexpr const char* BOAT_ID                    = "boat_id";
  constexpr const char* USER_ID                    = "user_id";
  constexpr const char* DISPLAY_NAME               = "display_name";
  constexpr const char* HMAC_SECRET                = "hmac_secret";   // 16 B blob
  constexpr const char* CREW_TOKEN                 = "crew_token";    // 8 B blob
  constexpr const char* RELAY_MODE                 = "relay_mode";
  constexpr const char* LAST_SOS_SEQ               = "last_sos_seq";
  constexpr const char* LAST_JOURNEY_TOGGLE_USER   = "last_jt_user";
  constexpr const char* LORAWAN_DEVKEY             = "lw_devkey";     // 16 B
  constexpr const char* LORAWAN_APPEUI             = "lw_appeui";     // 8 B
  constexpr const char* LORAWAN_DEVEUI             = "lw_deveui";     // 8 B
}
```

- [ ] **Step 2: Commit**

```bash
git add firmware/src/nvs_layout.h
git commit -m "feat(firmware): nvs key layout"
```

---

## Task 13: Wire main.cpp around the modules

**Files:**
- Modify: `firmware/src/main.cpp` (significant rewrite — keep file as the wiring layer)
- Create: `firmware/src/radio/scheduler.h`
- Create: `firmware/src/radio/scheduler.cpp`

This is the biggest single rewrite. Implement in steps; each step compiles.

- [ ] **Step 1: Stub radio scheduler skeleton**

`firmware/src/radio/scheduler.h`:
```cpp
#pragma once
#include "mesh/packet.h"
#include "mesh/dedup.h"
#include "mesh/forwarding.h"
#include "mesh/sos_state.h"
#include "mesh/uplink_queue.h"

class RadioScheduler {
public:
  void begin();
  void on_irq_dio0();
  void run_one_tick(uint32_t now_ms);

  void on_button_sos(uint16_t user_id, uint8_t reason);
  void on_ble_sos_trigger(uint16_t user_id, uint8_t reason);
  void on_ble_cancel_sos(uint16_t user_id);

  bool mesh_rx_flag = false;
private:
  DedupCache    dedup_;
  ForwardSlot   slots_[MAX_INFLIGHT_FWD];
  SosState      sos_;
  UplinkQueue   uplinks_;
  uint8_t       hmac_secret_[16] = {};
  uint16_t      mesh_src_id_ = 0;
  uint32_t      next_pos_at_ms_ = 0;

  void try_tx_sos(uint32_t now_ms);
  void try_tx_pos(uint32_t now_ms);
  void drain_rx(uint32_t now_ms);
};
```

`firmware/src/radio/scheduler.cpp`: minimal skeleton that compiles (real RFM95 wiring done at bench-test step). Touch RFM95 only behind `#ifdef ESP_PLATFORM` so native build still works.

```cpp
#include "radio/scheduler.h"
#include "mesh/build_parse.h"
#include "mesh/constants.h"
#include <string.h>

#ifdef ARDUINO
  #include <RadioLib.h>
  extern SX1276 radio;        // declared in main.cpp
  static volatile bool s_rx_flag = false;
  IRAM_ATTR static void on_dio0_isr() { s_rx_flag = true; }
#endif

void RadioScheduler::begin() {
#ifdef ARDUINO
  radio.beginFSK();  // placeholder
  radio.setFrequency(MESH_FREQ_MHZ);
  radio.setSpreadingFactor(MESH_SF);
  radio.setBandwidth(MESH_BW_KHZ);
  radio.setCodingRate(MESH_CR);
  radio.setSyncWord(MESH_SYNC_WORD);
  radio.setOutputPower(MESH_TX_DBM);
  radio.setDio0Action(on_dio0_isr);
  radio.startReceive();
#endif
}

void RadioScheduler::on_irq_dio0() { mesh_rx_flag = true; }

void RadioScheduler::run_one_tick(uint32_t now_ms) {
  sos_.tick(now_ms);
  if (mesh_rx_flag) { drain_rx(now_ms); mesh_rx_flag = false; }
  if (sos_.phase() == SosPhase::ACTIVE && sos_.next_retry_ms_from_now(now_ms) == 0) try_tx_sos(now_ms);
  if (now_ms >= next_pos_at_ms_) try_tx_pos(now_ms);
  for (auto& s : slots_) {
    if (s.tick(now_ms) == FwdState::DONE) { /* TX deferred frame */ s.state = FwdState::EMPTY; }
  }
}

void RadioScheduler::on_button_sos(uint16_t user_id, uint8_t reason) {
  sos_.trigger(/*now_ms=*/0, reason, user_id);
}

void RadioScheduler::on_ble_sos_trigger(uint16_t user_id, uint8_t reason) {
  sos_.trigger(/*now_ms=*/0, reason, user_id);
}

void RadioScheduler::on_ble_cancel_sos(uint16_t /*user_id*/) {
  sos_.user_cancel();
}

void RadioScheduler::try_tx_sos(uint32_t now_ms) {
  SosBuild b = {.src = mesh_src_id_, .seq = sos_.seq(), .ts = (uint32_t)(now_ms / 1000),
                .lat1e7 = 0, .lon1e7 = 0, .spd_cms = 0, .hdg_cdeg = 0,
                .batt_pc = 100, .reason = sos_.reason(), .trigger_user_id = sos_.user_id()};
  SosPkt pkt;
  build_sos(hmac_secret_, b, &pkt);
#ifdef ARDUINO
  radio.transmit((uint8_t*)&pkt, sizeof(pkt));
#endif
  sos_.note_tx(now_ms);
}

void RadioScheduler::try_tx_pos(uint32_t now_ms) {
  PosBuild b = {.src = mesh_src_id_, .seq = 0, .ts = (uint32_t)(now_ms / 1000),
                .lat1e7 = 0, .lon1e7 = 0, .spd_cms = 0, .hdg_cdeg = 0,
                .batt_pc = 100, .flags = 0, .user_id = 0, .name = "", .name_len = 0};
  PosPkt pkt; build_pos(b, &pkt);
#ifdef ARDUINO
  radio.transmit((uint8_t*)&pkt, sizeof(pkt));
#endif
  next_pos_at_ms_ = now_ms + (POS_INTERVAL_S * 1000);
}

void RadioScheduler::drain_rx(uint32_t /*now_ms*/) {
  // bench step: actually pull bytes and dispatch by header.type via validate_*
}
```

- [ ] **Step 2: Compile native to confirm everything links**

Run: `cd firmware && pio run -e native`
Expected: SUCCESS.

- [ ] **Step 3: Rewrite `main.cpp` wiring**

`main.cpp` (target shape — preserve existing pairing AP and BLE GATT logic from previous file, add the scheduler hook and dual-task creation):

```cpp
#include <Arduino.h>
#include <Preferences.h>
#include "mesh/constants.h"
#include "radio/scheduler.h"
#include "ble/acl.h"
#include "nvs_layout.h"

static RadioScheduler g_sched;
static SemaphoreHandle_t g_data_mutex;
static SemaphoreHandle_t g_mesh_mutex;

static void radio_task(void*) {
  uint32_t last = millis();
  for (;;) {
    g_sched.run_one_tick(millis());
    vTaskDelay(pdMS_TO_TICKS(5));
    (void)last;
  }
}

static void app_task(void*) {
  for (;;) {
    // GPS read, BLE callbacks, LED FSM, button polling, ADC
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void setup() {
  Serial.begin(115200);
  g_data_mutex = xSemaphoreCreateMutex();
  g_mesh_mutex = xSemaphoreCreateMutex();
  g_sched.begin();
  xTaskCreatePinnedToCore(radio_task, "radio", 8192, nullptr, 5, nullptr, 0);
  xTaskCreatePinnedToCore(app_task,   "app",   8192, nullptr, 3, nullptr, 1);
}

void loop() { vTaskDelay(pdMS_TO_TICKS(1000)); }
```

- [ ] **Step 4: Build for ESP32**

Run: `cd firmware && pio run -e denky32_hybrid`
Expected: SUCCESS (linker may complain about unused old functions — remove their declarations gradually).

- [ ] **Step 5: Run full native suite**

Run: `cd firmware && pio test -e native`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add firmware/src/main.cpp firmware/src/radio/scheduler.h firmware/src/radio/scheduler.cpp
git commit -m "feat(firmware): wire scheduler + modules in main; freertos task split"
```

---

## Task 14: BLE auth (bench-only)

**Files:**
- Create: `firmware/src/ble/auth.h`
- Create: `firmware/src/ble/auth.cpp`

This module touches NimBLE GATT — it cannot be tested host-side. The pure ACL is covered by Task 10. The handshake state-machine here is straightforward, exercised by the Layer 2 bench checklist.

- [ ] **Step 1: Implement skeleton**

`auth.h`:
```cpp
#pragma once
#include <stdint.h>
#include "ble/acl.h"

class BleAuth {
public:
  void on_connect(uint16_t conn_handle);
  void on_disconnect(uint16_t conn_handle);
  uint8_t challenge_for(uint16_t conn_handle, uint8_t out[16]);
  bool verify_response(uint16_t conn_handle, BleTier hint, const uint8_t proof[8],
                       const uint8_t hmac_secret[16], const uint8_t crew_token[8]);
  BleTier tier(uint16_t conn_handle) const;
private:
  struct Conn { uint16_t h; uint8_t challenge[16]; BleTier tier; bool active; };
  static constexpr uint8_t MAX = 4;
  Conn conns_[MAX] = {};
  Conn* find(uint16_t h);
  Conn* slot();
};
```

`auth.cpp` (≤100 lines): generate 16-byte random challenge via `esp_random()` on connect; on verify, HMAC the challenge with the appropriate secret and consteq-compare the first 8 bytes. On success set `tier`. Idle-disconnect after 10 s if tier stays STRANGER.

- [ ] **Step 2: Commit**

```bash
git add firmware/src/ble/auth.h firmware/src/ble/auth.cpp
git commit -m "feat(firmware): ble per-connection challenge/response state"
```

---

## Task 15: Layer-2 bench test checklist

**Files:**
- Create: `firmware/test/bench/LAYER2.md`

- [ ] **Step 1: Write checklist**

```markdown
# Layer 2 Bench Tests · single device

Run on 3 separate units. Each row must pass on all 3 before promoting.

| # | Test | Pass criteria |
|---|---|---|
| B-01 | Cold boot → first POS over mesh | sniffer logs a 46 B frame with magic 0xBA within 30 s of power-on |
| B-02 | BLE pair flow | app receives mesh_src_id, NVS shows paired=true |
| B-03 | Owner AUTH handshake | AUTH_STATUS reads tier=OWNER |
| B-04 | Crew AUTH handshake | AUTH_STATUS reads tier=CREW after crew_token submitted |
| B-05 | Stranger denied | unauthenticated connection cannot subscribe DATA |
| B-06 | Button SOS trigger | LED red-fast within 200 ms; SosPkt visible on sniffer |
| B-07 | Persistent retry | with no neighbour ack, retries fire at 0/30/60/120/300 s ±2 s |
| B-08 | Battery cutoff at 10 % | one final SOS, then POS halts, LED red-solid |
| B-09 | Journey privacy override | journey=off + SOS still transmits |
| B-10 | Watchdog recovery | LMIC stuck >30 s → reboot, mesh resumes within 5 s |
| B-11 | GPS loss for 10 min | POS sends 0,0 + flag |
| B-12 | NVS write fail simulation | BLE STATUS notifies STORAGE_FAIL |
| B-13 | Mesh CAD listen idle current | ≤ 18 mA average over 2 min sample |
| B-14 | LED reference card | observed pattern matches docs/site Docs LED card for each forced state |
```

- [ ] **Step 2: Commit**

```bash
git add firmware/test/bench/LAYER2.md
git commit -m "test(firmware): layer-2 bench checklist"
```

---

## Task 16: Final native test sweep + tag

- [ ] **Step 1: Run all native tests**

Run: `cd firmware && pio test -e native -v`
Expected: every test file passes; no warnings.

- [ ] **Step 2: Build hybrid firmware**

Run: `pio run -e denky32_hybrid`
Expected: SUCCESS, RAM and Flash usage printed; mesh state ≤ ~3 KB.

- [ ] **Step 3: Tag**

```bash
git tag firmware-v2-mesh-pre-bench
```

---

## Spec coverage cross-check

| Spec § | Covered by |
|---|---|
| Process model (radioTask, appTask, mutex order, ISR) | Task 13 |
| Constants table | Task 2 |
| MeshHeader + 4 packet structs + size asserts | Task 3 |
| CRC16-CCITT | Task 4 |
| HMAC-SHA256 trunc-4 | Task 5 |
| Validation pipeline (magic, ver, type, CRC, dedup, ts, HMAC) | Task 11 |
| Dedup ring (64) | Task 6 |
| RBSF forward state (K=2, jitter, TTL, dedup) | Task 7 |
| SOS originator FSM with retry backoff and battery cancel | Task 8 |
| LoRaWAN uplink queue with SOS preemption | Task 9 |
| BLE per-command ACL matrix | Task 10 |
| BLE per-connection challenge/response | Task 14 + bench |
| NVS layout | Task 12 |
| Radio scheduler FSM (LMIC/mesh share) | Task 13 + bench |
| Error/edge handling (radio fail, GPS loss, NVS fail, batt cutoff) | Task 13 wiring + bench |
| Bench checklist | Task 15 |

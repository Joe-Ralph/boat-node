#include <unity.h>
#include <string.h>
#include "mesh/build_parse.h"
#include "mesh/dedup.h"
#include "mesh/constants.h"

static const uint8_t KEY[16] = {
  0xab,0xcd,0xef,0x01,0x23,0x45,0x67,0x89,
  0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,0x11
};

void test_pos_build_then_validate_roundtrip() {
  PosPkt pkt;
  PosBuild in{};
  in.src = 0x07f4; in.seq = 1; in.ts = 1715600000;
  in.lat1e7 = 100000000; in.lon1e7 = 770000000;
  in.spd_cms = 300; in.hdg_cdeg = 9000;
  in.batt_pc = 84; in.flags = 1;
  in.user_id = 42;
  in.name = "Joe"; in.name_len = 3;
  build_pos(in, &pkt);

  DedupCache d;
  ValidationCtx vc{1715600100, 0};
  PosPkt rt;
  TEST_ASSERT_EQUAL(VrOk,
    validate_and_parse_pos(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt), &rt, &d, vc));
  TEST_ASSERT_EQUAL(0x07f4, rt.hdr.src);
  TEST_ASSERT_EQUAL_INT32(100000000, rt.lat1e7);
}

void test_pos_dedup_rejects_repeat() {
  PosPkt pkt;
  PosBuild in{};
  in.src = 0x0007; in.seq = 7; in.ts = 1715600000;
  build_pos(in, &pkt);

  DedupCache d;
  ValidationCtx vc{1715600100, 0};
  PosPkt rt;
  TEST_ASSERT_EQUAL(VrOk,
    validate_and_parse_pos(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt), &rt, &d, vc));
  TEST_ASSERT_EQUAL(VrDup,
    validate_and_parse_pos(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt), &rt, &d, vc));
}

void test_sos_hmac_fail() {
  SosPkt pkt;
  SosBuild in{};
  in.src = 0x07f4; in.seq = 1; in.ts = 1715600000;
  in.batt_pc = 80; in.reason = 0; in.trigger_user_id = 42;
  build_sos(KEY, in, &pkt);
  pkt.hmac[0] ^= 0xFF;
  // Re-compute CRC so we exercise HMAC path, not CRC path.
  // We need to flip CRC too since hmac is inside the CRC range.
  // Easiest: recompute CRC on the tampered frame.
  pkt.crc = 0;     // force recompute
  uint16_t crc = 0xFFFF;
  const uint8_t* p = reinterpret_cast<uint8_t*>(&pkt);
  for (size_t i = 0; i < sizeof(pkt) - 2; ++i) {
    crc ^= static_cast<uint16_t>(p[i]) << 8;
    for (int j = 0; j < 8; ++j) crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : (crc << 1);
  }
  pkt.crc = crc;

  DedupCache d;
  ValidationCtx vc{1715600100, 0};
  SosPkt rt;
  TEST_ASSERT_EQUAL(VrHmacFail,
    validate_and_parse_sos(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt), KEY, &rt, &d, vc));
}

void test_stale_ts_rejected() {
  SosPkt pkt;
  SosBuild in{};
  in.src = 0x07f4; in.seq = 2; in.ts = 1715600000;
  in.trigger_user_id = 1;
  build_sos(KEY, in, &pkt);

  DedupCache d;
  ValidationCtx vc{1715600000 + 999, 0};   // far outside ±300 s
  SosPkt rt;
  TEST_ASSERT_EQUAL(VrStaleTs,
    validate_and_parse_sos(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt), KEY, &rt, &d, vc));
}

void test_magic_rejected() {
  PosPkt pkt;
  PosBuild in{};
  in.src = 0x0001; in.seq = 1; in.ts = 1715600000;
  build_pos(in, &pkt);
  pkt.hdr.magic = 0x00;

  DedupCache d;
  ValidationCtx vc{1715600100, 0};
  PosPkt rt;
  TEST_ASSERT_EQUAL(VrMagic,
    validate_and_parse_pos(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt), &rt, &d, vc));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_pos_build_then_validate_roundtrip);
  RUN_TEST(test_pos_dedup_rejects_repeat);
  RUN_TEST(test_sos_hmac_fail);
  RUN_TEST(test_stale_ts_rejected);
  RUN_TEST(test_magic_rejected);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

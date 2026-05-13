#include <unity.h>
#include <string.h>
#include "mesh/hmac_util.h"

// RFC 4231 test case 1:
//   key  = 20 * 0x0b
//   data = "Hi There"
//   HMAC-SHA256 = b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
// First 4 bytes: b0 34 4c 61.

void test_hmac_rfc4231_vec1() {
  const uint8_t key[20] = {0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,
                            0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,
                            0x0b,0x0b,0x0b,0x0b};
  const uint8_t data[] = {'H','i',' ','T','h','e','r','e'};
  const uint8_t expected_trunc[4] = {0xb0, 0x34, 0x4c, 0x61};
  uint8_t out[4] = {0};
  hmac_sha256_trunc4(key, sizeof(key), data, sizeof(data), out);
  TEST_ASSERT_EQUAL_MEMORY(expected_trunc, out, 4);
}

void test_hmac_full_32_byte() {
  const uint8_t key[20] = {0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,
                            0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,0x0b,
                            0x0b,0x0b,0x0b,0x0b};
  const uint8_t data[] = {'H','i',' ','T','h','e','r','e'};
  const uint8_t expected[32] = {
    0xb0,0x34,0x4c,0x61,0xd8,0xdb,0x38,0x53,
    0x5c,0xa8,0xaf,0xce,0xaf,0x0b,0xf1,0x2b,
    0x88,0x1d,0xc2,0x00,0xc9,0x83,0x3d,0xa7,
    0x26,0xe9,0x37,0x6c,0x2e,0x32,0xcf,0xf7
  };
  uint8_t out[32] = {0};
  hmac_sha256_full(key, sizeof(key), data, sizeof(data), out);
  TEST_ASSERT_EQUAL_MEMORY(expected, out, 32);
}

void test_hmac_verify_match() {
  const uint8_t key[16] = {0xab,0xab,0xab,0xab,0xab,0xab,0xab,0xab,
                            0xab,0xab,0xab,0xab,0xab,0xab,0xab,0xab};
  const uint8_t data[] = {1, 2, 3, 4, 5};
  uint8_t tag[4];
  hmac_sha256_trunc4(key, sizeof(key), data, sizeof(data), tag);
  TEST_ASSERT_TRUE(hmac_sha256_verify_trunc4(key, sizeof(key), data, sizeof(data), tag));
}

void test_hmac_verify_tampered() {
  const uint8_t key[16] = {0xab,0xab,0xab,0xab,0xab,0xab,0xab,0xab,
                            0xab,0xab,0xab,0xab,0xab,0xab,0xab,0xab};
  const uint8_t data[] = {1, 2, 3, 4, 5};
  uint8_t tag[4];
  hmac_sha256_trunc4(key, sizeof(key), data, sizeof(data), tag);
  tag[0] ^= 0x01;
  TEST_ASSERT_FALSE(hmac_sha256_verify_trunc4(key, sizeof(key), data, sizeof(data), tag));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_hmac_rfc4231_vec1);
  RUN_TEST(test_hmac_full_32_byte);
  RUN_TEST(test_hmac_verify_match);
  RUN_TEST(test_hmac_verify_tampered);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

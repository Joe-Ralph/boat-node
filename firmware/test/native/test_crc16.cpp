#include <unity.h>
#include "mesh/crc16.h"

void test_crc16_fixture() {
  const uint8_t data[] = {'1','2','3','4','5','6','7','8','9'};
  TEST_ASSERT_EQUAL_HEX16(0x29B1, crc16_ccitt(data, sizeof(data)));
}

void test_crc16_empty() {
  TEST_ASSERT_EQUAL_HEX16(0xFFFF, crc16_ccitt(nullptr, 0));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_crc16_fixture);
  RUN_TEST(test_crc16_empty);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

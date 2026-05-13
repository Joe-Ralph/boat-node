#include <unity.h>
#include "mesh/packet.h"

void test_header_size() { TEST_ASSERT_EQUAL(15, sizeof(MeshHeader)); }
void test_pos_size()    { TEST_ASSERT_EQUAL(46, sizeof(PosPkt)); }
void test_sos_size()    { TEST_ASSERT_EQUAL(37, sizeof(SosPkt)); }
void test_ack_size()    { TEST_ASSERT_EQUAL(27, sizeof(AckPkt)); }
void test_cancel_size() { TEST_ASSERT_EQUAL(25, sizeof(CancelPkt)); }

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_header_size);
  RUN_TEST(test_pos_size);
  RUN_TEST(test_sos_size);
  RUN_TEST(test_ack_size);
  RUN_TEST(test_cancel_size);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

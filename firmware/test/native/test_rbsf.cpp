#include <unity.h>
#include "mesh/forwarding.h"
#include "mesh/constants.h"

void test_pending_to_done() {
  ForwardSlot s;
  s.start(7, 1, PKT_POS, /*now_ms=*/100, /*jitter_ms=*/50, /*hops_after_fwd=*/1, /*ttl=*/4);
  TEST_ASSERT_EQUAL((int)FwdState::PENDING, (int)s.tick(110));
  TEST_ASSERT_EQUAL((int)FwdState::DONE,    (int)s.tick(160));
}

void test_pending_to_suppressed_at_k() {
  ForwardSlot s;
  s.start(7, 1, PKT_POS, 100, 200, 1, 4);
  s.heard();
  s.heard();
  TEST_ASSERT_EQUAL((int)FwdState::SUPPRESSED, (int)s.tick(110));
}

void test_ttl_drops_immediately() {
  ForwardSlot s;
  s.start(7, 1, PKT_POS, 100, 50, /*hops_after_fwd=*/5, /*ttl=*/4);
  TEST_ASSERT_EQUAL((int)FwdState::DROP_TTL, (int)s.tick(101));
}

void test_matches_only_when_pending() {
  ForwardSlot s;
  TEST_ASSERT_FALSE(s.matches(7, 1, PKT_POS));
  s.start(7, 1, PKT_POS, 100, 200, 1, 4);
  TEST_ASSERT_TRUE(s.matches(7, 1, PKT_POS));
  TEST_ASSERT_FALSE(s.matches(7, 1, PKT_SOS));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_pending_to_done);
  RUN_TEST(test_pending_to_suppressed_at_k);
  RUN_TEST(test_ttl_drops_immediately);
  RUN_TEST(test_matches_only_when_pending);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

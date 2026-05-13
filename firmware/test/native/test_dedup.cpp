#include <unity.h>
#include "mesh/dedup.h"
#include "mesh/constants.h"

void test_first_insert_is_miss() {
  DedupCache d;
  TEST_ASSERT_FALSE(d.seen_then_insert(7, 1, PKT_POS));
}

void test_repeat_is_hit() {
  DedupCache d;
  d.seen_then_insert(7, 1, PKT_POS);
  TEST_ASSERT_TRUE(d.seen_then_insert(7, 1, PKT_POS));
}

void test_different_type_not_deduped() {
  DedupCache d;
  d.seen_then_insert(7, 1, PKT_POS);
  TEST_ASSERT_FALSE(d.seen_then_insert(7, 1, PKT_SOS));
}

void test_ring_evicts_oldest() {
  DedupCache d;
  for (uint16_t s = 0; s < DEDUP_CACHE_SIZE + 5; ++s) {
    d.seen_then_insert(1, s, PKT_POS);
  }
  // First five entries should have been evicted.
  TEST_ASSERT_FALSE(d.seen_then_insert(1, 0, PKT_POS));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_first_insert_is_miss);
  RUN_TEST(test_repeat_is_hit);
  RUN_TEST(test_different_type_not_deduped);
  RUN_TEST(test_ring_evicts_oldest);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

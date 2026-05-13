#include <unity.h>
#include "mesh/uplink_queue.h"
#include "mesh/constants.h"

static UplinkItem mk(uint8_t type, uint16_t seq) {
  UplinkItem it{};
  it.type = type;
  it.own  = true;
  it.seq  = seq;
  it.len  = 0;
  return it;
}

void test_empty_then_queue() {
  UplinkQueue q;
  TEST_ASSERT_TRUE(q.is_empty());
  TEST_ASSERT_TRUE(q.enqueue(mk(PKT_POS, 1)));
  TEST_ASSERT_FALSE(q.is_empty());
}

void test_sos_preempts_oldest_non_sos_when_full() {
  UplinkQueue q;
  for (int i = 0; i < 8; ++i) q.enqueue(mk(PKT_POS, (uint16_t)i));
  TEST_ASSERT_TRUE(q.enqueue(mk(PKT_SOS, 99)));
  TEST_ASSERT_EQUAL(8, q.size());
}

void test_full_sos_only_drops_non_sos_arrival() {
  UplinkQueue q;
  for (int i = 0; i < 8; ++i) q.enqueue(mk(PKT_SOS, (uint16_t)i));
  TEST_ASSERT_FALSE(q.enqueue(mk(PKT_POS, 99)));
  TEST_ASSERT_EQUAL(8, q.size());
}

void test_dequeue_fifo() {
  UplinkQueue q;
  q.enqueue(mk(PKT_POS, 1));
  q.enqueue(mk(PKT_POS, 2));
  UplinkItem out{};
  TEST_ASSERT_TRUE(q.dequeue(&out));
  TEST_ASSERT_EQUAL(1, out.seq);
  TEST_ASSERT_TRUE(q.dequeue(&out));
  TEST_ASSERT_EQUAL(2, out.seq);
  TEST_ASSERT_FALSE(q.dequeue(&out));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_empty_then_queue);
  RUN_TEST(test_sos_preempts_oldest_non_sos_when_full);
  RUN_TEST(test_full_sos_only_drops_non_sos_arrival);
  RUN_TEST(test_dequeue_fifo);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

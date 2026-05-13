#include <unity.h>
#include "mesh/sos_state.h"

void test_idle_to_active() {
  SosState s;
  s.trigger(0, /*reason=*/0, /*user_id=*/42);
  TEST_ASSERT_EQUAL((int)SosPhase::ACTIVE, (int)s.phase());
  TEST_ASSERT_EQUAL(0u, s.next_retry_ms_from_now(0));   // first attempt immediate
}

void test_retry_schedule() {
  SosState s;
  s.trigger(0, 0, 1);
  s.note_tx(0);                                          // retry_idx -> 1 (30s)
  TEST_ASSERT_EQUAL(30000u, s.next_retry_ms_from_now(0));
  s.note_tx(30000);                                      // retry_idx -> 2 (60s)
  TEST_ASSERT_EQUAL(60000u, s.next_retry_ms_from_now(30000));
}

void test_acked_clears_to_acked() {
  SosState s;
  s.trigger(0, 0, 1);
  s.note_tx(0);
  s.on_ack(s.seq(), /*status=*/0);
  TEST_ASSERT_EQUAL((int)SosPhase::ACKED, (int)s.phase());
}

void test_low_battery_cancels() {
  SosState s;
  s.trigger(0, 0, 1);
  s.battery_check(8);
  TEST_ASSERT_EQUAL((int)SosPhase::CANCELED, (int)s.phase());
}

void test_user_cancel_from_active() {
  SosState s;
  s.trigger(0, 0, 1);
  s.user_cancel();
  TEST_ASSERT_EQUAL((int)SosPhase::CANCELED, (int)s.phase());
}

void test_seq_persists_across_sessions() {
  SosState s;
  s.seed_from_nvs(42);
  s.trigger(0, 0, 1);
  TEST_ASSERT_EQUAL(43, s.seq());
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_idle_to_active);
  RUN_TEST(test_retry_schedule);
  RUN_TEST(test_acked_clears_to_acked);
  RUN_TEST(test_low_battery_cancels);
  RUN_TEST(test_user_cancel_from_active);
  RUN_TEST(test_seq_persists_across_sessions);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

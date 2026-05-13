#include <unity.h>
#include "ble/acl.h"

void test_owner_allowed_everywhere() {
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::SET_CONFIG,    0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::ROTATE_KEY,    0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::FACTORY_RESET, 0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::OWNER, BleCmd::SOS_TRIGGER,   0, 0));
}

void test_crew_blocked_from_config() {
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::SET_CONFIG,    0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::ROTATE_KEY,    0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::FACTORY_RESET, 0, 0));
}

void test_crew_allowed_for_sos_and_journey() {
  TEST_ASSERT_TRUE(acl_allow(BleTier::CREW, BleCmd::SOS_TRIGGER,   0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::CREW, BleCmd::START_JOURNEY, 0, 0));
  TEST_ASSERT_TRUE(acl_allow(BleTier::CREW, BleCmd::END_JOURNEY,   0, 0));
}

void test_crew_cancel_own_only() {
  TEST_ASSERT_TRUE (acl_allow(BleTier::CREW, BleCmd::CANCEL_SOS, /*caller=*/42, /*sos_user=*/42));
  TEST_ASSERT_FALSE(acl_allow(BleTier::CREW, BleCmd::CANCEL_SOS, /*caller=*/42, /*sos_user=*/9));
}

void test_stranger_denied_all() {
  TEST_ASSERT_FALSE(acl_allow(BleTier::STRANGER, BleCmd::SUBSCRIBE_DATA, 0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::STRANGER, BleCmd::SOS_TRIGGER,    0, 0));
  TEST_ASSERT_FALSE(acl_allow(BleTier::STRANGER, BleCmd::SET_CONFIG,     0, 0));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_owner_allowed_everywhere);
  RUN_TEST(test_crew_blocked_from_config);
  RUN_TEST(test_crew_allowed_for_sos_and_journey);
  RUN_TEST(test_crew_cancel_own_only);
  RUN_TEST(test_stranger_denied_all);
  return UNITY_END();
}

void setUp() {}
void tearDown() {}

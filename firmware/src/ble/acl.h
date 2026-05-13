#pragma once
#include <stdint.h>

// BLE per-command Access Control List.
// Pure function: state lives in the caller's connection table.

enum class BleTier : uint8_t {
  STRANGER = 0,
  CREW     = 1,
  OWNER    = 2,
};

enum class BleCmd : uint8_t {
  SUBSCRIBE_DATA,
  SUBSCRIBE_ACK,
  SET_CONFIG,
  START_JOURNEY,
  END_JOURNEY,
  SOS_TRIGGER,
  CANCEL_SOS,
  ROTATE_KEY,
  FACTORY_RESET,
};

// caller_user_id and sos_user_id are only consulted for CREW + CANCEL_SOS,
// which is restricted to "own SOS only" by matching the two.
bool acl_allow(BleTier tier, BleCmd cmd,
               uint16_t caller_user_id, uint16_t sos_user_id);

#include "ble/acl.h"

bool acl_allow(BleTier tier, BleCmd cmd,
               uint16_t caller_user_id, uint16_t sos_user_id) {
  if (tier == BleTier::STRANGER) return false;
  if (tier == BleTier::OWNER)    return true;

  // CREW tier
  switch (cmd) {
    case BleCmd::SUBSCRIBE_DATA:
    case BleCmd::SUBSCRIBE_ACK:
    case BleCmd::START_JOURNEY:
    case BleCmd::END_JOURNEY:
    case BleCmd::SOS_TRIGGER:
      return true;
    case BleCmd::CANCEL_SOS:
      return caller_user_id == sos_user_id;
    case BleCmd::SET_CONFIG:
    case BleCmd::ROTATE_KEY:
    case BleCmd::FACTORY_RESET:
    default:
      return false;
  }
}

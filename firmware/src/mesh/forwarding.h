#pragma once
#include <stdint.h>
#include "mesh/constants.h"

// RBSF (Receiver-Based Suppression Flood) per-packet state.
// Each in-flight forward owns one slot. When K_SUPPRESS neighbours have been
// heard repeating the same (src, seq, type), the local node suppresses its
// own copy. Otherwise the jitter timer fires and the node forwards.

enum class FwdState : uint8_t {
  EMPTY,
  PENDING,
  SUPPRESSED,
  DONE,        // local TX should happen now; caller flips to EMPTY after radio queues it
  DROP_TTL,
};

struct ForwardSlot {
  uint16_t src = 0;
  uint16_t seq = 0;
  uint8_t  type = 0;
  uint32_t tx_at_ms = 0;
  uint8_t  heard_count = 0;
  uint8_t  next_hops = 0;
  uint8_t  ttl = 0;
  FwdState state = FwdState::EMPTY;

  void start(uint16_t src_, uint16_t seq_, uint8_t type_,
             uint32_t now_ms, uint32_t jitter_ms,
             uint8_t hops_after_fwd, uint8_t ttl_);

  void heard() { if (state == FwdState::PENDING && heard_count < 255) ++heard_count; }

  FwdState tick(uint32_t now_ms);

  bool matches(uint16_t src_, uint16_t seq_, uint8_t type_) const {
    return state == FwdState::PENDING && src == src_ && seq == seq_ && type == type_;
  }
};

#include "mesh/forwarding.h"

void ForwardSlot::start(uint16_t src_, uint16_t seq_, uint8_t type_,
                        uint32_t now_ms, uint32_t jitter_ms,
                        uint8_t hops_after_fwd, uint8_t ttl_) {
  src = src_;
  seq = seq_;
  type = type_;
  tx_at_ms = now_ms + jitter_ms;
  heard_count = 0;
  next_hops = hops_after_fwd;
  ttl = ttl_;
  state = (next_hops > ttl) ? FwdState::DROP_TTL : FwdState::PENDING;
}

FwdState ForwardSlot::tick(uint32_t now_ms) {
  if (state != FwdState::PENDING) return state;
  if (next_hops > ttl)              { state = FwdState::DROP_TTL;  return state; }
  if (heard_count >= K_SUPPRESS)    { state = FwdState::SUPPRESSED; return state; }
  if (now_ms >= tx_at_ms)           { state = FwdState::DONE;       return state; }
  return FwdState::PENDING;
}

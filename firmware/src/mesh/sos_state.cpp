#include "mesh/sos_state.h"

namespace {
constexpr uint32_t RETRY_MS[]  = { 0, 30000, 60000, 120000, 300000 };
constexpr uint8_t  RETRY_TAIL  = (sizeof(RETRY_MS) / sizeof(RETRY_MS[0])) - 1;
constexpr uint32_t ACK_HOLD_MS = 5u * 60u * 1000u;
}

void SosState::trigger(uint32_t now_ms, uint8_t reason, uint16_t user_id) {
  if (phase_ == SosPhase::ACTIVE) return;
  phase_ = SosPhase::ACTIVE;
  ++seq_;
  retry_idx_     = 0;
  first_tx_done_ = false;
  last_tx_ms_    = now_ms;
  reason_        = reason;
  user_id_       = user_id;
  acked_at_ms_   = 0;
}

void SosState::note_tx(uint32_t now_ms) {
  last_tx_ms_    = now_ms;
  first_tx_done_ = true;
  if (retry_idx_ < RETRY_TAIL) ++retry_idx_;
}

uint32_t SosState::next_retry_ms_from_now(uint32_t now_ms) const {
  if (phase_ != SosPhase::ACTIVE) return 0xFFFFFFFFu;
  if (!first_tx_done_) return 0;
  const uint32_t delay = RETRY_MS[retry_idx_];
  const uint32_t due   = last_tx_ms_ + delay;
  return (due > now_ms) ? (due - now_ms) : 0;
}

void SosState::on_ack(uint16_t ack_seq, uint8_t /*status*/) {
  if (phase_ != SosPhase::ACTIVE) return;
  if (ack_seq != seq_) return;
  phase_ = SosPhase::ACKED;
}

void SosState::user_cancel() {
  if (phase_ == SosPhase::ACTIVE || phase_ == SosPhase::ACKED) {
    phase_ = SosPhase::CANCELED;
  }
}

void SosState::battery_check(uint8_t pct) {
  if (phase_ == SosPhase::ACTIVE && pct < 10) {
    phase_ = SosPhase::CANCELED;
  }
}

void SosState::tick(uint32_t now_ms) {
  if (phase_ == SosPhase::ACKED) {
    if (acked_at_ms_ == 0) acked_at_ms_ = now_ms;
    if (now_ms - acked_at_ms_ > ACK_HOLD_MS) {
      phase_       = SosPhase::IDLE;
      acked_at_ms_ = 0;
    }
  }
}

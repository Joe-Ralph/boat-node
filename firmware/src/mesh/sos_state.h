#pragma once
#include <stdint.h>

// FSM-3 · SOS Originator.
// Owns local sequence counter, retry schedule, ACK / CANCEL transitions.
// Retry backoff: 0, 30, 60, 120, 300, 300, ... seconds (last value repeats).

enum class SosPhase : uint8_t {
  IDLE,
  ACTIVE,
  ACKED,
  CANCELED,
};

class SosState {
public:
  // Begin a new SOS session. Idempotent if already ACTIVE.
  void trigger(uint32_t now_ms, uint8_t reason, uint16_t user_id);

  // Caller informs us a TX of the current SOS just queued / sent.
  void note_tx(uint32_t now_ms);

  // Milliseconds until next scheduled TX from "now_ms".
  // Returns 0 if a TX should happen immediately, or a large sentinel if not ACTIVE.
  uint32_t next_retry_ms_from_now(uint32_t now_ms) const;

  void on_ack(uint16_t ack_seq, uint8_t status);
  void user_cancel();
  void battery_check(uint8_t pct);
  void tick(uint32_t now_ms);   // drives ACKED -> IDLE after 5 min hold

  SosPhase phase()   const { return phase_; }
  uint16_t seq()     const { return seq_; }
  uint16_t user_id() const { return user_id_; }
  uint8_t  reason()  const { return reason_; }

  // For NVS persistence:
  void seed_from_nvs(uint16_t last_seq) { seq_ = last_seq; }

private:
  SosPhase phase_       = SosPhase::IDLE;
  uint16_t seq_         = 0;
  uint8_t  retry_idx_   = 0;
  uint32_t last_tx_ms_  = 0;
  uint32_t acked_at_ms_ = 0;
  uint8_t  reason_      = 0;
  uint16_t user_id_     = 0;
  bool     first_tx_done_ = false;
};

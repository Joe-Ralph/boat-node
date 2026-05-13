#pragma once
#include <stdint.h>
#include "mesh/packet.h"
#include "mesh/dedup.h"
#include "mesh/forwarding.h"
#include "mesh/sos_state.h"
#include "mesh/uplink_queue.h"

// FSM-1 · Radio scheduler.
// Owns the single RFM95. Time-shares ownership between LMIC (LoRaWAN) and
// RadioLib mesh. Drains DIO0 RX flag every tick. Decides when to TX SOS,
// POS, forwards, and LoRaWAN uplinks per spec §"State Machines · FSM-1".
//
// Hardware-bound. Compile-only host stub; bench-tested per LAYER2.md.

class RadioScheduler {
public:
  void begin();

  // ISR sets this to true on DIO0 edge; cleared in run_one_tick().
  volatile bool mesh_rx_flag = false;

  // Drive the FSM once. Caller invokes from radioTask at ~5 ms cadence.
  void run_one_tick(uint32_t now_ms);

  // Event hooks from app layer.
  void on_button_sos(uint16_t user_id, uint8_t reason);
  void on_ble_sos_trigger(uint16_t user_id, uint8_t reason);
  void on_ble_cancel_sos(uint16_t user_id);
  void on_battery_pct(uint8_t pct);

  // NVS bootstrap.
  void load_identity(uint16_t mesh_src_id, const uint8_t hmac_secret[16],
                     uint16_t last_sos_seq);

  // Telemetry hooks. Read-only from app side.
  SosPhase sos_phase() const { return sos_.phase(); }
  uint16_t sos_seq()   const { return sos_.seq(); }

private:
  DedupCache  dedup_;
  ForwardSlot slots_[MAX_INFLIGHT_FWD];
  SosState    sos_;
  UplinkQueue uplinks_;

  uint8_t  hmac_secret_[16] = {};
  uint16_t mesh_src_id_     = 0;
  uint32_t next_pos_at_ms_  = 0;
  uint32_t boot_epoch_s_    = 0;

  void try_tx_sos(uint32_t now_ms);
  void try_tx_pos(uint32_t now_ms);
  void try_drain_forwards(uint32_t now_ms);
  void try_drain_lmic();
  void drain_rx(uint32_t now_ms);
};

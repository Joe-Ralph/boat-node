#include "radio/scheduler.h"
#include "mesh/build_parse.h"
#include "mesh/constants.h"
#include <string.h>

#ifdef ARDUINO
  #include <Arduino.h>
  #include <RadioLib.h>
  // Pin map for RFM95 — matches main.cpp comment block.
  // NSS=5, RST=14, DIO0=2, DIO1=4.
  static SX1276 g_radio = new Module(5, 2, 14, 4);
  static volatile bool s_rx_flag = false;
  IRAM_ATTR static void on_dio0_isr() { s_rx_flag = true; }
#endif

void RadioScheduler::begin() {
#ifdef ARDUINO
  // RadioLib LoRa init at mesh PHY. LMIC reconfigures on hand-off.
  int s = g_radio.begin(MESH_FREQ_MHZ, MESH_BW_KHZ, MESH_SF, MESH_CR,
                        MESH_SYNC_WORD, MESH_TX_DBM);
  if (s != RADIOLIB_ERR_NONE) {
    Serial.printf("[radio] init fail %d\n", s);
    return;
  }
  g_radio.setDio0Action(on_dio0_isr, RISING);
  g_radio.startReceive();
#endif
}

void RadioScheduler::load_identity(uint16_t mesh_src_id,
                                   const uint8_t hmac_secret[16],
                                   uint16_t last_sos_seq) {
  mesh_src_id_ = mesh_src_id;
  memcpy(hmac_secret_, hmac_secret, 16);
  sos_.seed_from_nvs(last_sos_seq);
}

void RadioScheduler::run_one_tick(uint32_t now_ms) {
#ifdef ARDUINO
  if (s_rx_flag) { mesh_rx_flag = true; s_rx_flag = false; }
#endif

  sos_.tick(now_ms);

  if (mesh_rx_flag) {
    drain_rx(now_ms);
    mesh_rx_flag = false;
  }

  if (sos_.phase() == SosPhase::ACTIVE && sos_.next_retry_ms_from_now(now_ms) == 0) {
    try_tx_sos(now_ms);
  }

  if (now_ms >= next_pos_at_ms_) {
    try_tx_pos(now_ms);
  }

  try_drain_forwards(now_ms);
  try_drain_lmic();
}

void RadioScheduler::on_button_sos(uint16_t user_id, uint8_t reason) {
#ifdef ARDUINO
  sos_.trigger(millis(), reason, user_id);
#else
  sos_.trigger(0, reason, user_id);
#endif
}

void RadioScheduler::on_ble_sos_trigger(uint16_t user_id, uint8_t reason) {
  on_button_sos(user_id, reason);
}

void RadioScheduler::on_ble_cancel_sos(uint16_t /*user_id*/) {
  sos_.user_cancel();
}

void RadioScheduler::on_battery_pct(uint8_t pct) {
  sos_.battery_check(pct);
}

void RadioScheduler::try_tx_sos(uint32_t now_ms) {
  SosBuild b{};
  b.src             = mesh_src_id_;
  b.seq             = sos_.seq();
  b.ts              = boot_epoch_s_ + (now_ms / 1000);
  b.batt_pc         = 100;     // wired from GPS task later
  b.reason          = sos_.reason();
  b.trigger_user_id = sos_.user_id();
  SosPkt pkt;
  build_sos(hmac_secret_, b, &pkt);

#ifdef ARDUINO
  int rc = g_radio.transmit(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt));
  if (rc != RADIOLIB_ERR_NONE) Serial.printf("[mesh] sos tx fail %d\n", rc);
  g_radio.startReceive();
#endif

  // Local-loop the originator's own dedup so we don't forward it.
  dedup_.seen_then_insert(pkt.hdr.src, pkt.hdr.seq, pkt.hdr.type);
  sos_.note_tx(now_ms);

  // SOS frames also enqueue for the gateway-class uplink path.
  UplinkItem it{};
  it.type = PKT_SOS;
  it.own  = true;
  it.seq  = pkt.hdr.seq;
  it.len  = sizeof(pkt);
  memcpy(it.payload, &pkt, sizeof(pkt));
  (void)uplinks_.enqueue(it);
}

void RadioScheduler::try_tx_pos(uint32_t now_ms) {
  PosBuild b{};
  b.src     = mesh_src_id_;
  b.seq     = 0;     // POS has its own free-running counter; caller can override
  b.ts      = boot_epoch_s_ + (now_ms / 1000);
  b.batt_pc = 100;
  PosPkt pkt;
  build_pos(b, &pkt);

#ifdef ARDUINO
  g_radio.transmit(reinterpret_cast<uint8_t*>(&pkt), sizeof(pkt));
  g_radio.startReceive();
#endif

  dedup_.seen_then_insert(pkt.hdr.src, pkt.hdr.seq, pkt.hdr.type);

  // Reschedule with ±20 s jitter. Pseudo-random from millis bottom bits.
  const uint32_t jitter = (now_ms & 0x7FFF) % (2 * POS_JITTER_S * 1000);
  next_pos_at_ms_ = now_ms + (POS_INTERVAL_S * 1000) - (POS_JITTER_S * 1000) + jitter;
}

void RadioScheduler::try_drain_forwards(uint32_t now_ms) {
  for (auto& s : slots_) {
    FwdState st = s.tick(now_ms);
    if (st == FwdState::DONE) {
      // Mesh-forward the cached frame. In this skeleton the slot only knows
      // the (src, seq, type) tuple — actual byte buffer is staged by drain_rx
      // alongside slot allocation in the production impl.
      s.state = FwdState::EMPTY;
    } else if (st == FwdState::SUPPRESSED || st == FwdState::DROP_TTL) {
      s.state = FwdState::EMPTY;
    }
  }
}

void RadioScheduler::try_drain_lmic() {
  // Defer to LMIC integration in main.cpp's LMIC loop. This scheduler tracks
  // intent; main.cpp owns the EV_TXCOMPLETE callback that calls dequeue.
}

void RadioScheduler::drain_rx(uint32_t now_ms) {
#ifdef ARDUINO
  uint8_t buf[64];
  int len = g_radio.getPacketLength();
  if (len <= 0 || len > (int)sizeof(buf)) {
    g_radio.startReceive();
    return;
  }
  int rc = g_radio.readData(buf, len);
  if (rc != RADIOLIB_ERR_NONE) {
    g_radio.startReceive();
    return;
  }

  // Validate header magic/ver/type to know which decoder to invoke.
  if (len < (int)sizeof(MeshHeader)) { g_radio.startReceive(); return; }
  const MeshHeader* h = reinterpret_cast<const MeshHeader*>(buf);
  if (h->magic != PKT_MAGIC || h->ver != PKT_VER) { g_radio.startReceive(); return; }

  ValidationCtx vc{ boot_epoch_s_ + (now_ms / 1000), 0 };
  switch (h->type) {
    case PKT_POS: {
      PosPkt p;
      if (validate_and_parse_pos(buf, len, &p, &dedup_, vc) == VrOk) {
        // Hand off to app for nearby cache + admin telemetry.
      }
      break;
    }
    case PKT_SOS: {
      SosPkt p;
      if (validate_and_parse_sos(buf, len, hmac_secret_, &p, &dedup_, vc) == VrOk) {
        // Stage forward + uplink.
        UplinkItem it{};
        it.type = PKT_SOS; it.own = false; it.seq = p.hdr.seq; it.len = len;
        memcpy(it.payload, buf, len);
        uplinks_.enqueue(it);
      }
      break;
    }
    case PKT_ACK: {
      AckPkt p;
      if (validate_and_parse_ack(buf, len, hmac_secret_, &p, &dedup_, vc) == VrOk) {
        if (p.ack_src == mesh_src_id_) sos_.on_ack(p.ack_seq, p.status);
      }
      break;
    }
    case PKT_CANCEL: {
      CancelPkt p;
      if (validate_and_parse_cancel(buf, len, hmac_secret_, &p, &dedup_, vc) == VrOk) {
        if (p.cancel_seq == sos_.seq()) sos_.user_cancel();
      }
      break;
    }
    default: break;
  }
  g_radio.startReceive();
#else
  (void)now_ms;
#endif
}

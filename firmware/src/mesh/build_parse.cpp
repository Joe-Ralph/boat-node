#include "mesh/build_parse.h"
#include "mesh/crc16.h"
#include "mesh/hmac_util.h"
#include <string.h>
#include <stdlib.h>

namespace {

void fill_header(MeshHeader& h, uint8_t type, uint16_t src, uint16_t dest,
                 uint16_t seq, uint32_t ts) {
  h.magic = PKT_MAGIC;
  h.ver   = PKT_VER;
  h.type  = type;
  h.src   = src;
  h.dest  = dest;
  h.seq   = seq;
  h.hops  = 0;
  h.ttl   = MESH_TTL_DEFAULT;
  h.ts    = ts;
}

uint16_t read_crc(const uint8_t* buf, size_t len) {
  return static_cast<uint16_t>(buf[len - 2]) |
         (static_cast<uint16_t>(buf[len - 1]) << 8);
}

uint32_t abs_diff(uint32_t a, uint32_t b) {
  return a >= b ? a - b : b - a;
}

ValidationResult pre_check(const uint8_t* buf, size_t len, uint8_t expect_type,
                           size_t expect_len, const ValidationCtx& vc,
                           DedupCache* d) {
  if (len < sizeof(MeshHeader))                 return VrTruncated;
  const MeshHeader* h = reinterpret_cast<const MeshHeader*>(buf);
  if (h->magic != PKT_MAGIC)                    return VrMagic;
  if (h->ver   != PKT_VER)                      return VrVer;
  if (h->type  != expect_type)                  return VrType;
  if (len != expect_len)                        return VrTruncated;

  if (crc16_ccitt(buf, len - 2) != read_crc(buf, len)) return VrCrc;

  // ts==0 means "no GPS time yet"; allow it through (originator may flag
  // NO_GPS_TIME via PosPkt.flags). Other validations remain.
  if (h->ts != 0 && abs_diff(vc.now_s, h->ts) > REPLAY_WINDOW_S) return VrStaleTs;

  if (d && d->seen_then_insert(h->src, h->seq, h->type)) return VrDup;
  return VrOk;
}

}  // namespace

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

void build_pos(const PosBuild& in, PosPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_POS, in.src, 0xFFFF, in.seq, in.ts);
  out->lat1e7   = in.lat1e7;
  out->lon1e7   = in.lon1e7;
  out->spd_cms  = in.spd_cms;
  out->hdg_cdeg = in.hdg_cdeg;
  out->batt_pc  = in.batt_pc;
  out->flags    = in.flags;
  out->user_id  = in.user_id;
  uint8_t n = in.name_len;
  if (n > sizeof(out->name_utf8)) n = sizeof(out->name_utf8);
  out->name_len = n;
  if (in.name && n) memcpy(out->name_utf8, in.name, n);
  out->crc = crc16_ccitt(reinterpret_cast<uint8_t*>(out), sizeof(PosPkt) - 2);
}

void build_sos(const uint8_t key[16], const SosBuild& in, SosPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_SOS, in.src, 0xFFFF, in.seq, in.ts);
  out->lat1e7          = in.lat1e7;
  out->lon1e7          = in.lon1e7;
  out->spd_cms         = in.spd_cms;
  out->hdg_cdeg        = in.hdg_cdeg;
  out->batt_pc         = in.batt_pc;
  out->reason          = in.reason;
  out->trigger_user_id = in.trigger_user_id;
  const size_t hmac_input_len = offsetof(SosPkt, hmac);
  hmac_sha256_trunc4(key, 16,
                     reinterpret_cast<uint8_t*>(out), hmac_input_len,
                     out->hmac);
  out->crc = crc16_ccitt(reinterpret_cast<uint8_t*>(out), sizeof(SosPkt) - 2);
}

void build_ack(const uint8_t key[16], const AckBuild& in, AckPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_ACK, in.src, in.dest, in.seq, in.ts);
  out->ack_src = in.ack_src;
  out->ack_seq = in.ack_seq;
  out->status  = in.status;
  const size_t hmac_input_len = offsetof(AckPkt, hmac);
  hmac_sha256_trunc4(key, 16,
                     reinterpret_cast<uint8_t*>(out), hmac_input_len,
                     out->hmac);
  out->crc = crc16_ccitt(reinterpret_cast<uint8_t*>(out), sizeof(AckPkt) - 2);
}

void build_cancel(const uint8_t key[16], const CancelBuild& in, CancelPkt* out) {
  memset(out, 0, sizeof(*out));
  fill_header(out->hdr, PKT_CANCEL, in.src, 0xFFFF, in.seq, in.ts);
  out->cancel_seq      = in.cancel_seq;
  out->trigger_user_id = in.trigger_user_id;
  const size_t hmac_input_len = offsetof(CancelPkt, hmac);
  hmac_sha256_trunc4(key, 16,
                     reinterpret_cast<uint8_t*>(out), hmac_input_len,
                     out->hmac);
  out->crc = crc16_ccitt(reinterpret_cast<uint8_t*>(out), sizeof(CancelPkt) - 2);
}

// ---------------------------------------------------------------------------
// Validate + parse
// ---------------------------------------------------------------------------

ValidationResult validate_and_parse_pos(const uint8_t* buf, size_t len, PosPkt* out,
                                        DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_POS, sizeof(PosPkt), vc, d);
  if (r != VrOk) return r;
  memcpy(out, buf, sizeof(PosPkt));
  return VrOk;
}

ValidationResult validate_and_parse_sos(const uint8_t* buf, size_t len,
                                        const uint8_t key[16], SosPkt* out,
                                        DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_SOS, sizeof(SosPkt), vc, d);
  if (r != VrOk) return r;
  const size_t input_len = offsetof(SosPkt, hmac);
  if (!hmac_sha256_verify_trunc4(key, 16, buf, input_len,
                                 buf + offsetof(SosPkt, hmac))) {
    return VrHmacFail;
  }
  memcpy(out, buf, sizeof(SosPkt));
  return VrOk;
}

ValidationResult validate_and_parse_ack(const uint8_t* buf, size_t len,
                                        const uint8_t key[16], AckPkt* out,
                                        DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_ACK, sizeof(AckPkt), vc, d);
  if (r != VrOk) return r;
  const size_t input_len = offsetof(AckPkt, hmac);
  if (!hmac_sha256_verify_trunc4(key, 16, buf, input_len,
                                 buf + offsetof(AckPkt, hmac))) {
    return VrHmacFail;
  }
  memcpy(out, buf, sizeof(AckPkt));
  return VrOk;
}

ValidationResult validate_and_parse_cancel(const uint8_t* buf, size_t len,
                                           const uint8_t key[16], CancelPkt* out,
                                           DedupCache* d, const ValidationCtx& vc) {
  ValidationResult r = pre_check(buf, len, PKT_CANCEL, sizeof(CancelPkt), vc, d);
  if (r != VrOk) return r;
  const size_t input_len = offsetof(CancelPkt, hmac);
  if (!hmac_sha256_verify_trunc4(key, 16, buf, input_len,
                                 buf + offsetof(CancelPkt, hmac))) {
    return VrHmacFail;
  }
  memcpy(out, buf, sizeof(CancelPkt));
  return VrOk;
}

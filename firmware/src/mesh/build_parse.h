#pragma once
#include <stddef.h>
#include "mesh/packet.h"
#include "mesh/dedup.h"
#include "mesh/constants.h"

enum ValidationResult {
  VrOk          = 0,
  VrTruncated   = 1,
  VrMagic       = 2,
  VrVer         = 3,
  VrType        = 4,
  VrCrc         = 5,
  VrDup         = 6,
  VrStaleTs     = 7,
  VrHmacFail    = 8,
  VrTtlExceeded = 9,
};

struct ValidationCtx {
  uint32_t now_s;       // current GPS time
  uint16_t last_seq;    // monotonic guard (per src)
};

// Builders fill the output buffer including CRC and HMAC. No allocation.
struct PosBuild {
  uint16_t src; uint16_t seq; uint32_t ts;
  int32_t  lat1e7; int32_t lon1e7;
  uint16_t spd_cms; uint16_t hdg_cdeg;
  uint8_t  batt_pc; uint8_t flags;
  uint16_t user_id;
  const char* name; uint8_t name_len;
};

struct SosBuild {
  uint16_t src; uint16_t seq; uint32_t ts;
  int32_t  lat1e7; int32_t lon1e7;
  uint16_t spd_cms; uint16_t hdg_cdeg;
  uint8_t  batt_pc; uint8_t reason;
  uint16_t trigger_user_id;
};

struct AckBuild {
  uint16_t src; uint16_t dest; uint16_t seq; uint32_t ts;
  uint16_t ack_src; uint16_t ack_seq; uint8_t status;
};

struct CancelBuild {
  uint16_t src; uint16_t seq; uint32_t ts;
  uint16_t cancel_seq; uint16_t trigger_user_id;
};

void build_pos   (const PosBuild& in, PosPkt* out);
void build_sos   (const uint8_t key[16], const SosBuild& in,    SosPkt* out);
void build_ack   (const uint8_t key[16], const AckBuild& in,    AckPkt* out);
void build_cancel(const uint8_t key[16], const CancelBuild& in, CancelPkt* out);

ValidationResult validate_and_parse_pos(
    const uint8_t* buf, size_t len, PosPkt* out,
    DedupCache* d, const ValidationCtx& vc);

ValidationResult validate_and_parse_sos(
    const uint8_t* buf, size_t len, const uint8_t key[16], SosPkt* out,
    DedupCache* d, const ValidationCtx& vc);

ValidationResult validate_and_parse_ack(
    const uint8_t* buf, size_t len, const uint8_t key[16], AckPkt* out,
    DedupCache* d, const ValidationCtx& vc);

ValidationResult validate_and_parse_cancel(
    const uint8_t* buf, size_t len, const uint8_t key[16], CancelPkt* out,
    DedupCache* d, const ValidationCtx& vc);

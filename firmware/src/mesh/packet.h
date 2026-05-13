#pragma once
#include <stdint.h>

// All multi-byte fields little-endian. Wire = byte-exact struct copy.
// Size asserts at the bottom guard against ABI drift.

#pragma pack(push, 1)

struct MeshHeader {
  uint8_t  magic;   // 0xBA
  uint8_t  ver;     // 0x02
  uint8_t  type;    // PktType
  uint16_t src;     // originator mesh_src_id
  uint16_t dest;    // 0xFFFF = broadcast; originator src for ACK
  uint16_t seq;     // monotonic per src
  uint8_t  hops;    // incremented per forward
  uint8_t  ttl;     // default 4; decrement-and-drop
  uint32_t ts;      // unix seconds from GPS time
};

struct PosPkt {
  MeshHeader hdr;          // type = PKT_POS, dest = 0xFFFF
  int32_t    lat1e7;
  int32_t    lon1e7;
  uint16_t   spd_cms;
  uint16_t   hdg_cdeg;
  uint8_t    batt_pc;
  uint8_t    flags;        // bit0 = journey_active
  uint16_t   user_id;      // profiles.user_short_id
  uint8_t    name_len;
  uint8_t    name_utf8[12];
  uint16_t   crc;          // CRC16-CCITT over bytes 0..(sizeof - 2)
};

struct SosPkt {
  MeshHeader hdr;             // type = PKT_SOS, dest = 0xFFFF
  int32_t    lat1e7;
  int32_t    lon1e7;
  uint16_t   spd_cms;
  uint16_t   hdg_cdeg;
  uint8_t    batt_pc;
  uint8_t    reason;          // 0=manual, 1=MOB, 2=engine, 3=medical, ...
  uint16_t   trigger_user_id; // profiles.user_short_id
  uint8_t    hmac[4];         // HMAC-SHA256(secret, bytes 0..offsetof(hmac))[:4]
  uint16_t   crc;
};

struct AckPkt {
  MeshHeader hdr;             // type = PKT_ACK, dest = originator's src
  uint16_t   ack_src;
  uint16_t   ack_seq;
  uint8_t    status;          // SosStatus
  uint8_t    reserved;
  uint8_t    hmac[4];         // signed with ORIGINATOR's secret
  uint16_t   crc;
};

struct CancelPkt {
  MeshHeader hdr;             // type = PKT_CANCEL, dest = 0xFFFF
  uint16_t   cancel_seq;
  uint16_t   trigger_user_id; // CREW may cancel only own (= trigger_user_id matches)
  uint8_t    hmac[4];
  uint16_t   crc;
};

#pragma pack(pop)

// Wire sizes. Spec table prose under §"Packet Formats" had POS/SOS/ACK math
// drift; ground truth is the layout above. Edge function + ChirpStack codec
// must agree to these constants, not the prose.
static_assert(sizeof(MeshHeader) == 15, "MeshHeader must be 15 bytes");
static_assert(sizeof(PosPkt)     == 46, "PosPkt must be 46 bytes");
static_assert(sizeof(SosPkt)     == 37, "SosPkt must be 37 bytes (spec prose says 36; layout sums to 37)");
static_assert(sizeof(AckPkt)     == 27, "AckPkt must be 27 bytes (spec prose says 25; layout sums to 27)");
static_assert(sizeof(CancelPkt)  == 25, "CancelPkt must be 25 bytes");

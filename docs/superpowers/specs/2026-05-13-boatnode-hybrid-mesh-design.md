# BoatNode Hybrid LoRaWAN+Mesh Design Spec

**Date:** 2026-05-13
**Status:** Design approved, awaiting implementation plan
**Scope:** Firmware (`firmware/src/main.cpp`), backend (Supabase + ChirpStack codec), Flutter app (`app/boatnode/lib/services/hardware_service.dart`, joiner SOS path), admin dashboard

## Problem Statement

BoatNode is a fisherman-safety system. Each boat node has ESP32 + RFM95 + NEO-6M GPS + BLE + WS2812 status LED. Today's production firmware (`firmware/src/main.cpp`) is LoRaWAN-only: a boat outside ChirpStack gateway range cannot reach the backend. Joiner crew members send SOS only over Supabase RPC and never touch LoRa, so when the owner's phone is offline the SOS never reaches the mesh even if the joiner is standing next to the boat device.

The design extends each boat node to act as a **hybrid LoRaWAN/mesh device**: time-shares a single RFM95 between LMIC (LoRaWAN) and a private SX1276 P2P mesh. Boats out of gateway range flood SOS+position over the mesh; the first boat in gateway range relays to ChirpStack. Crew members on the boat authenticate via BLE (separate auth tier from owner) and can trigger SOS through the same physical device. Backend signs an ACK that flows back through mesh to the originator, closing the "did my SOS reach land?" loop.

## Requirements

### Functional
- Boats out of gateway range deliver SOS to backend via mesh + any-cast relay through a gateway-class boat.
- SOS receives end-to-end ACK from backend, flooded back through mesh to originator within 30 seconds.
- Multiple crew members per boat can read live status and trigger/cancel SOS through the boat's BLE radio.
- Crew can toggle journey state (start/end). Crew cannot edit config, rotate keys, or factory reset.
- Joiner SOS falls back to Supabase RPC when no BLE link to the boat is available.

### Non-Functional
- Battery: 1 week on 2× 18650 (~7 Ah) at typical fishing duty cycle.
- Worst-case SOS gateway delivery: ≤30 s in mesh-reachable scenarios.
- HMAC-SHA256 truncated to 4 bytes for security-relevant frames; spoof and replay defense.
- Single RFM95 only (no hardware change vs current production board).
- Mesh handles sparse offshore (2–5 km inter-boat, 10–30 boats) through medium coastal (0.5–2 km, 30–100 boats).
- No central routing state; resilient to mobile topology.

### Out of Scope (v1)
- Crew token rotation on crew removal (deferred to v2).
- Asymmetric cryptography (HMAC sufficient at this airtime budget).
- "Bottle in ocean" long-term store-and-forward across hours (deferred to v2).
- AODV-style route discovery (rejected: boats move too fast).
- OLED display in production (debug only).

## Decisions (Brainstorming Outcome)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| Q1 | Radio topology | Single RFM95 time-shared between LMIC and RadioLib mesh | No BOM change. ESP32 can drive radio FSM. |
| Q2 | SOS latency tier | Fast (≤30 s gateway delivery) | Right for fisherman safety. |
| Q3 | Fleet density assumption | Sparse offshore → medium coastal | Drives RBSF parameters, dedup cache size. |
| Q4 | Packet types + ACK | POS, SOS, ACK, CANCEL with end-to-end mesh ACK | "Did SOS reach land?" closes loop for the fisherman. |
| Q5 | SOS authentication | HMAC-SHA256 truncated to 4 bytes, per-boat secret | Spoof defense. Fits airtime budget. Per-boat key isolates compromise. |
| Q6 | Store-and-forward | Persistent retry until ACK, user-cancel, or battery <10% | Safety dominates battery in emergency. |
| Q7 | Identity + secret provisioning | Backend-assigned u16 `mesh_src_id`; secret generated on-device at BLE pair time | Compact (2 B/packet), stable, backend-owned. No factory step. |
| Q8 | SOS overrides journey privacy + cancel UX | SOS always transmits regardless of journey state. Cancel from app button OR hardware long-press OR backend false-alarm. | Safety dominates privacy in emergency. Phone may be unavailable. |
| Mesh proto | Approach | RBSF (controlled flood with overhearing suppression, K=2) | Adapts to density without routing state. Resilient to mobile topology. |
| Crew BLE | Permissions | Crew can read DATA + ACK_FEED, trigger/cancel SOS, toggle journey. Cannot edit config or rotate keys. | Crew is physically on the boat; journey toggle is a legitimate crew action. Config and keys remain owner-only. |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       BOAT NODE (ESP32 + RFM95)                      │
│                                                                       │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐      │
│   │   BLE    │    │   GPS    │    │  Status  │    │ Buttons  │      │
│   │  Server  │    │ NEO-6M   │    │   LED    │    │ SOS/RST  │      │
│   │ (multi)  │    │          │    │ WS2812   │    │          │      │
│   └────┬─────┘    └────┬─────┘    └──────────┘    └────┬─────┘      │
│        │               │                                │             │
│        └───────┬───────┴─────────────────┬──────────────┘             │
│                │                         │                            │
│        ┌───────▼─────────┐       ┌───────▼─────────┐                 │
│        │  BoatState +    │       │  Radio Scheduler │                 │
│        │  MeshState      │◄──────┤  (FSM-1)         │                 │
│        │  (mutex-guarded)│       └───────┬─────────┘                 │
│        └─────────────────┘               │                            │
│                                  ┌───────▼────────┐                  │
│                                  │   RFM95 SX1276  │                  │
│                                  │  (single radio) │                  │
│                                  └───┬─────────┬───┘                  │
│                                      │         │                      │
│                          ┌───────────▼┐   ┌────▼──────────┐          │
│                          │  LoRaWAN   │   │  Mesh P2P     │          │
│                          │  (LMIC)    │   │  (RadioLib)   │          │
│                          │  865 MHz   │   │  865.2 MHz    │          │
│                          │  Class A   │   │  SF9 BW125    │          │
│                          └────┬───────┘   └───────┬───────┘          │
└───────────────────────────────┼───────────────────┼──────────────────┘
                                │ uplink            │ flood
                                ▼                   ▼
                          ┌──────────┐         ┌────────────┐
                          │ChirpStack│         │ Neighbor   │
                          │  GW      │         │ boats      │
                          └────┬─────┘         └──────┬─────┘
                               │ webhook              │
                               ▼                      │
                          ┌──────────┐                │
                          │ Supabase │                │
                          │ Edge fn  │◄───────────────┘
                          │ (decode +│
                          │  HMAC)   │
                          └────┬─────┘
                               ▼
                          ┌──────────────────────────┐
                          │ Supabase (tables, RPCs,  │
                          │ realtime, RLS)           │
                          └────┬─────────────┬───────┘
                               │             │
                               ▼             ▼
                          ┌──────────┐  ┌──────────┐
                          │  Admin   │  │ Flutter  │
                          │ dashboard│  │ app      │
                          └──────────┘  └──────────┘
```

### Process model on ESP32

- **`radioTask`** (core 0, high priority): owns RFM95. Runs FSM-1 (radio scheduler), drains DIO0 IRQ flag.
- **`appTask`** (core 1, normal): BLE callbacks, GPS parse, LED FSM, button polling, ADC.
- Shared state: `BoatState` (existing) + new `MeshState` (dedup cache, forward queue, nearby cache). Guarded by `dataMutex` (existing) and new `meshMutex`. Mutex order: `dataMutex` → `meshMutex`.
- Single ISR: `setMeshRxFlag()` on DIO0. Polled by `radioTask` on 5 ms tick.

### Key constants

| Constant | Value | Source |
|---|---|---|
| `MESH_FREQ_MHZ` | 865.2 | Q3 fleet density compatible with EU868 sub-band. |
| `MESH_SF` | 9 | Range/airtime balance for sparse-medium fleet. |
| `MESH_BW_KHZ` | 125 | Standard. |
| `MESH_CR` | 4/5 | RadioLib default. |
| `MESH_SYNC_WORD` | 0x12 | LoRa private network sync word (distinct from LoRaWAN's 0x34). |
| `MESH_TX_DBM` | 14 | ETSI limit for 865.2 MHz sub-band. |
| `MESH_TTL` | 4 | Hops before drop. |
| `K_SUPPRESS` | 2 | RBSF overhearing threshold. |
| `JITTER_POS` | 200..800 ms | RBSF jitter for POS forwards. |
| `JITTER_SOS` | 50..200 ms | RBSF jitter for SOS forwards (fast). |
| `JITTER_ACK` | 50..200 ms | RBSF jitter for ACK forwards (fast). |
| `MAX_INFLIGHT_FWD` | 8 | Concurrent pending forwards (RAM bound). |
| `DEDUP_CACHE_SIZE` | 64 entries | (src, seq, type) → ring buffer. |
| `NEARBY_CACHE_SIZE` | 30 entries | Existing. |
| `POS_INTERVAL_S` | 120 | POS broadcast cadence. |
| `POS_JITTER_S` | ±20 | Collision avoidance. |
| `SOS_RETRY_S` | 0, 30, 60, 120, 300, 300, ... | Exponential backoff cap. |
| `REPLAY_WINDOW_S` | 300 | `ts` freshness window. |
| `BLE_MAX_CONN` | 4 | Owner + 3 crew slots. |
| `LOW_BATT_THRESHOLD_PC` | 10 | Stop POS retries, allow final SOS. |
| `CRITICAL_BATT_PC` | 5 | Hard shutdown. |

## Packet Formats

All multi-byte fields **little-endian**. Structs use `#pragma pack(push,1)`. Wire = byte-exact struct copy.

### MeshHeader (15 bytes, all frames)

```c
struct __attribute__((packed)) MeshHeader {
  uint8_t  magic;    // 0xBA = BoatNode mesh
  uint8_t  ver;      // 0x02
  uint8_t  type;     // 0x01=POS, 0x02=SOS, 0x03=ACK, 0x04=CANCEL
  uint16_t src;      // originator's mesh_src_id
  uint16_t dest;     // 0xFFFF = broadcast (POS/SOS/CANCEL); originator's src (ACK)
  uint16_t seq;      // monotonic per src
  uint8_t  hops;     // incremented on each forward; starts at 0
  uint8_t  ttl;      // default 4; decrement-and-drop
  uint32_t ts;       // unix seconds from GPS time; replay defense
};
```

### PosPkt (46 bytes; no HMAC)

```c
struct __attribute__((packed)) PosPkt {
  MeshHeader hdr;          // type=0x01, dest=0xFFFF
  int32_t  lat1e7;
  int32_t  lon1e7;
  uint16_t spd_cms;
  uint16_t hdg_cdeg;
  uint8_t  batt_pc;
  uint8_t  flags;          // bit0=journey_active, bit1..7 reserved
  uint16_t user_id;
  uint8_t  name_len;
  uint8_t  name_utf8[12];  // zero-padded
  uint16_t crc;            // CRC16-CCITT
};
```

### SosPkt (36 bytes; HMAC)

```c
struct __attribute__((packed)) SosPkt {
  MeshHeader hdr;            // type=0x02, dest=0xFFFF
  int32_t  lat1e7;
  int32_t  lon1e7;
  uint16_t spd_cms;
  uint16_t hdg_cdeg;
  uint8_t  batt_pc;
  uint8_t  reason;           // 0=manual, 1=man-overboard, 2=engine, 3=medical, ...
  uint16_t trigger_user_id;  // = profiles.user_short_id; 0 = unknown/owner-default
  uint8_t  hmac[4];          // HMAC-SHA256(secret, hdr || payload up to here)[:4]
  uint16_t crc;
};
```

`trigger_user_id` is the u16 `profiles.user_short_id`, **not** the UUID `profiles.id`. Backend resolves UUID via `profiles.user_short_id` index on receive.

### AckPkt (25 bytes; HMAC)

```c
struct __attribute__((packed)) AckPkt {
  MeshHeader hdr;            // type=0x03, dest=originator's src_id
  uint16_t ack_src;
  uint16_t ack_seq;
  uint8_t  status;           // 0=received, 1=dispatched, 2=resolved, 3=false-alarm
  uint8_t  reserved;
  uint8_t  hmac[4];          // signed with originator's hmac_secret
  uint16_t crc;
};
```

`hdr.src` of an ACK is whichever gateway-boat uplinked the SOS. Backend identity is not on-air. Only the originator validates HMAC; forwarders flood blindly.

### CancelPkt (25 bytes; HMAC)

```c
struct __attribute__((packed)) CancelPkt {
  MeshHeader hdr;            // type=0x04, dest=0xFFFF
  uint16_t cancel_seq;
  uint16_t trigger_user_id;  // = profiles.user_short_id; device ACLs "crew cancel own only"
  uint8_t  hmac[4];
  uint16_t crc;
};
```

### Validation pipeline (every received frame)

1. `len ≥ sizeof(MeshHeader)` else drop (truncated).
2. `magic == 0xBA && ver == 0x02` else drop.
3. `type ∈ {POS, SOS, ACK, CANCEL}` else drop.
4. CRC16-CCITT over frame matches else drop.
5. `(src, seq, type)` in dedup cache → drop (already handled).
6. `ts` within ±300 s of GPS time → continue, else drop.
7. If `type ∈ {SOS, ACK, CANCEL}`: HMAC verify; drop on fail.
8. Insert `(src, seq, type)` into dedup cache.
9. Hand to forwarding (FSM-2) and local logic.

### Airtime (SF9 BW125, CR4/5, explicit header, CRC on)

| Packet | Bytes | Airtime |
|---|---|---|
| POS | 46 | ~205 ms |
| SOS | 36 | ~180 ms |
| ACK | 25 | ~145 ms |
| CANCEL | 25 | ~145 ms |

Boat at idle: 205 / 120000 ≈ 0.17 % duty. Well under ETSI 1 %.

### Field validation rules

| Field | Constraint |
|---|---|
| `lat1e7` | -900000000..900000000; `0,0` means "no GPS fix" |
| `lon1e7` | -1800000000..1800000000 |
| `name_len` | 0..12 |
| `ttl` | clamped 1..6 on receive |
| `hops` | drop if `hops > ttl` |
| `ts` | within ±300 s of current GPS time |

## State Machines

### FSM-1: Radio Scheduler

Radio is owned by exactly one of `{LMIC, Mesh}` at any instant. Switching ≈ 5 ms (retune + reconfigure SF/BW/sync-word).

States: `BOOT`, `MESH_LISTEN`, `MESH_TX`, `MESH_PROCESS`, `LMIC_HANDOFF`, `LMIC_ACTIVE`.

Triggers:

| Trigger | Action |
|---|---|
| `meshRxFlag` set (DIO0 IRQ in mesh mode) | `MESH_LISTEN → MESH_PROCESS` |
| POS timer fires (every 120 s ±20 s) | `MESH_LISTEN → MESH_TX(POS)` |
| Forward queue nonempty after jitter elapsed | `MESH_LISTEN → MESH_TX(forward)` |
| LoRaWAN uplink queue nonempty AND no SOS in flight | `MESH_LISTEN → LMIC_HANDOFF` |
| LoRaWAN join timer fires (boot + every 30 min if not joined) | `LMIC_HANDOFF` |
| LMIC `EV_TXCOMPLETE` (RX1/RX2 closed) | `LMIC_ACTIVE → MESH_LISTEN` |
| SOS active and retry timer fires | `MESH_LISTEN → MESH_TX(SOS)` (preempts queued POS) |

Preemption: SOS always wins. If about to hand off to LMIC for a routine POS uplink and an SOS arrives, drop the LMIC plan, mesh-broadcast SOS first, then re-evaluate. SOS cannot preempt mid-LMIC-RX-window (must wait ~6 s for `EV_TXCOMPLETE`).

Mesh-mode listen uses CAD-cycle: 5 ms CAD scan / 100 ms sleep. On preamble detect, switch to full RX, decode frame.

### FSM-2: Per-packet Forwarding (RBSF)

Per pending `(src, seq, type)` in `forward_queue`:

| State | Transition |
|---|---|
| `PENDING` (jitter=R, heard=0) | overhear same (src,seq,type) → `heard++` |
| | heard ≥ `K_SUPPRESS` → `SUPPRESSED` → free slot |
| | jitter expires AND heard < K → TX → `DONE` → free slot |
| | `hops+1 > ttl` → `DROP_TTL` → free slot |
| | dedup hit (already TX'd) → `DROP_DUP` |

### FSM-3: SOS Originator

| State | Trigger | Next |
|---|---|---|
| `IDLE` | button or BLE SOS_TRIGGER | `ACTIVE`, seq=N, TX SOS, start retry timer, LED red fast-pulse |
| `ACTIVE` | retry timer | `ACTIVE`, retry++, TX SOS (regenerate ts, HMAC) |
| `ACTIVE` | ACK rx (HMAC ok, ack_src=self) | `ACKED`, status from packet, LED green |
| `ACTIVE` | local cancel OR remote CANCEL OR batt<10% | `CANCELED`, TX CANCEL once, LED off |
| `ACKED` | status=2 (resolved) or 3 (false-alarm) | `IDLE` after 5 min hold |

Retry schedule: 0 s, 30 s, 60 s, 120 s, 300 s, then 300 s repeating until ACK/CANCEL/batt<10%. Each retry regenerates `ts` and HMAC; `seq` stays constant per session.

### FSM-4: LoRaWAN Uplink Queue (gateway-boat role)

States: `EMPTY → QUEUED → IN_FLIGHT → (EMPTY|QUEUED)`. Queue depth 8.

| Frame type | Uplink? |
|---|---|
| SOS (own) | Always. Priority. |
| SOS (mesh-relayed) | Always. Backend dedups. |
| POS (own) | Always (routine track). |
| POS (mesh-relayed) | Only if `relay_mode` enabled (default OFF, backend can flip per-boat via downlink). |
| CANCEL (own or mesh-relayed) | Always. |

Drop policy: full queue + new SOS → evict oldest non-SOS. Full SOS-only queue + non-SOS arrival → drop arrival.

### RAM budget

| Structure | Bytes |
|---|---|
| Dedup cache (64 × 5) | 320 |
| Forward queue (8 × 50) | 400 |
| Nearby boats cache (30 × 36) | 1080 |
| LoRaWAN uplink queue (8 × 50) | 400 |
| SosState | 64 |
| Mutexes/handles | ~200 |
| **Total mesh state** | **~2.5 KB** |

ESP32 has 320 KB SRAM. Trivial.

## Identity & Security

### Identities

| ID | Scope | Format | Source | Used by |
|---|---|---|---|---|
| `DevEUI` | LoRaWAN | 8 B hex | Vendor or operator block | LMIC join, ChirpStack registry |
| `mesh_src_id` | Mesh P2P | u16 | Backend-assigned at pair | Mesh frames, dedup, ACK routing |
| `boat_id` (display) | App/human | string e.g. `"B1234"` | Backend; returned alongside `mesh_src_id` from `pair_boat` RPC; stored in device NVS for OLED/log strings | UI, QR, support |
| `user_short_id` | Mesh P2P | u16 | Backend-assigned at user signup (new column on `profiles`) | `trigger_user_id` field in SOS/CANCEL packets |
| `profiles.id` | Supabase | UUID | Supabase auth | Backend joins, RLS |

### Secrets

| Secret | Bytes | Where | Lifetime |
|---|---|---|---|
| LoRaWAN AppKey | 16 | Device NVS + ChirpStack | Lifetime |
| LoRaWAN AppEUI/DevEUI | 8 + 8 | Device flash + ChirpStack | Lifetime |
| `hmac_secret` (mesh) | 16 | Device NVS + Supabase `boats.hmac_secret` | Per device, rotatable in v2 |
| `crew_token` | 8 | Device NVS + Supabase `boats.crew_token` | Per device, rotatable in v2 |

### Provisioning (BLE pair time)

Device generates both `hmac_secret` (16 B) and `crew_token` (8 B) via `esp_random()` on first boot. Phone pulls them over BLE and uploads to Supabase `pair_boat` RPC over HTTPS (TLS to Supabase). Backend assigns next free `mesh_src_id` and returns it to the phone, which writes back to device via BLE `PAIR_FINALIZE` command. Device sets `paired=true` in NVS.

Trust boundary: phone TLS to Supabase + short-range BLE link at pair time (user holds both devices). Secrets never traverse BLE after pair.

### HMAC

```
hmac_input = MeshHeader (15 B) || payload up to (but excluding) hmac and crc
hmac_full  = HMAC_SHA256(hmac_secret, hmac_input)
hmac_4     = hmac_full[0..3]
```

Library: `mbedtls_md_hmac` (built into Arduino-ESP32). ~1 ms per packet. Brute force at 2^32 = ~24 years of continuous LoRa TX — out of threat model.

### NVS layout (namespace `boat_cfg`)

| Key | Type | Notes |
|---|---|---|
| `paired` | bool | |
| `mesh_src_id` | u32 (low 16 used) | |
| `boat_id` | string ≤9 | display form |
| `user_id` | u32 | owner |
| `display_name` | string ≤14 | |
| `hmac_secret` | blob 16 B | internal API only; **no BLE getter** |
| `crew_token` | blob 8 B | internal API only; **no BLE getter** |
| `relay_mode` | bool | default false; LoRaWAN downlink only |
| `last_sos_seq` | u16 | replay defense across reboots |
| `last_journey_toggle_user_id` | u16 | audit |
| `lorawan_devkey` | blob 16 B | OTAA AppKey |
| `lorawan_appeui`/`lorawan_deveui` | blob 8 B / 8 B | |

### Threat model

| Attack | Mitigation |
|---|---|
| Spoofed SOS from rogue LoRa | HMAC verify fails at backend → drop |
| Replay of captured SOS | `ts` outside ±300 s OR `seq ≤ last_seq` rejected |
| Spoofed POS (no HMAC) | Backend rate-limit per src, position-jump filter, src must be registered |
| Forged ACK to fake "help on way" | ACK HMAC'd with originator's secret; attacker has no key |
| Selective DoS (malicious forwarder drops SOS) | RBSF + flood = multiple paths |
| Mass spoof flood (DoS) | CAD listen near-free; backend rate-limits per src |
| Phone compromise post-pair | Secret never in phone storage post-pair |
| Device theft | Owner reports → backend disables boat / rotates secret via LoRaWAN downlink (v2) |
| Stolen joiner phone | Has `crew_token` only; cannot forge mesh HMAC; owner removes via `boat_members` |
| Removed crew re-uses old token (v1 gap) | Documented gap. v2 rotates `crew_token`. |
| Crew tries owner commands | BLE per-command ACL drops at device |

Not protected: backend compromise (standard hardening applies); device side-channel/flash dump (use ESP32 flash encryption + secure boot in v2); active jamming (detection only — fleet-wide silence → SAR alert).

## Joiner Support & Multi-tenant BLE

### Auth tiers

| Tier | Token | Capabilities |
|---|---|---|
| Owner | `hmac_secret` | Read DATA/ACK_FEED, SOS/CANCEL, journey toggle, SET config, ROTATE_KEY, FACTORY_RESET |
| Crew | `crew_token` | Read DATA/ACK_FEED, SOS/CANCEL (own SOS only for CANCEL), journey toggle |
| Stranger | none | Connect allowed; no notify, no commands |

### GATT layout

Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b` (existing).

| Char | Property | Purpose |
|---|---|---|
| `beb5483e-...` (DATA) | Read/Notify | Status frame (existing) |
| `8246d623-...` (CMD) | Write | Existing command grammar |
| AUTH_CHALLENGE (new UUID) | Read | 16-byte random nonce per connection |
| AUTH_RESPONSE (new UUID) | Write | `{tier_hint, HMAC(token, challenge)[:8]}` |
| AUTH_STATUS (new UUID) | Read/Notify | Tier achieved on this conn |
| SOS_TRIGGER (new UUID) | Write | Explicit SOS endpoint with `{user_id, reason}` |
| ACK_FEED (new UUID) | Read/Notify | Last ACK status (mirrors mesh ACK to BLE) |

UUIDs for new chars: generate at implementation; document in spec annex.

### Auth handshake (per connection)

```
Phone                                          Device
  1. BLE connect                          ──►   conn.tier = STRANGER
  2. read AUTH_CHALLENGE                  ◄──   C = 16 random bytes
  3. compute proof = HMAC_SHA256(token, C)[:8]
     write AUTH_RESPONSE {tier_hint, proof}
                                          ──►   lookup token by tier_hint
                                                expected = HMAC_SHA256(token, C)[:8]
                                                consteq(proof, expected)
                                                  ok  → conn.tier = OWNER/CREW
                                                  fail → conn.tier stays STRANGER
                                                          disconnect after 5 s idle
  4. read AUTH_STATUS                     ◄──   {tier, ok}
  5. subscribe to DATA, ACK_FEED
  6. operate
```

Challenge nonce rotates per connection. Replaying captured proof against a new challenge fails.

### Per-command ACL

| Command | Owner | Crew | Stranger |
|---|---|---|---|
| `SET:` config | ✓ | ✗ | ✗ |
| `START_JOURNEY` / `END_JOURNEY` | ✓ | ✓ | ✗ |
| `SOS_TRIGGER` | ✓ | ✓ | ✗ |
| `CANCEL_SOS` | ✓ | own SOS only (match `trigger_user_id`) | ✗ |
| `ROTATE_KEY` | ✓ | ✗ | ✗ |
| `FACTORY_RESET` | ✓ | ✗ | ✗ |
| Subscribe DATA | ✓ | ✓ | ✗ |
| Subscribe ACK_FEED | ✓ | ✓ | ✗ |

### Joiner SOS happy path

```
Joiner phone           Boat device                Mesh                 Backend          Owner phone
─────────────          ──────────                ──────                ────────         ──────────
1. tap SOS
2. BLE SOS_TRIGGER
   {user_id, reason}
                   ─►  ACL ok (CREW)
                       build SosPkt
                       sign HMAC
                       SosState ACTIVE
                       TX SOS over mesh    ─►
                                              gateway-boat hears,
                                              relays via LoRaWAN  ─►   verify HMAC
                                                                       INSERT sos_signals
                                                                       origin='mesh'
                                                                       trigger_user_id=joiner
                                                                       realtime notify
                                                                                          ─► CallKit:
                                                                                             "joiner SOS"
                                                                       build AckPkt
                                                                       sign HMAC
                                                                       downlink to GW   ◄─
                                              GW boat retransmits
                                              ACK to mesh        ◄─
                       hdr.dest == self,
                       HMAC verify ok
                       SosState ACKED
                       notify ACK_FEED
3. ◄── ACK_FEED      ◄─
4. UI: "land received"
   LED green
```

### Joiner SOS fallback (out of BLE range)

```
1. Joiner taps SOS
2. App BLE-scans for boat; no match within 5 s
3. Fallback: existing Supabase RPC broadcast_sos(lat, lon)
4. Backend writes sos_signals with origin='phone_direct'
5. Owner relay path (existing): owner app sees sos_signals row → BLE SOS_TRIGGER to device
```

### Crew membership flow

1. Owner: Settings → Show QR.
2. Joiner: Scan QR → app calls `joinBoatByQR()` → backend writes `boat_members(boat_id, user_id, role='crew')`.
3. App immediately calls `get_crew_token(boat_id)` → backend returns `crew_token` to verified member.
4. App caches token in `flutter_secure_storage`.
5. On next BLE proximity: connect, AUTH handshake with `crew_token`, AUTH_STATUS = CREW.

Crew rotation on removal: deferred to v2 (document as known gap).

## Backend Integration

### ChirpStack codec (Application Server, JS)

Decodes mesh frame headers and extracts payload. Does **not** verify HMAC (secrets stay server-side). Codec output is opaque base64 of frame bytes plus parsed header fields.

### Supabase Edge function `mesh-decoder`

Path: `supabase/functions/mesh-decoder/index.ts`. ChirpStack HTTP integration POSTs uplinks here. Flow:

```
1. Parse frame, validate magic/ver/type, CRC.
2. Lookup boat by mesh_src_id; get hmac_secret.
3. If type in {SOS, ACK, CANCEL}: verify HMAC (consteq).
4. Verify ts freshness (±300 s); verify seq progression.
5. Dispatch by type:
     POS    → INSERT boat_logs
     SOS    → INSERT sos_signals ON CONFLICT (boat_id, mesh_seq) DO NOTHING
              → trigger downlink ACK via ChirpStack REST
     CANCEL → UPDATE sos_signals SET status='canceled'
6. Return 200 OK.
```

Idempotent on retries (dedup at SQL level).

### Schema migration `supabase_schema-v10.sql`

```sql
ALTER TABLE boats
  ADD COLUMN mesh_src_id INTEGER UNIQUE
    CHECK (mesh_src_id > 0 AND mesh_src_id < 65535),
  ADD COLUMN hmac_secret BYTEA,
  ADD COLUMN crew_token BYTEA,
  ADD COLUMN dev_eui BYTEA,
  ADD COLUMN last_sos_seq INTEGER DEFAULT 0
    CHECK (last_sos_seq >= 0 AND last_sos_seq <= 65535),
  ADD COLUMN relay_mode BOOLEAN DEFAULT FALSE,
  ADD COLUMN unpaired_at TIMESTAMPTZ;

-- Short numeric handle for over-the-air mesh packets (u16 fits 2 bytes)
ALTER TABLE profiles
  ADD COLUMN user_short_id INTEGER UNIQUE
    CHECK (user_short_id > 0 AND user_short_id < 65535);

CREATE OR REPLACE FUNCTION assign_user_short_id() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_short_id IS NULL THEN
    SELECT COALESCE(MAX(user_short_id), 0) + 1
      INTO NEW.user_short_id FROM profiles;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_assign_short_id
BEFORE INSERT ON profiles
FOR EACH ROW EXECUTE FUNCTION assign_user_short_id();

ALTER TABLE sos_signals
  ADD COLUMN origin TEXT NOT NULL DEFAULT 'phone_direct'
    CHECK (origin IN ('mesh', 'phone_direct')),
  ADD COLUMN trigger_user_short_id INTEGER REFERENCES profiles(user_short_id),
  ADD COLUMN trigger_user_id UUID REFERENCES profiles(id),
  ADD COLUMN mesh_seq INTEGER CHECK (mesh_seq >= 0 AND mesh_seq <= 65535),
  ADD COLUMN mesh_hops SMALLINT,
  ADD COLUMN gateway_boat_id INTEGER REFERENCES boats(mesh_src_id),
  ADD COLUMN ack_status SMALLINT DEFAULT 0,
  ADD COLUMN acked_at TIMESTAMPTZ;

CREATE UNIQUE INDEX sos_dedup ON sos_signals(boat_id, mesh_seq)
  WHERE origin = 'mesh';

CREATE TABLE boat_journey_events (
  id BIGSERIAL PRIMARY KEY,
  boat_id INTEGER NOT NULL REFERENCES boats(id),
  user_id UUID NOT NULL REFERENCES profiles(id),
  action TEXT NOT NULL CHECK (action IN ('start','end')),
  ts TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION get_crew_token(p_boat_id INTEGER)
RETURNS BYTEA LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  caller UUID := auth.uid();
  token BYTEA;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM boat_members
    WHERE boat_id = p_boat_id AND user_id = caller
  ) AND NOT EXISTS (
    SELECT 1 FROM boats WHERE id = p_boat_id AND owner_id = caller
  ) THEN
    RAISE EXCEPTION 'not_a_member';
  END IF;
  SELECT crew_token INTO token FROM boats WHERE id = p_boat_id;
  RETURN token;
END $$;

CREATE OR REPLACE FUNCTION pair_boat(
  p_dev_eui BYTEA,
  p_hmac_secret BYTEA,
  p_crew_token BYTEA,
  p_display_name TEXT
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  caller UUID := auth.uid();
  new_src INTEGER;
BEGIN
  SELECT COALESCE(MAX(mesh_src_id), 0) + 1 INTO new_src FROM boats;
  INSERT INTO boats (owner_id, mesh_src_id, dev_eui, hmac_secret,
                     crew_token, display_name)
  VALUES (caller, new_src, p_dev_eui, p_hmac_secret,
          p_crew_token, p_display_name);
  RETURN new_src;
END $$;

CREATE VIEW boats_public AS
SELECT id, owner_id, mesh_src_id, display_name, village_id,
       created_at, last_sos_seq, relay_mode
FROM boats;

-- Apps must use boats_public; hmac_secret/crew_token accessible only via
-- specific RPCs and service-role (Edge function).
```

Paired revert: `revert_schema-v10.sql` drops the columns/tables/functions/view in reverse order.

### ACK downlink trigger

Trigger on `sos_signals` insert (origin='mesh', ack_status=0) posts a ChirpStack downlink REST call to the gateway-boat that delivered the uplink. Body: base64-encoded AckPkt built in PL/pgSQL using `pgcrypto.hmac()`.

### Realtime channels

| Channel | Source | Subscribers |
|---|---|---|
| `sos_signals` insert | Edge function | Owner CallKit, joiner ACK display, admin dashboard |
| `boat_logs` insert | Edge function | App live boat view |
| `boat_journey_events` insert | RPC on toggle | Audit, admin |

### App changes

**`hardware_service.dart`** (`app/boatnode/lib/services/`):
- Add AUTH_CHALLENGE/RESPONSE flow with `crew_token` or `hmac_secret`.
- Add `triggerSos({userId, reason})` writing SOS_TRIGGER characteristic.
- Add `cancelSos({userId, seq})` writing CANCEL_SOS.
- Add `ackFeedStream` from ACK_FEED notify.

**`sos_service.dart`**:
- `sendSos()` tries BLE first; falls back to `broadcast_sos` RPC on no-BLE.

**`backend_service.dart`**:
- Add `getCrewToken(boatId)` calling `get_crew_token` RPC; cache in secure storage.
- Add `pairBoat({devEui, hmacSecret, crewToken, displayName})` calling `pair_boat` RPC.

**Admin dashboard** (`admin/`):
- Show SOS `origin`, `gateway_boat_id`, `mesh_hops`, `trigger_user_id`.
- "Mark resolved" / "Mark false alarm" buttons → ACK downlink with status=2/3.

## Error Handling & Edge Cases

Selected. Full table in design discussion (preserved in commit history).

### Radio
- RFM95 init fail: LED red triple-blink, retry 3× then reboot.
- LoRaWAN join repeated fail: disable LMIC, mesh-only mode, retry join every 30 min.
- LMIC stuck (>30 s no `EV_TXCOMPLETE`): watchdog forces `LMIC_clrTxData`, retune mesh; requeue SOS.
- Mesh TX timeout: re-arm RX immediately, retry once with 200 ms jitter.
- CRC fail / HMAC fail: silent drop, counter increment, ring-buffer log.

### GPS
- No fix at boot: POS sends `lat=0, lon=0`; backend treats as "no fix".
- Fix lost mid-journey: use last known for 10 min, then `0, 0`.
- No GPS time → cannot HMAC: buffer SOS attempt 30 s waiting; if still no time, use `boot_epoch + millis()/1000` with `flags |= NO_GPS_TIME`.
- GPS module silent: power-cycle pin; after 3 fails mark GPS dead.

### NVS
- `hmac_secret` missing while `paired==true`: mark unpaired, force re-pair (do not invent random secret).
- `mesh_src_id` clash heard: log security event, continue; v2 prompt factory reset.
- NVS write failure: retry once; surface `STORAGE_FAIL` via BLE STATUS.

### BLE
- Phone disconnects mid-SOS: SOS state already ACTIVE; phone reconnects later, reads ACK_FEED.
- Auth handshake >10 s: disconnect.
- 5th connection attempt: rejected (cap = 4).
- Stranger subscribe: no notifications sent.
- Replayed AUTH_RESPONSE: nonce rotation defeats.

### SOS state
- Concurrent crew + owner trigger within 1 s: single SosState; `trigger_user_id` reflects latest.
- Crew cancels different user's SOS: rejected at device.
- ACK for stale seq: ignore.
- ACK with bad HMAC: drop.
- Race between user cancel and backend false-alarm: idempotent.
- Battery <10% mid-SOS: one final attempt, LED red-solid, mesh listen continues, POS stops.

### Time/replay
- `ts` outside window: drop; consistent drift → log "clock_drift".
- `seq` wrap (~35 years at 5 SOS/day): tolerated via mod-2^16 cmp.
- Cold boot resets `seq` to 0: device tracks `last_sos_seq` in NVS to survive reboots.

### Mesh
- Simultaneous SOS broadcasts (collision): RBSF jitter re-randomized on retry.
- ACK arrives after local CANCEL: backend sees CANCEL; device ignores inbound ACK.
- Gateway-boat WAN drops mid-queue: retry; after 5 min broadcast `RELAY_FAIL` flag (best-effort).
- Mesh loop: TTL drop + dedup prevent infinite forwards.

### Battery
- <5 %: stop POS; SOS final-attempt budget.
- <2 %: hard shutdown, NVS `last_shutdown_reason=LOW_BATT`.
- ESP32 thermal >80 °C: reduce TX 14 → 10 dBm, POS interval 300 s; recover at <70 °C.

### Backend
- Duplicate gateway uplink: SQL `ON CONFLICT DO NOTHING`.
- Multiple gateway-boats relay same SOS: first wins; subsequent dropped.
- Edge function timeout: ChirpStack retries; idempotent.
- No gateway available for downlink CANCEL: queue 1 h, then expire + dispatcher alert.

## Testing Strategy

### Layer 1 — Host unit tests (`pio test -e native`)

Targets: `crc16_ccitt`, `mesh_packet build/parse`, `hmac_truncated`, `dedup_cache`, `rbsf_state`, `sos_state`, `ble_acl`, `replay_defense`. Coverage target 90 % line. Run on every push.

### Layer 2 — Single-device bench

Manual + scripted. Tests: boot to first POS, BLE pair flow, auth (owner/crew/stranger), SOS trigger, persistent retry, battery cutoff, journey privacy, watchdog recovery, GPS loss. Pass criteria: all rows pass on 3 separate units.

### Layer 3 — Multi-device system tests

Minimum 4 boat units + 1 ChirpStack gateway + Supabase staging.

- Mesh propagation: single-hop, multi-hop, RBSF suppression, dedup, TTL drop.
- End-to-end SOS: direct gateway, mesh-relayed, no-gateway persistent retry, joiner via BLE, joiner fallback, concurrent SOS, spoofed SOS rejected, replay rejected.
- ACK path: backend ACK reaches originator, multi-status progression, HMAC fail handled.
- Auth + roles: crew add/remove, ACL enforcement, factory reset.
- Power: 7-day battery test, continuous CAD mesh listen, BLE multi-client.
- Failure injection: ChirpStack down, Supabase realtime down, LMIC stuck, mesh radio dies, GPS spoof.

### Test data fixtures

Path: `firmware/test/fixtures/`. Files: `vectors_hmac.json` (RFC 4231), `vectors_crc16.json`, `vectors_packets.bin` (50 frames, valid and tampered), `topology_*.yaml` (multi-device scenarios).

### Acceptance for v1 ship

All Layer 1 green in CI. Layer 2 checklist signed off on 3 units. Layer 3 end-to-end SOS happy path + at least 2 failure scenarios passing. 7-day battery test completed.

## Migration & Rollout

1. Land schema v10 + revert.
2. Implement Edge function `mesh-decoder`; deploy to staging.
3. Implement firmware behind compile flag `MESH_HYBRID=1`; production builds keep `=0` until field tested.
4. Implement Flutter changes behind a feature flag (`features.mesh_via_ble`).
5. Bench tests on 3 units; sign off Layer 2.
6. Field test 4-boat fleet; sign off Layer 3.
7. Backend dual-write: accept both legacy SOS (phone direct) and mesh SOS; admin dashboard differentiates.
8. Flip `MESH_HYBRID=1` for production builds, OTA where supported.
9. Flip Flutter feature flag.

## Open Issues / V2

- Crew token rotation on crew removal.
- HMAC key rotation flow (NVS slot reserved; downlink mechanism deferred).
- ESP32 flash encryption + secure boot for side-channel resistance.
- "Bottle in ocean" long-term store-and-forward across hours.
- Geofence-based POS interval scaling (denser POS near coast, sparse offshore).
- Health telemetry uplink: daily HMAC-fail counters, restart reasons, battery curve.

## References

- Current production firmware: `firmware/src/main.cpp`
- Historical v2 sketch (mesh stub): `firmware/BoatNode_v2_Full.cpp`
- Backend schema: `backend/migrations/supabase_schema-v1..v9.sql`
- Flutter hardware service: `app/boatnode/lib/services/hardware_service.dart`
- Flutter SOS service: `app/boatnode/lib/services/sos_service.dart`
- Brainstorming session: 2026-05-13 with user (Q1–Q8 + protocol approach).

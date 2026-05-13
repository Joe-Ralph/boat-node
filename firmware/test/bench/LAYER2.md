# Layer 2 — single-device bench tests

Run on 3 separate boat units. Each row must pass on all 3 before promotion.

Sniffer: any RFM95 in `MESH_FREQ_MHZ` SF9 BW125 sync-word 0x12 mode (a fourth board running RadioLib RX, or HackRF / RTL-SDR with LoRa decoder). Capture frames hex-dumped over serial.

## Boot + radio

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-01  | Cold boot → first POS over mesh            | Sniffer logs a 46 B frame with magic `0xBA` within 30 s of power-on            |
| B-02  | RFM95 init fail (pull NSS to 3V3)          | LED red triple-blink, reboot after 3rd attempt                                 |
| B-03  | Watchdog recovery on LMIC stuck            | Force LMIC into RX1 timeout; firmware clears state within 30 s and mesh resumes |

## Pairing + identity

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-04  | BLE pair flow                              | App receives `mesh_src_id` via PAIR_FINALIZE, NVS `paired=true`                |
| B-05  | NVS write fail simulation                  | BLE STATUS notifies `STORAGE_FAIL`                                             |
| B-06  | `hmac_secret` never exposed                | BLE read on `HMAC_SECRET` UUID is rejected (no such characteristic published)  |

## BLE auth + ACL

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-07  | Owner AUTH handshake                       | `AUTH_STATUS` read returns tier=OWNER after valid HMAC proof                   |
| B-08  | Crew AUTH handshake                        | Crew with valid `crew_token` reaches tier=CREW                                 |
| B-09  | Stranger denied                            | Unauthenticated client cannot subscribe DATA notifications                     |
| B-10  | Stranger auto-disconnect after 10 s        | Connection drops, slot freed for next client                                   |
| B-11  | 5th BLE connection rejected                | `BLE_MAX_CONN = 4` enforced; 5th attempt declined                              |
| B-12  | Crew tries `SET_CONFIG`                    | Device responds `ACL_DENIED`; characteristic write rejected                    |
| B-13  | Crew tries `CANCEL_SOS` on different user  | Device rejects (owner-or-self only)                                            |

## SOS

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-14  | Button SOS trigger                         | LED red-fast within 200 ms; `SosPkt` visible on sniffer                        |
| B-15  | Joiner SOS via BLE                         | Identical `SosPkt` on-air with `trigger_user_id` = joiner short_id             |
| B-16  | Persistent retry without neighbour ACK     | Retries fire at 0 / 30 / 60 / 120 / 300 s (±2 s)                                |
| B-17  | ACK from backend reaches device            | LED green slow-pulse; `ACK_FEED` notify carries the seq                        |
| B-18  | User cancel during ACTIVE                  | LED off; `CancelPkt` transmitted once                                          |
| B-19  | Battery cutoff at 10 %                     | One final SOS attempt, then POS halts, LED red-solid                           |
| B-20  | Journey privacy override                   | Journey OFF + SOS still transmits at full power                                |

## GPS

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-21  | Cold start no fix                          | POS sends `lat=0, lon=0` for 30 s, then real fix takes over                    |
| B-22  | Fix lost mid-journey                       | Uses last fix for 10 min; reverts to 0,0 after                                  |
| B-23  | SOS without GPS time                       | Buffers attempt 30 s; if still none, uses `boot_epoch + millis/1000` + flag    |

## Power

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-24  | 7-day battery test (typical duty cycle)    | 2× 18650 7 Ah pack ≥ 7 days idle + 2 SOS / day                                  |
| B-25  | Mesh CAD listen idle current               | ≤ 18 mA average over 2 min sample                                              |

## LED card

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-26  | LED pattern matches docs LED reference     | Observed colour/pattern matches `site3d/components/Docs.tsx` card for each forced state |

## Mesh interop

| #     | Test                                       | Pass criteria                                                                  |
|-------|--------------------------------------------|--------------------------------------------------------------------------------|
| B-27  | Two-device dedup                           | B sends POS; B forwards via flood; sniffer sees no third copy from B           |
| B-28  | TTL drop on hops > 4                       | Forced ttl=4, hops=5 → DROP_TTL counter increments                              |
| B-29  | Replay rejected                            | Same SosPkt resent with ts > 300 s old → silent drop                            |

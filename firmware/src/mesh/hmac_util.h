#pragma once
#include <stdint.h>
#include <stddef.h>

// HMAC-SHA256 truncated to first 4 bytes.
// Backed by mbedtls (built into Arduino-ESP32 + linkable host-side).
void hmac_sha256_trunc4(const uint8_t* key,  size_t key_len,
                        const uint8_t* data, size_t data_len,
                        uint8_t out[4]);

// Constant-time compare against expected tag. Returns true iff equal.
bool hmac_sha256_verify_trunc4(const uint8_t* key,  size_t key_len,
                               const uint8_t* data, size_t data_len,
                               const uint8_t tag[4]);

// Full 32-byte HMAC-SHA256. Used by BLE auth which compares 8 bytes
// (BLE proofs are 8 B per spec §"Auth handshake"), not 4 like mesh frames.
void hmac_sha256_full(const uint8_t* key,  size_t key_len,
                      const uint8_t* data, size_t data_len,
                      uint8_t out[32]);

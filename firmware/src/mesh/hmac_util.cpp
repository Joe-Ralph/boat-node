#include "mesh/hmac_util.h"
#include <string.h>
#include "mbedtls/md.h"

void hmac_sha256_trunc4(const uint8_t* key,  size_t key_len,
                        const uint8_t* data, size_t data_len,
                        uint8_t out[4]) {
  uint8_t full[32] = {0};
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (info == nullptr) { memset(out, 0, 4); return; }

  if (mbedtls_md_setup(&ctx, info, /*hmac=*/1) != 0) {
    mbedtls_md_free(&ctx); memset(out, 0, 4); return;
  }
  mbedtls_md_hmac_starts(&ctx, key, key_len);
  mbedtls_md_hmac_update(&ctx, data, data_len);
  mbedtls_md_hmac_finish(&ctx, full);
  mbedtls_md_free(&ctx);
  memcpy(out, full, 4);
}

bool hmac_sha256_verify_trunc4(const uint8_t* key,  size_t key_len,
                               const uint8_t* data, size_t data_len,
                               const uint8_t tag[4]) {
  uint8_t expected[4];
  hmac_sha256_trunc4(key, key_len, data, data_len, expected);
  uint8_t diff = 0;
  for (int i = 0; i < 4; ++i) diff |= (expected[i] ^ tag[i]);
  return diff == 0;
}

void hmac_sha256_full(const uint8_t* key,  size_t key_len,
                      const uint8_t* data, size_t data_len,
                      uint8_t out[32]) {
  memset(out, 0, 32);
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (info == nullptr) return;
  if (mbedtls_md_setup(&ctx, info, /*hmac=*/1) != 0) {
    mbedtls_md_free(&ctx); return;
  }
  mbedtls_md_hmac_starts(&ctx, key, key_len);
  mbedtls_md_hmac_update(&ctx, data, data_len);
  mbedtls_md_hmac_finish(&ctx, out);
  mbedtls_md_free(&ctx);
}

#include "mesh/dedup.h"

bool DedupCache::seen_then_insert(uint16_t src, uint16_t seq, uint8_t type) {
  for (auto& e : ring_) {
    if (e.used && e.src == src && e.seq == seq && e.type == type) return true;
  }
  ring_[head_] = {src, seq, type, /*used=*/1};
  head_ = (head_ + 1) % DEDUP_CACHE_SIZE;
  return false;
}

void DedupCache::clear() {
  for (auto& e : ring_) e = {};
  head_ = 0;
}

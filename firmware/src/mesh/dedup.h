#pragma once
#include <stdint.h>
#include "mesh/constants.h"

// Ring buffer of recently seen (src, seq, type) tuples.
// Used to drop duplicates during mesh flood (RBSF).
class DedupCache {
public:
  // Returns true if (src, seq, type) already present.
  // On miss, inserts it (and may evict the oldest entry) and returns false.
  bool seen_then_insert(uint16_t src, uint16_t seq, uint8_t type);

  void clear();

private:
  struct Entry { uint16_t src; uint16_t seq; uint8_t type; uint8_t used; };
  Entry ring_[DEDUP_CACHE_SIZE] = {};
  uint8_t head_ = 0;
};

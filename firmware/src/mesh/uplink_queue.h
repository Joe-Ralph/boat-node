#pragma once
#include <stdint.h>
#include "mesh/constants.h"

// FSM-4 · LoRaWAN uplink queue (gateway-class boat role).
// Capacity 8. SOS preemption: when full and a new SOS arrives, evict the
// oldest non-SOS frame. When the queue is full of SOS frames, drop non-SOS
// arrivals.

struct UplinkItem {
  uint8_t  type = 0;
  bool     own  = false;
  uint16_t seq  = 0;
  uint8_t  len  = 0;
  uint8_t  payload[60] = {0};
};

class UplinkQueue {
public:
  static constexpr uint8_t CAP = 8;

  bool    enqueue(const UplinkItem& it);
  bool    dequeue(UplinkItem* out);
  bool    peek(UplinkItem* out) const;
  bool    is_empty() const { return size_ == 0; }
  uint8_t size()     const { return size_; }

private:
  UplinkItem ring_[CAP];
  uint8_t    head_ = 0;
  uint8_t    tail_ = 0;
  uint8_t    size_ = 0;

  void erase_at(uint8_t idx);
};

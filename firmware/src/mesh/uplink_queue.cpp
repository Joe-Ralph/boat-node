#include "mesh/uplink_queue.h"

bool UplinkQueue::enqueue(const UplinkItem& it) {
  if (size_ < CAP) {
    ring_[tail_] = it;
    tail_ = (tail_ + 1) % CAP;
    ++size_;
    return true;
  }
  // Full. Only SOS may preempt.
  if (it.type != PKT_SOS) return false;

  for (uint8_t i = 0; i < size_; ++i) {
    const uint8_t idx = (head_ + i) % CAP;
    if (ring_[idx].type != PKT_SOS) {
      erase_at(idx);
      ring_[tail_] = it;
      tail_ = (tail_ + 1) % CAP;
      ++size_;
      return true;
    }
  }
  return false;     // queue is entirely SOS — drop arrival
}

bool UplinkQueue::peek(UplinkItem* out) const {
  if (size_ == 0) return false;
  *out = ring_[head_];
  return true;
}

bool UplinkQueue::dequeue(UplinkItem* out) {
  if (size_ == 0) return false;
  *out = ring_[head_];
  head_ = (head_ + 1) % CAP;
  --size_;
  return true;
}

void UplinkQueue::erase_at(uint8_t idx) {
  // Shift entries [head_..idx-1] forward by 1 to fill the hole, then advance head_.
  while (idx != head_) {
    const uint8_t prev = (idx + CAP - 1) % CAP;
    ring_[idx] = ring_[prev];
    idx = prev;
  }
  head_ = (head_ + 1) % CAP;
  --size_;
}

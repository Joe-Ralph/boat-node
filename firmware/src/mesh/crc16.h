#pragma once
#include <stdint.h>
#include <stddef.h>

// CRC16-CCITT (poly 0x1021, init 0xFFFF, no reflection, no final XOR).
// Standard fixture: crc16_ccitt("123456789", 9) == 0x29B1.
uint16_t crc16_ccitt(const uint8_t* data, size_t len, uint16_t init = 0xFFFF);

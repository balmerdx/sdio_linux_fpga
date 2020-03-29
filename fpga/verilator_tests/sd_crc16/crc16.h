#pragma once
#include <stdint.h>
#include <vector>

inline uint16_t crc16_1bit(uint16_t prev, bool bit)
{
    uint16_t inv = (bit?1:0) ^ ((prev>>15)&1);

    return ((prev<<1)|inv)^((inv<<5)|(inv<<12));
}

inline uint16_t crc16_4bit(uint16_t prev, uint8_t byte)
{
    for(int i=0; i<4; i++)
        prev = crc16_1bit(prev, (byte&(1<<i))?true:false);
    return prev;
}


inline uint16_t crc16_8bit(uint16_t prev, uint8_t byte)
{
    for(int i=0; i<8; i++)
        prev = crc16_1bit(prev, (byte&(1<<i))?true:false);
    return prev;
}

inline uint16_t crc16(const std::vector<uint8_t>& bytes)
{
    uint16_t prev = 0;
    for(uint8_t b : bytes)
        prev = crc16_8bit(prev, b);
    return prev;
}

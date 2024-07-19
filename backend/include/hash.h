//
// Created by r53wang on 4/17/23.
//

#ifndef semalloc_HASH_H
#define semalloc_HASH_H
#include <cinttypes>

static inline uint16_t hash(uint32_t input) {
    return input & 0xFFFF;
}
#endif //semalloc_HASH_H

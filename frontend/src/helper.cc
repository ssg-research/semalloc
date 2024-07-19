//
// Created by r53wang on 10/23/23.
//
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include "Config.h"

#define CSI_RH_BITMASK          0x3FFF000000000000UL
#define CSI_RH_LENGTH 14
#define CSI_RH_OFFSET 48

uint64_t CSSHashFunction(const uint64_t* p, uint64_t n) {
#ifdef STAT
    return 0;
#endif
    uint8_t len = n > CSI_RH_LENGTH / 2 ? CSI_RH_LENGTH / 2 : n;
    uint64_t h = 0;
    for (int i = 0; i < len; i++) {
        h = h << 2;
        h += (p[i] >> 6) & 0x3;
    }
    return (h << 48) & CSI_RH_BITMASK;
}


void CSSSaveTrack(uint64_t i, uint64_t* value, uint64_t** debugArray, char* func1, char* func2) {
//    if (*value > 0xFFFFUL) {
//        fprintf(stderr, "[CSTV_EXP] CSTV overflow to %zu in function %s before calling %s\n", *value, func1, func2);
//        exit(1);
//    }

    ((uint64_t*)debugArray)[i] = *value;
    fprintf(stderr, "[SET_CSTV] Set value %zu in function %s before calling %s\n", *value, func1, func2);
}


void CSSCheckTrack(uint64_t i, uint64_t* value, uint64_t** debugArray, char* func1, char* func2) {
    if (((uint64_t*)debugArray)[i] != *value) {
        fprintf(stderr, "[CSTV_NO_MATCH] Expect %zu, get %zu in function %s after calling %s\n",
                *value, ((uint64_t*)debugArray)[i], func1, func2);
        exit(1);
    } else {
        fprintf(stderr, "[CSTV_MATCH] Get %zu in function %s after calling %s\n",
                *value, func1, func2);
    }
}


static void CSSPrintTrack(uint64_t value, char* s1, char* func1, char* func2) {

}

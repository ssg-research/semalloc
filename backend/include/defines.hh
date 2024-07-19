//
// Created by r53wang on 3/23/23.
//

#ifndef BACKEND_DEFINES_HH
#define BACKEND_DEFINES_HH
#include <cinttypes>
#include <cstring>
#include <cstdlib>
#include <map>
#include "pthread.h"
#include <malloc.h>
#include <sys/mman.h>

// #define INFO2
//  #define DEBUG
//#define ENABLE_ASSERTS
#define STAT

#define LAZY_LOOP
#define LAZY_OCCUR 2
#include "debug.hh"

/// global definitions

#define MAX_THREAD 128

#define PAGE_SIZE_BIT 12
#define PAGE_SIZE (1 << PAGE_SIZE_BIT)
#define MIN_BAG_SIZE 16

#define GLOBAL_BAG_N 14
#define BAG_THRESHOLD (MIN_BAG_SIZE << (GLOBAL_BAG_N - 1))
#define GLOBAL_SINGLE_BIBOP_SIZE (1UL << 32)
#define GLOBAL_BIBOP_SIZE (GLOBAL_BAG_N * GLOBAL_SINGLE_BIBOP_SIZE)

#define INDIVIDUAL_BIBOP_MAX_N (1 << 16)
#define INDIVIDUAL_DATA_POOL_CAPACITY 16
#define INDIVIDUAL_BIBOP_SIZE (1UL << 31)

#define METADATA_POOL_SIZE (2UL << 32)

#define INDIVIDUAL_DATA_POOL_SIZE (INDIVIDUAL_BIBOP_SIZE * INDIVIDUAL_DATA_POOL_CAPACITY)
#define INDIVIDUAL_DATA_POOL_N (1 << 14)

// CSI
#define REAL_SIZE_BIT_MASK      0x00000000FFFFFFFFUL
#define GET_REAL_SIZE(size) (size & REAL_SIZE_BIT_MASK)
#define CSI_BIT_MASK            0x3FFFFFFF00000000UL
#define CSI_RH_BITMASK          0x3FFF000000000000UL
#define CSI_LOOP_BIT_MASK       0x4000000000000000UL
#define CSI_HUGE_SIZE_BIT_MASK  0x8000000000000000UL
#define CSI_HUGE_SIZE_SIZE_MASK 0x7FFFFFFFFFFFFFFFUL

// memory release
#define REGULAR_MEMORY_RELEASE
#define AGGRESSIVE_MEMORY_RELEASE
#define MEMORY_RELEASE_THRESHOLD (8 * 4096)

#define LOG2(x) ((unsigned) (8*sizeof(unsigned long long) - __builtin_clzll((x - 1))))

enum BIBOP_TYPE {
    UNDEFINED,
    GLOBAL_BIBOP,
    INDIVIDUAL_BIBOP
};

#endif //BACKEND_DEFINES_HH

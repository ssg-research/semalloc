//
// Created by r53wang on 4/18/23.
//

#ifndef semalloc_HELPEROBJECTS_HH
#define semalloc_HELPEROBJECTS_HH
#include "defines.hh"
#include <atomic>

struct HugeHeader {
    size_t size; // 8
    char unused[7]; // 7
    unsigned char controlByte; // 0: regular, 1: huge 00000000; 00000001

    void setHuge() {
        controlByte ^= (unsigned char)0x01;
    }

    bool isHuge() {
        return controlByte & (unsigned char)0x01;
    }
};

struct RegularHeader {
    void* bibop; // 8
    uint32_t memalign_offset; // 4
    uint16_t thread_id; // 2
    // .....ABT
    // A: 0 not allocated; 1 allocated
    // B: 0 individual; 1 global
    // T: 0 regular; 1 huge
    unsigned char controlByte;

    void setRegular() {
        controlByte &= (unsigned char)0xFE;
    }

    bool isRegular() {
        return !(controlByte & (unsigned char)0x01);
    }

    void setGlobal() {
        controlByte ^= (unsigned char)0x02;
    }

    void setIndividual() {
        controlByte &= (unsigned char)0xFD;
    }

    void setAllocation() {
        controlByte ^= (unsigned char)0x04;
    }

    void setFree() {
        controlByte &= (unsigned char)0xFB;
    }

    bool isAllocation() {
        return controlByte & (unsigned char)0x04;
    }
};

// size 16
struct ObjectHeader {
    union {
        HugeHeader hugeHeader;
        RegularHeader regularHeader;
    };
};

#define HEADER_SIZE (sizeof(ObjectHeader))

struct ListElement{
    ListElement* nxt;
};


#endif
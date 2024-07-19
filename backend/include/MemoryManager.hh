//
// Created by r53wang on 3/23/23.
//

#ifndef semalloc_MEMORYMANAGER_HH
#define semalloc_MEMORYMANAGER_HH

#include "BIBOP.hh"
#include "defines.hh"
#include "hash.h"
#include "MemoryPool.hh"
#include "HelperObjects.hh"
#include "GlobalBIBOP.hh"
#include "IndividualBIBOP.hh"
#include <atomic>


class MemoryManager {
private:
    MemoryPool* individualDataPool[INDIVIDUAL_DATA_POOL_N]; // all data will be allocated from the dataPool
#ifdef LAZY_LOOP
    struct lazy_element_t {
        size_t CSI;
        uint8_t occurCount;
    };
    lazy_element_t lazyIdentifiers[INDIVIDUAL_DATA_POOL_N << 8];
#endif
    MemoryPool* metadataPool; // all metadata will be allocated from the metadataPool
    BIBOP* globalBIBOP; // a global BIBOP handles all one-time allocation

    struct IndividualBIBOP_c_t {
        IndividualBIBOP* ptr[GLOBAL_BAG_N];
        size_t CSI;
    };

    size_t individualDatPoolBump;
    IndividualBIBOP_c_t individualBIBOP[INDIVIDUAL_BIBOP_MAX_N]; // individual BIBOPs each for one loop

    // free list
    std::atomic<ListElement*> FreeList;

    uint16_t thread_id;
#ifdef DEBUG
    size_t huge_count;
#endif

    IndividualBIBOP* getIndividualBIBOPbyCSI(size_t CSI, size_t objectSize);
    GlobalBIBOP* AllocateGlobalBIBOP();
    IndividualBIBOP* AllocateIndividualBIBOP(size_t objectSize);

    static void* allocateHuge(size_t size);
    void handleFreeList();

    bool tryPutToLazyPool(size_t CSI);
    void* acquireIndividualDataPool();

public:
    void* mallocMemory(size_t size);
    void* mallocMemory(size_t realSize, size_t CSI, bool inLoop);
    void freeRegularMemory(void* ptr);
    void freeOtherThreadMemory(void* ptr);

    void InitMemoryManager(uint16_t _thread_id) {
        this->individualDataPool[0] = MemoryPool::AllocateMemoryPool(INDIVIDUAL_DATA_POOL_SIZE);
        this->metadataPool = MemoryPool::AllocateMemoryPool(METADATA_POOL_SIZE);

        globalBIBOP = this->AllocateGlobalBIBOP();
        memset(individualBIBOP, 0xFF, sizeof individualBIBOP);

        this->individualDatPoolBump = 0;
        this->FreeList = nullptr;
        this->thread_id = _thread_id;
    }

public:
    static MemoryManager* AllocateMemoryManager(uint16_t _thread_id) {
        auto mm = (MemoryManager*)mmap(nullptr, sizeof(MemoryManager), PROT_READ | PROT_WRITE,
                                                 MAP_PRIVATE | MAP_ANON, -1, 0);
        mm->InitMemoryManager(_thread_id);
        return mm;
    }

    static inline void freeHugeMemory(void *ptr) {
        auto* header = (HugeHeader*)((uint64_t)ptr - HEADER_SIZE);
        auto* addr = (void*)((uint64_t)ptr - PAGE_SIZE);
        munmap(addr, header->size + PAGE_SIZE);
    }

    static inline size_t getHugeSize(void *ptr) {
        auto* header = (HugeHeader*)((uint64_t)ptr - HEADER_SIZE);
        return header->size;
    }

    static inline size_t getRegularSize(void* ptr) {
        auto* header = (RegularHeader*)((uint64_t)ptr - HEADER_SIZE);
        if (!header->isRegular()) {
            auto* bibop = (SingleBIBOP*)header->bibop;
            return bibop->getObjectSize();
        } else {
            auto* bibop = (IndividualBIBOP*)header->bibop;
            return bibop->getObjectSize();
        }
    }
};

#endif //semalloc_MEMORYMANAGER_HH

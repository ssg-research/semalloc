//
// Created by r53wang on 4/17/23.
//

#ifndef semalloc_MEMORYPOOL_HH
#define semalloc_MEMORYPOOL_HH
#include "defines.hh"

class MemoryPool {
private:
    void* baseMemory;
    void* bumpMemory;
    void* boundaryMemory;
public:
    void* allocateMemory(size_t size);
    void* getPoolBase();
    void* getBumpMemory();

    static MemoryPool* AllocateMemoryPool(size_t InitSize) {
        Debug("Init pool with size %zu\n", InitSize);
        auto mp = (MemoryPool*)mmap(nullptr, sizeof(MemoryPool), PROT_READ | PROT_WRITE,
                                       MAP_PRIVATE | MAP_ANON, -1, 0);
        mp->baseMemory = mmap(nullptr, InitSize, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANON, -1, 0);

        mp->bumpMemory = mp->baseMemory;
        mp->boundaryMemory = (void*)((size_t)mp->baseMemory + InitSize);
        Debug("Init pool with base: %p, boundary: %p\n", mp->baseMemory, mp->boundaryMemory);
        return mp;
    }

};


#endif //semalloc_MEMORYPOOL_HH

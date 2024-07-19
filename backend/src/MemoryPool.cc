//
// Created by r53wang on 4/17/23.
//

#include "MemoryPool.hh"
void* MemoryPool::allocateMemory(size_t size) {
    void* allocatedMemory = this->bumpMemory;
    this->bumpMemory = (void*)((size_t)this->bumpMemory + size);

    if ((size_t)this->bumpMemory > (size_t)this->boundaryMemory) {
        Debug("Allocation exceeds the maximum pool size. Need %zu, need extra %zu\n",
              size, (size_t)this->bumpMemory - (size_t)this->baseMemory);
        this->bumpMemory = (void*)((size_t)this->bumpMemory - size);
        return nullptr;
    }
    Debug("Allocated to %p\n", allocatedMemory);
    return allocatedMemory;
}


void* MemoryPool::getBumpMemory() {
    return this->bumpMemory;
}


void* MemoryPool::getPoolBase() {
    return this->baseMemory;
}
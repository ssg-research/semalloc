//
// Created by r53wang on 4/4/23.
//
#include "SingleBIBOP.hh"

void *SingleBIBOP::allocateObject() {
    if (freeList.nxt) {
        node* tmp = freeList.nxt;
        freeList.nxt = freeList.nxt->nxt;
        return tmp;
    } else {
        Debug("bump: %p\n", (void*)bump);
        void* tmp = (void*)bump;
        bump += objectSize;
        Debug("Object allocate to %p\n", tmp);
        if (bump - base >= capacity) {
            Debug("Insufficient memory for size: %zu\n", objectSize);
            return nullptr;
        }
        return tmp;
    }
}

void SingleBIBOP::freeObject(void *ptr) {
    auto* convertedPtr = (node*)ptr;
    convertedPtr->nxt = freeList.nxt;
    freeList.nxt = convertedPtr;
#ifdef REGULAR_MEMORY_RELEASE
    auto size = this->getObjectSize();

    if (size >= MEMORY_RELEASE_THRESHOLD) {
        madvise((void*)((uint64_t)ptr + HEADER_SIZE), (size >> PAGE_SIZE_BIT) << PAGE_SIZE_BIT, MADV_DONTNEED);
    }
#endif
}

void SingleBIBOP::ExtendSingleBIBOP(uint64_t _base, size_t _capacity) {
    bump = _base;
    base = _base;
    capacity = _capacity;
}

size_t SingleBIBOP::getObjectSize() {
    return this->objectSize- HEADER_SIZE;
}

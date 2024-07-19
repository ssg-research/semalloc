//
// Created by r53wang on 3/23/23.
//
#include "semalloc.hh"
#include "threads.h"

MemoryManager* globalMemoryManager[MAX_THREAD];
__thread size_t tid;
__thread size_t thread_id;
std::atomic<size_t> thread_bump;

#ifdef STAT
    size_t* n_malloc;
    size_t* n_individual_pool;
    size_t* n_individual_allocation;
    size_t* s_lazy_memory;
    size_t* s_global_memory;
    size_t* s_rec_memory;
#endif

void* css_malloc(size_t size) {
    Debug("enter malloc %zu\n", size);
    if (tid != get_thread_id()) {
        Debug("no manager at thread %zx\n", get_thread_id());
        init_thread();
    }

    void* ptr = globalMemoryManager[thread_id]->mallocMemory(size);
    Debug("ptr: %p, size: %zu, thread %zu\n", ptr, size, thread_id);
    return ptr;
}

void css_free(void* ptr) {
    if (tid != get_thread_id()) {
        Debug("no manager at %zu\n", get_thread_id());
        init_thread();
    }
    Debug("ptr: %p thread %zu\n", ptr, thread_id);
    if (ptr == nullptr) {
        return;
    }

    // huge
    auto* hugeHeader = (HugeHeader*)((uint64_t)ptr - HEADER_SIZE);
    if (hugeHeader->isHuge()) {
        MemoryManager::freeHugeMemory(ptr);
        return;
    }

    // current thread
    auto* regularHeader = (RegularHeader*)((uint64_t)ptr - HEADER_SIZE);
    if (regularHeader->thread_id == thread_id) {
        globalMemoryManager[thread_id]->freeRegularMemory(ptr);
        return;
    }

    // other thread
    globalMemoryManager[regularHeader->thread_id]->freeOtherThreadMemory(ptr);
}

void *css_realloc(void *ptr, size_t size) {
    Debug("realloc: %p, %zu\n", ptr, size);
    if (tid != get_thread_id()) {
        Debug("no manager at %zu\n", get_thread_id());
        init_thread();
    }

    if (ptr == nullptr) {
        void *newPtr = globalMemoryManager[thread_id]->mallocMemory(size);
        Debug("Empty old ptr, allocated to %p\n", newPtr);
        return newPtr;
    }

    if (size == 0) {
        css_free(ptr);
        return nullptr;
    }

    auto* hugeHeader = (HugeHeader*)((uint64_t)ptr - HEADER_SIZE);
    auto* regularHeader = (RegularHeader*)((uint64_t)ptr - HEADER_SIZE);

    size_t oldSize = css_malloc_usable_size(ptr);
    size_t realSize = GET_REAL_SIZE(size);
    Debug("Real size: %zu, old size: %zu\n", realSize, oldSize);
    if (realSize <= oldSize) {
        return ptr;
    }

    void* newObject = globalMemoryManager[thread_id]->mallocMemory(size);
    memcpy(newObject, ptr, oldSize);

    // huge
    if (hugeHeader->isHuge()) {
        MemoryManager::freeHugeMemory(ptr);
        Debug("Allocated to %p, oldSize %zu, newSize %zu\n", newObject, oldSize, realSize);
        return newObject;
    }

    // current thread
    if (regularHeader->thread_id == thread_id) {
        globalMemoryManager[thread_id]->freeRegularMemory(ptr);
        Debug("Allocated to %p, oldSize %zu, newSize %zu\n", newObject, oldSize, realSize);
        return newObject;
    }

    // other thread
    globalMemoryManager[regularHeader->thread_id]->freeOtherThreadMemory(ptr);
    Debug("Allocated to %p, oldSize %zu, newSize %zu\n", newObject, oldSize, realSize);
    return newObject;
}

void *css_calloc(size_t nmemb, size_t size) {
    Debug("calloc a: %zu, b: %zu\n", nmemb, size);
    size_t realSize = GET_REAL_SIZE(size);
    size_t CSI = (size & CSI_BIT_MASK) >> 32;

    Debug("calloc a: %zu, b: %zu\n", nmemb, realSize);
    auto allocatedMemory = globalMemoryManager[thread_id]->mallocMemory(nmemb * realSize, CSI, size & CSI_LOOP_BIT_MASK);
    memset(allocatedMemory, 0, nmemb * realSize);

    Debug("calloc allocated to %p\n", allocatedMemory);
    return allocatedMemory;
}

void*css_memalign(size_t alignment, size_t size) {
    Debug("memalign align: %zu, size: %zu\n", alignment, size);
    if (alignment & (alignment - 1)) {
        Error("Invalid alignment: %zu\n", alignment);
        exit(-1);
    }

    size_t realSize = GET_REAL_SIZE(size);
    size_t CSI = (size & CSI_BIT_MASK) >> 32;

    size_t newSize = (realSize + HEADER_SIZE) / alignment * alignment + 2 * alignment;
    void* addr = globalMemoryManager[thread_id]->mallocMemory(newSize, CSI, size & CSI_LOOP_BIT_MASK);
    Debug("realSize: %zu, alignment: %zu, newSize: %zu, addr: %p\n", realSize, alignment, newSize, addr);
    if ((uint64_t)addr % alignment == 0) {
        return addr;
    }

    auto* oldHeader = (RegularHeader*)((uint64_t)addr - HEADER_SIZE);
    auto* oldBIBOP = oldHeader->bibop;

    void* newAddr = (void*)((uint64_t)addr / alignment * alignment + alignment);
    uint32_t offset = (uint64_t)newAddr - (uint64_t)addr;
    auto* newHeader = (RegularHeader*)((uint64_t)newAddr - HEADER_SIZE);

    newHeader->thread_id = thread_id;
    newHeader->bibop = oldBIBOP;
    newHeader->memalign_offset = offset;
    newHeader->controlByte = oldHeader->controlByte;
    newHeader->setAllocation();
    oldHeader->setFree();

    Debug("Allocated to %p\n", newAddr);
    return newAddr;
}

int css_posix_memalign(void** ptr, size_t a, size_t b) {
    void* tmp = css_memalign(a, b);
    *ptr = tmp;
    return 0;
}

void* css_aligned_alloc(size_t a, size_t b) {
    return css_memalign(a, b);
}


size_t css_malloc_usable_size(void* ptr) {
    auto* hugeHeader = (HugeHeader*)((uint64_t)ptr - HEADER_SIZE);

    size_t size;
    if (hugeHeader->isHuge()) {
        size = MemoryManager::getHugeSize(ptr);
    } else {
        size = MemoryManager::getRegularSize(ptr);
    }

    return size;
}
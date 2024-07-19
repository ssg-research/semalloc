//
// Created by r53wang on 3/23/23.
//

#include "MemoryManager.hh"

#ifdef STAT
extern size_t* n_malloc;
extern size_t* n_individual_pool;
extern size_t* n_individual_allocation;
extern size_t* s_rec_memory;
extern size_t* s_lazy_memory;
extern size_t* s_global_memory;
#endif

void *MemoryManager::mallocMemory(size_t size) {
    this->handleFreeList();
    if (size & CSI_HUGE_SIZE_BIT_MASK) {
        void* ptr = MemoryManager::allocateHuge(size & CSI_HUGE_SIZE_SIZE_MASK);
        Info2("Huge allocated to %p\n", ptr);
        return ptr;
    }

    size_t realSize = GET_REAL_SIZE(size);
    Debug("Real size: %zu\n", realSize);
    if (realSize == 0) {
        return nullptr;
    }

    if (realSize >= BAG_THRESHOLD) {
        return MemoryManager::allocateHuge(realSize);
    }
#ifdef STAT
    *n_malloc += 1;
#endif
    size_t CSI = (size & CSI_BIT_MASK) >> 32;
#ifdef STAT
    Error("CSI>>>>>>>> %zu", CSI);
#endif
    if ((size & CSI_LOOP_BIT_MASK) && (!tryPutToLazyPool(CSI))) {
        // in the loop, we need to find the corresponding BIBOP
        Info2("size %ld, CSI %zu Loop\n", realSize, CSI);

        IndividualBIBOP* currentBIBOP = getIndividualBIBOPbyCSI(CSI, realSize);
        void* ptr = currentBIBOP->allocateObject();
        Info2("Allocated to %p\n", ptr);

        if (ptr == nullptr) {
            Debug("Need to extend BIBOP: %p\n", currentBIBOP);
            void* chunk = this->acquireIndividualDataPool();
            currentBIBOP->ExtendSingleBIBOP((uint64_t)chunk, INDIVIDUAL_BIBOP_SIZE);
            ptr = currentBIBOP->allocateObject();
            Info2("Allocated to %p\n", ptr);
        }

        void* data = (void*)((uint64_t)ptr + HEADER_SIZE);
        auto* header = (RegularHeader*)ptr;

        header->thread_id = thread_id;
        header->bibop = currentBIBOP;
        header->setRegular();
        header->setIndividual();
        header->setAllocation();
        header->memalign_offset = 0;
#ifdef STAT
        *n_individual_allocation += 1;
        *s_rec_memory += realSize + 16;
#endif
        return data;
    } else {
        // not in loop, we don't need to allocate the identifier, just go ahead and allocate
        Info2("size %ld, CSI %ld NLoop\n", realSize, CSI);
        SingleBIBOP* targetBIBOP = *(globalBIBOP->size2BIBOP(realSize));
        void* ptr = targetBIBOP->allocateObject();
        Info2("Allocated to %p\n", ptr);

        if (ptr == nullptr) {
            Debug("Need to extend Global BIBOP: %p\n", globalBIBOP);
            void* chunk = this->acquireIndividualDataPool();
            targetBIBOP->ExtendSingleBIBOP((uint64_t )chunk, INDIVIDUAL_BIBOP_SIZE);
            ptr = targetBIBOP->allocateObject();
            Info2("Allocated to %p\n", ptr);
        }

        void* data = (void*)((uint64_t)ptr + HEADER_SIZE);
        auto* header = (RegularHeader*)ptr;

        header->thread_id = thread_id;
        header->bibop = targetBIBOP;
        header->setRegular();
        header->setGlobal();
        header->setAllocation();
        header->memalign_offset = 0;
#ifdef STAT
        if (size & CSI_LOOP_BIT_MASK) {
            *s_lazy_memory += realSize + 16;
        } else {
            *s_global_memory += realSize + 16;
        }
#endif

        return data;
    }
}

void *MemoryManager::mallocMemory(size_t realSize, size_t CSI, bool inLoop) {
    this->handleFreeList();
    Debug("Real size: %zu\n", realSize);
    if (realSize == 0) {
        return nullptr;
    }
#ifdef STAT
    Error("CSI>>>>>>>> %zu", CSI);
#endif
    if (realSize >= BAG_THRESHOLD) {
        return MemoryManager::allocateHuge(realSize);
    }
#ifdef STAT
    *n_malloc += 1;
#endif

    if (inLoop && (!tryPutToLazyPool(CSI))) {
        // in the loop, we need to find the corresponding BIBOP
        Info2("size %ld, CSI %ld Loop\n", realSize, CSI);

        IndividualBIBOP* currentBIBOP = getIndividualBIBOPbyCSI(CSI, realSize);
        void* ptr = currentBIBOP->allocateObject();
        Info2("Allocated to %p\n", ptr);

        if (ptr == nullptr) {
            Debug("Need to extend BIBOP: %p\n", currentBIBOP);
            void* chunk = this->acquireIndividualDataPool();
            currentBIBOP->ExtendSingleBIBOP((uint64_t)chunk, INDIVIDUAL_BIBOP_SIZE);
            ptr = currentBIBOP->allocateObject();
            Info2("Allocated to %p\n", ptr);
        }

        void* data = (void*)((uint64_t)ptr + HEADER_SIZE);
        auto* header = (RegularHeader*)ptr;

        header->thread_id = thread_id;
        header->bibop = currentBIBOP;
        header->setRegular();
        header->setIndividual();
        header->setAllocation();
        header->memalign_offset = 0;
#ifdef STAT
        *n_individual_allocation += 1;
        *s_rec_memory += realSize + 16;
#endif
        return data;
    } else {
        // not in loop, we don't need to allocate the identifier, just go ahead and allocate
        Info2("size %ld, CSI %ld NLoop\n", realSize, CSI);
        SingleBIBOP* targetBIBOP = *(globalBIBOP->size2BIBOP(realSize));
        void* ptr = targetBIBOP->allocateObject();
        Info2("Allocated to %p\n", ptr);

        if (ptr == nullptr) {
            Debug("Need to extend Global BIBOP: %p\n", globalBIBOP);
            void* chunk = this->acquireIndividualDataPool();
            targetBIBOP->ExtendSingleBIBOP((uint64_t )chunk, INDIVIDUAL_BIBOP_SIZE);
            ptr = targetBIBOP->allocateObject();
            Info2("Allocated to %p\n", ptr);
        }

        void* data = (void*)((uint64_t)ptr + HEADER_SIZE);
        auto* header = (RegularHeader*)ptr;

        header->thread_id = thread_id;
        header->bibop = targetBIBOP;
        header->setRegular();
        header->setGlobal();
        header->setAllocation();
        header->memalign_offset = 0;
#ifdef STAT
        if (inLoop) {
            *s_lazy_memory += realSize + 16;
        } else {
            *s_global_memory += realSize + 16;
        }
#endif

        return data;
    }
}

void MemoryManager::freeRegularMemory(void *ptr) {
    this->handleFreeList();

    Info("ptr %p\n", ptr);
    if (ptr == nullptr) {
        return;
    }

    auto* header = (RegularHeader*)((uint64_t)ptr - HEADER_SIZE);
    if (!header->isAllocation()) {
        Error("Double free ptr: $%p\n", ptr);
        exit(-1);
    }

    auto* data = (void*)((uint64_t)ptr - HEADER_SIZE - header->memalign_offset);

    if (!header->isRegular()) {
        auto* bibop = (GlobalBIBOP*)header->bibop;
        Debug("Global handle %p, at %p\n", ptr, ((GlobalBIBOP*)bibop));
        bibop->freeGlobalObject(data);
    } else {
        auto* bibop = (IndividualBIBOP*)header->bibop;
        Debug("Individual handle %p\n", ptr);
        bibop->freeIndividualObject(data);
    }

    header->setFree();
}


IndividualBIBOP* MemoryManager::getIndividualBIBOPbyCSI(size_t CSI, size_t objectSize) {
    uint16_t BIBOPIndex = hash(CSI); // TODO: possibly a map?
    size_t SizeClassIndex = BIBOP::computeSizeIndex(objectSize);

    for (size_t offset = 0; offset < INDIVIDUAL_BIBOP_MAX_N; offset++) {
        size_t index = (BIBOPIndex + offset) % INDIVIDUAL_BIBOP_MAX_N;
        IndividualBIBOP_c_t *IB = &this->individualBIBOP[index];
    //    Debug("current CSI: %zu, target CSI: %zu, location: %zu\n", IB->CSI, CSI, index);
        // if current is the one we want
        if (IB->CSI == CSI) {
            if ((size_t)IB->ptr[SizeClassIndex] != 0xFFFFFFFFFFFFFFFFUL) {
                Info2("Existing BIBOP with location %zu offset %zu\n", index, offset);
                return IB->ptr[SizeClassIndex];
            } else {
                Info2("New BIBOP with location %zu\n", index);
                IB->ptr[SizeClassIndex] = this->AllocateIndividualBIBOP(MIN_BAG_SIZE << SizeClassIndex);
#ifdef STAT
                *n_individual_pool += 1;
#endif
                return IB->ptr[SizeClassIndex];
            }
        }

        // if current is not allocated
        if (IB->CSI == 0xFFFFFFFFFFFFFFFFUL) {
            Info2("New BIBOP with location %zu\n", index);
            IB->ptr[SizeClassIndex] = this->AllocateIndividualBIBOP(MIN_BAG_SIZE << SizeClassIndex);
            IB->CSI = CSI;
#ifdef STAT
            *n_individual_pool += 1;
#endif
            return IB->ptr[SizeClassIndex];
        }
    }
    Error("BIBOP max reached (max=%d). Cannot allocate a new memory chunk\n", INDIVIDUAL_BIBOP_MAX_N);
    exit(1);
}


GlobalBIBOP* MemoryManager::AllocateGlobalBIBOP(){
    Debug("Allocate BIBOP of size %zx\n", GLOBAL_BIBOP_SIZE);
    auto* ptr = (GlobalBIBOP*)this->metadataPool->allocateMemory(sizeof(GlobalBIBOP));
    Debug("BIBOP to %p\n", ptr);

    ptr->InitGlobalBIBOP();
    Debug("Type is set to %d\n", ptr->bibopType);
    return ptr;
}

void* MemoryManager::acquireIndividualDataPool() {
    void* data = this->individualDataPool[this->individualDatPoolBump]->allocateMemory(INDIVIDUAL_BIBOP_SIZE);
    if (data == nullptr) {
        this->individualDatPoolBump++;
        if (this->individualDatPoolBump >= INDIVIDUAL_DATA_POOL_N) {
            Error("DataPool max reached (max=%d)\n", INDIVIDUAL_DATA_POOL_N);
            exit(1);
        }

        this->individualDataPool[this->individualDatPoolBump] =
                MemoryPool::AllocateMemoryPool(INDIVIDUAL_DATA_POOL_SIZE);
        data = this->individualDataPool[this->individualDatPoolBump]->allocateMemory(INDIVIDUAL_BIBOP_SIZE);
    }

    return data;
}

IndividualBIBOP* MemoryManager::AllocateIndividualBIBOP(size_t objectSize){
    Debug("Allocate BIBOP of size %zx\n", INDIVIDUAL_BIBOP_SIZE);

    auto* ptr = (IndividualBIBOP*)this->metadataPool->allocateMemory(sizeof(IndividualBIBOP));
    Debug("BIBOP to %p\n", ptr);

    void* data = this->acquireIndividualDataPool();
    Debug("Chunk allocated to BIBOP: %p\n", data);

    ptr->InitIndividualBIBOP((uint64_t)data, objectSize, INDIVIDUAL_BIBOP_SIZE);
    Debug("BIBOP base: %p, up to: %lx\n", data, (uint64_t)data + INDIVIDUAL_BIBOP_SIZE);
    return ptr;
}


void *MemoryManager::allocateHuge(size_t size) {
    size_t new_size = (size + PAGE_SIZE - 1) & (~(PAGE_SIZE - 1));

    Debug("New size: %zu\n", new_size + PAGE_SIZE);
    void* addr = mmap(nullptr, new_size + PAGE_SIZE, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);

    if (addr == nullptr) {
        Error("mmap failed %p\n", addr);
        exit(-1);
    }

    void* data = (void*)((uint64_t)addr + PAGE_SIZE);
    auto* header = (HugeHeader*)((uint64_t)data - HEADER_SIZE);
    header->size = new_size;
    header->setHuge();

    Debug("Allocated to %p\n", data);
    return data;
}


void MemoryManager::freeOtherThreadMemory(void *ptr) {
    // convert head to metadata
    auto currentFreeObject = (ListElement*)ptr;

    auto curHead = this->FreeList.load();
    currentFreeObject->nxt = curHead;
    while (!std::atomic_compare_exchange_weak(&(this->FreeList), &curHead, currentFreeObject)) {
        curHead = this->FreeList.load();
        currentFreeObject->nxt = curHead;
    }
    Debug("Now head ptr: %p\n", this->FreeList.load());
}


void MemoryManager::handleFreeList() {
    while (this->FreeList != nullptr) {
        auto currentPtr = this->FreeList.load();
        auto nxt = currentPtr->nxt;

        while (!std::atomic_compare_exchange_weak(&this->FreeList, &currentPtr, nxt)) {
            currentPtr = this->FreeList.load();
            nxt = currentPtr->nxt;
        }

        Debug("Regular ptr: %p\n", currentPtr);
        auto* header = (RegularHeader*)((uint64_t)currentPtr - HEADER_SIZE);
        if (!header->isAllocation()) {
            Error("Double free ptr: $%p\n", currentPtr);
            exit(-1);
        }

        if (!header->isRegular()) {
            auto* bibop = (GlobalBIBOP*)header->bibop;
            bibop->freeGlobalObject(header);
        } else {
            auto* bibop = (IndividualBIBOP*)header->bibop;
            bibop->freeIndividualObject(header);
        }

        Debug("Handle done: %p\n", currentPtr);
        header->setFree();
    }
}

#ifdef LAZY_LOOP
bool MemoryManager::tryPutToLazyPool(size_t CSI) {
    /**
     * Lazy Identifiers:
     *      1: first time seen
     *      0: already exists
     */
    uint16_t BIBOPIndex = hash(CSI); // TODO: possibly a map?
    for (uint32_t i = 0; i < (INDIVIDUAL_DATA_POOL_N << 8); i++) {
        uint32_t index = (i + BIBOPIndex) % (INDIVIDUAL_DATA_POOL_N << 8);
        if (this->lazyIdentifiers[index].CSI == CSI) {
            if (this->lazyIdentifiers[index].occurCount < LAZY_OCCUR) {
                this->lazyIdentifiers[index].occurCount++;
                return true;
            }
            return false;
        }

        if (this->lazyIdentifiers[index].CSI == 0) {
            this->lazyIdentifiers[index].CSI = CSI;
            this->lazyIdentifiers[index].occurCount = 1;
            return true;
        }
    }
    Error("No enough space for CSI: %zu\n", CSI);
    exit(1);
}

#else
bool MemoryManager::tryPutToLazyPool(size_t CSI) {
    return false;
}
#endif

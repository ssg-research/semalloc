//
// Created by r53wang on 6/12/23.
//
#include "GlobalBIBOP.hh"

void GlobalBIBOP::freeGlobalObject(void *ptr) {
    Debug("Enter Global Free %p\n", ptr);

#ifdef REGULAR_MEMORY_RELEASE
    auto* header = (RegularHeader*)ptr;
    auto* bibop = (SingleBIBOP*)header->bibop;
    auto size = bibop->getObjectSize();

    if (size >= MEMORY_RELEASE_THRESHOLD) {
        madvise(header, (size >> PAGE_SIZE_BIT) << PAGE_SIZE_BIT, MADV_DONTNEED);
    }
#endif
}

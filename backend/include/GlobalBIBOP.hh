//
// Created by r53wang on 6/12/23.
//

#ifndef semalloc_GLOBALBIBOP_HH
#define semalloc_GLOBALBIBOP_HH
#include "BIBOP.hh"

class GlobalBIBOP: public BIBOP {
public:
    void InitGlobalBIBOP() {

        for (int i = 0; i < GLOBAL_BAG_N; i++) {
            void* data = mmap(nullptr, GLOBAL_SINGLE_BIBOP_SIZE, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANON, -1, 0);
            objects[i] = SingleBIBOP::AllocateSingleBIBOP(
                    (uint64_t) data, MIN_BAG_SIZE << i, GLOBAL_SINGLE_BIBOP_SIZE);
            Debug("Index: %d, size: %d\n", i, MIN_BAG_SIZE << i);
        }

        bibopType = GLOBAL_BIBOP;
    }

    void freeGlobalObject(void *ptr);
};

#endif //semalloc_GLOBALBIBOP_HH

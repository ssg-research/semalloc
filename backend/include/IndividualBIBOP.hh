//
// Created by r53wang on 6/12/23.
//

#ifndef semalloc_INDIVIDUALBIBOP_HH
#define semalloc_INDIVIDUALBIBOP_HH
#include "BIBOP.hh"

class IndividualBIBOP: public SingleBIBOP {

public:
    void InitIndividualBIBOP(uint64_t _base, size_t _objectSize, size_t _capacity) {
        bump = _base;
        base = _base;
        objectSize = _objectSize + HEADER_SIZE;
        freeList.nxt = nullptr;
        capacity = _capacity;
    }

    void freeIndividualObject(void *ptr);
};


#endif //semalloc_INDIVIDUALBIBOP_HH

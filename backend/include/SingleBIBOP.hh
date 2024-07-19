//
// Created by r53wang on 3/31/23.
//

#ifndef semalloc_SINGLEBIBOP_HH
#define semalloc_SINGLEBIBOP_HH
#include "defines.hh"
#include "HelperObjects.hh"

class SingleBIBOP {
protected:
    struct node {
        node* nxt;
    };

    uint64_t bump;
    uint64_t base;
    size_t objectSize;
    node freeList;
    size_t capacity;

public:
    void* allocateObject();
    void freeObject(void* ptr);
    void ExtendSingleBIBOP(uint64_t _base, size_t _capacity);

    void InitSingleBIBOP(uint64_t _base, size_t _objectSize) {
        bump = _base;
        base = _base;
        objectSize = _objectSize + HEADER_SIZE;
        freeList.nxt = nullptr;
    }

    static SingleBIBOP* AllocateSingleBIBOP(uint64_t _base, size_t _objectSize, size_t capacity) {
        auto sb = (SingleBIBOP*)mmap(nullptr, sizeof(SingleBIBOP), PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANON, -1, 0);
        if (sb == nullptr) {
            Error("No enough memory. Required size: %zu\n", sizeof(SingleBIBOP));
            exit(1);
        }

        sb->InitSingleBIBOP(_base, _objectSize);
        sb->capacity = capacity;
        return sb;
    }

    size_t getObjectSize();

};

#endif //semalloc_SINGLEBIBOP_HH

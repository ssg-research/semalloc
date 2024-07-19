//
// Created by r53wang on 4/4/23.
//
#include "BIBOP.hh"


SingleBIBOP** BIBOP::size2BIBOP(size_t size) {
    auto BIBOPCounter = computeSizeIndex(size);
    Debug("Size %zu, allocated to BIBOP: %lu\n", size, BIBOPCounter);
    return &this->objects[BIBOPCounter];
}

size_t BIBOP::computeSizeIndex(size_t size) {
    if (size <= MIN_BAG_SIZE){
        return 0;
    } else {
        return LOG2(size) - 4;
    }
}

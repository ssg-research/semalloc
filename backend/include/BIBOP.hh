//
// Created by r53wang on 3/23/23.
//

#ifndef semalloc_BIBOP_HH
#define semalloc_BIBOP_HH

#include "defines.hh"
#include "SingleBIBOP.hh"


class BIBOP {
protected:
    SingleBIBOP* objects[GLOBAL_BAG_N];


public:
    SingleBIBOP** size2BIBOP(size_t size);
    BIBOP_TYPE bibopType;

    static size_t computeSizeIndex(size_t size);
};


#endif //semalloc_BIBOP_HH

//
// Created by r53wang on 6/12/23.
//
#include "IndividualBIBOP.hh"

void IndividualBIBOP::freeIndividualObject(void *ptr) {
    Debug("Enter Individual Free %p\n", ptr);
    this->freeObject(ptr);
}
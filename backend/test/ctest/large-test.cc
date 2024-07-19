//
// Created by r53wang on 3/23/23.
//
#include <stdio.h>
#include "semalloc.hh"

void* ptr;

int main() {
    ptr = css_malloc(7200000000UL);
    css_free(ptr);

    printf("%lu\n", sizeof(ObjectHeader));
    return 0;
}
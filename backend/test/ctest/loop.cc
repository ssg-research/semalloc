//
// Created by r53wang on 3/23/23.
//
#include <stdio.h>
#include "semalloc.hh"
void* ptr;

int main() {
    for (int i = 0; i < 10; i++) {
        ptr = css_malloc(16 + i + 0xF000000000000000UL);
        css_free(ptr);
    }
    return 0;
}
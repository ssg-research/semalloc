//
// Created by r53wang on 4/12/24.
//
#include <stdio.h>
#include "semalloc.hh"

void* ptr;

int main() {
    ptr = css_malloc(72UL);
    css_free(ptr);
    css_free(ptr);
    return 0;
}
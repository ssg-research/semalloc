//
// Created by r53wang on 4/29/23.
//
#include "semalloc.hh"
void* ptr;

int main() {
    for (int i = 0; i < 20; i++) {
        ptr = css_realloc(ptr, 16 * i);
    }

    css_free(ptr);
    return 0;
}
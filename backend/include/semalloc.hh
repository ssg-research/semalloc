//
// Created by r53wang on 3/23/23.
//

#ifndef BACKEND_semalloc_HH
#define BACKEND_semalloc_HH

#include "defines.hh"
#include "BIBOP.hh"
#include "MemoryManager.hh"

void* css_malloc(size_t size);

void css_free(void* ptr);

void* css_realloc(void *ptr, size_t size);

void* css_calloc(size_t nmemb, size_t size);

void* css_memalign(size_t alignment, size_t size);

int css_posix_memalign(void**, size_t, size_t);

void* css_aligned_alloc(size_t, size_t);

void semalloc_finalize();

size_t css_malloc_usable_size(void*);

#endif //BACKEND_semalloc_HH

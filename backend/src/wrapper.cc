//
// Created by r53wang on 3/23/23.
//
#ifdef GLIBC_OVERRIDE

#include <stdio.h>
#include "semalloc.hh"
#include <dlfcn.h>

#ifdef STAT
static void __attribute__((destructor))
finalizer(void) {
	semalloc_finalize();
}
#endif

static void* css_valloc(size_t s) {
    fprintf(stderr, "Not supported with css_valloc %zu\n", s);
    return NULL;
}

static void* css_pvalloc(size_t s) {
    fprintf(stderr, "Not supported with css_pvalloc %zu\n", s);
    return NULL;
}

// static void* css_alloca(size_t s) {
//     fprintf(stderr, "Not supported with css_alloca %zu\n", s);
//     return NULL;
// }

static void* (*real_malloc)(size_t) = css_malloc;
static void (*real_free)(void*) = css_free;
static void* (*real_realloc)(void*, size_t) = css_realloc;
static void* (*real_memalign)(size_t, size_t) = css_memalign;
static void* (*real_calloc)(size_t, size_t) = css_calloc;
static void* (*real_valloc)(size_t) = css_valloc;
static void* (*real_aligned_alloc)(size_t, size_t) = css_aligned_alloc;
static void* (*real_pvalloc)(size_t) = css_pvalloc;
// static void* (*real_alloca)(size_t) = css_alloca;
static int (*real_posix_memalign)(void**, size_t, size_t) = css_posix_memalign;
static size_t (*real_malloc_usable_size)(void*) = css_malloc_usable_size;


static void mtrace_init(void)
{
    real_malloc = reinterpret_cast<void*(*)(size_t)>(dlsym(RTLD_NEXT, "malloc"));
    if (NULL == real_malloc) {
        fprintf(stderr, "Error in `dlsym`: %s\n", dlerror());
    }

    real_free = reinterpret_cast<void(*)(void*)>(dlsym(RTLD_NEXT, "free"));
    if (NULL == real_free) {
        fprintf(stderr, "Error in `dlsym`: %s\n", dlerror());
    }

    real_realloc = reinterpret_cast<void*(*)(void*, size_t)>(dlsym(RTLD_NEXT, "realloc"));
    if (NULL == real_realloc) {
        fprintf(stderr, "Error in `dlsym`: %s\n", dlerror());
    }

    real_memalign = reinterpret_cast<void*(*)(size_t, size_t)>(dlsym(RTLD_NEXT, "memalign"));
    if (NULL == real_memalign) {
        fprintf(stderr, "Error in `dlsym`: %s\n", dlerror());
    }

    real_calloc = reinterpret_cast<void*(*)(size_t, size_t)>(dlsym(RTLD_NEXT, "calloc"));
    if (NULL == real_calloc) {
        fprintf(stderr, "Error in `dlsym`: %s\n", dlerror());
    }

    real_malloc_usable_size = reinterpret_cast<size_t(*)(void*)>(dlsym(RTLD_NEXT, "malloc_usable_size"));
    if (NULL == real_malloc_usable_size) {
        fprintf(stderr, "Error in `dlsym`: %s\n", dlerror());
    }

    real_valloc = reinterpret_cast<void*(*)(size_t)>(dlsym(RTLD_NEXT, "valloc"));
    real_aligned_alloc = reinterpret_cast<void*(*)(size_t, size_t)>(dlsym(RTLD_NEXT, "aligned_alloc"));
    real_pvalloc = reinterpret_cast<void*(*)(size_t)>(dlsym(RTLD_NEXT, "pvalloc"));
    real_posix_memalign = reinterpret_cast<int(*)(void**, size_t, size_t)>(dlsym(RTLD_NEXT, "posix_memalign"));
    // real_alloca = reinterpret_cast<void*(*)(size_t)>(dlsym(RTLD_NEXT, "alloca"));
}


void *malloc(size_t size)
{
    if(real_malloc==NULL) {
        mtrace_init();
    }

    void *p = NULL;
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper malloc(%zu) = ", size);
#endif
    p = real_malloc(size);
#ifdef WRAPPER_INFO
    fprintf(stderr, "%p\n ", p);
#endif

    return p;
}

void free(void* ptr)
{
    if(real_free==NULL) {
        mtrace_init();
    }

    void *p = NULL;
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper free(%p)\n", ptr);
#endif
    real_free(ptr);
}


void* realloc(void* ptr, size_t size)
{
    if(real_realloc==NULL) {
        mtrace_init();
    }

    void *p = NULL;
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper realloc(%p, %zu) = ", ptr, size);
#endif
    p = real_realloc(ptr, size);
#ifdef WRAPPER_INFO
    fprintf(stderr, "%p\n ", p);
#endif
    return p;
}

void* memalign(size_t alignment, size_t size)
{
    if(real_memalign==NULL) {
        mtrace_init();
    }

    void *p = NULL;
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper memalign(%zu, %zu) = ", alignment, size);
#endif
    p =  real_memalign(alignment, size);
#ifdef WRAPPER_INFO
    fprintf(stderr, "%p\n ", p);
#endif
    return p;
}

void* calloc(size_t nmemb, size_t size)
{
    if(real_calloc==NULL) {
        mtrace_init();
    }

    void *p = NULL;
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper calloc(%zu, %zu) = ", nmemb, size);
#endif
    p = real_calloc(nmemb, size);
#ifdef WRAPPER_INFO
    fprintf(stderr, "%p\n ", p);
#endif
    return p;
}

void* valloc(size_t s) {
    return css_valloc(s);
}

void* aligned_alloc(size_t s, size_t s2) {
    return css_aligned_alloc(s, s2);
}

void* pvalloc(size_t s) {
    return css_pvalloc(s);
}

// void *alloca(size_t s) {
//     return css_alloca(s);
// }

int posix_memalign(void** ptr, size_t s, size_t s2) {
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper posix_mamalign (%zu, %zu) = ", s, s2);
#endif
    int tmp = css_posix_memalign(ptr, s, s2);
#ifdef WRAPPER_INFO
    fprintf(stderr, "%p\n ", *ptr);
#endif
    return tmp;
}

size_t malloc_usable_size(void *ptr)
{
    if(real_malloc_usable_size==NULL) {
        mtrace_init();
    }

    size_t s = 0;
#ifdef WRAPPER_INFO
    fprintf(stderr, "wrapper malloc_usable_size(%p) = ", ptr);
#endif
    s = real_malloc_usable_size(ptr);
#ifdef WRAPPER_INFO
    fprintf(stderr, "%zu\n ", s);
#endif

    return s;
}

#endif
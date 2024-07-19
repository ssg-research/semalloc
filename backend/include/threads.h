//
// Created by r53wang on 4/24/23.
//

#ifndef semalloc_THREADS_H
#define semalloc_THREADS_H
#include <atomic>
#include "MemoryManager.hh"

extern MemoryManager* globalMemoryManager[MAX_THREAD];
extern std::atomic<size_t> thread_bump;
extern __thread size_t thread_id;
extern __thread size_t tid;

#ifdef STAT
    extern size_t* n_malloc;
    extern size_t* n_individual_pool;
    extern size_t* n_individual_allocation;
    extern size_t* s_lazy_memory;
    extern size_t* s_global_memory;
    extern size_t* s_rec_memory;
#endif

//! Fast thread ID
// https://github.com/mjansson/rpmalloc
inline uintptr_t get_thread_id() {
#if (defined(__GNUC__) || defined(__clang__)) && !defined(__CYGWIN__)
    uintptr_t cur_tid;
#  if defined(__i386__)
    __asm__("movl %%gs:0, %0" : "=r" (cur_tid) : : );
#  elif defined(__x86_64__)
#    if defined(__MACH__)
    __asm__("movq %%gs:0, %0" : "=r" (cur_tid) : : );
#    else
    __asm__("movq %%fs:0, %0" : "=r" (cur_tid) : : );
#    endif
#  elif defined(__arm__)
    __asm__ volatile ("mrc p15, 0, %0, c13, c0, 3" : "=r" (cur_tid));
#  elif defined(__aarch64__)
#    if defined(__MACH__)
    // tpidr_el0 likely unused, always return 0 on iOS
	__asm__ volatile ("mrs %0, tpidrro_el0" : "=r" (cur_tid));
#    else
    __asm__ volatile ("mrs %0, tpidr_el0" : "=r" (cur_tid));
#    endif
#  else
    tid = (uintptr_t)((void*)get_thread_heap_raw());
#  endif
    return cur_tid;
#else
    return (uintptr_t)((void*)get_thread_heap_raw());
#endif
}


void init_thread() {
    size_t currentThreadID = std::atomic_fetch_add_explicit(&thread_bump, 1, std::memory_order_acquire);
    globalMemoryManager[currentThreadID] = MemoryManager::AllocateMemoryManager(currentThreadID);
    thread_id = currentThreadID;
    tid = get_thread_id();

#ifdef STAT
    if (thread_id == 0) {
        n_malloc = (size_t*)mmap(nullptr, PAGE_SIZE, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);
        n_individual_pool = (size_t*)mmap(nullptr, PAGE_SIZE, PROT_READ | PROT_WRITE,
                                          MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);
        n_individual_allocation = (size_t*)mmap(nullptr, PAGE_SIZE, PROT_READ | PROT_WRITE,
                                                MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);
        s_lazy_memory = (size_t*)mmap(nullptr, PAGE_SIZE, PROT_READ | PROT_WRITE,
                                                MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);
        s_global_memory = (size_t*)mmap(nullptr, PAGE_SIZE, PROT_READ | PROT_WRITE,
                                           MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);
        s_rec_memory = (size_t*)mmap(nullptr, PAGE_SIZE, PROT_READ | PROT_WRITE,
                                                MAP_PRIVATE | MAP_ANON |MAP_NORESERVE, -1, 0);

    }
#endif
}

#ifdef STAT
void semalloc_finalize() {
    if (thread_id != 0) {
        return;
    }

    fprintf(stderr, "Number of allocations: %zu\n", *n_malloc);
    fprintf(stderr, "Number of individual pools: %zu\n", *n_individual_pool);
    fprintf(stderr, "Number of individual allocations: %zu\n", *n_individual_allocation + *n_individual_pool);
    fprintf(stderr, "Size of lazy memory: %zu\n", *s_lazy_memory);
    fprintf(stderr, "Size of global memory (note the thread spawn takes space): %zu\n", *s_global_memory);
    fprintf(stderr, "Size recycling memory: %zu\n", *s_rec_memory);
}
#endif

#endif //semalloc_THREADS_H


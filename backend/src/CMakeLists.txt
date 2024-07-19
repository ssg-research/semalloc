cmake_minimum_required(VERSION 3.16)
project(semalloc)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 17)

include_directories(../include/)

option(GLIBC_OVERRIDE ON)
message("override: ${GLIBC_OVERRIDE}")

option(DEBUG OFF)
message("debug: ${DEBUG}")

option(LOG_TO_FILE OFF)
message("log_to_file: ${LOG_TO_FILE}")

option(DEBUG2 OFF)
message("debug2: ${DEBUG2}")

if (CMAKE_SYSTEM_PROCESSOR MATCHES "(x86)|(X86)|(amd64)|(AMD64)")
    message("x86")
    set(CFLAGS  "-Wl,--no-as-needed -O3 -ldl")
else()
    message("arm")
    set(CFLAGS  "-Wl,--no-as-needed -O3 -ldl")
endif()

if (GLIBC_OVERRIDE)
    message("Enable override")
    set(CFLAGS "${CFLAGS} -DGLIBC_OVERRIDE")
endif(GLIBC_OVERRIDE)

if (DEBUG)
    message("Enable debug")
    set(CFLAGS "${CFLAGS} -DDEBUG")
endif(DEBUG)

if (LOG_TO_FILE)
    message("Enable log_to_file")
    set(CFLAGS "${CFLAGS} -DLOG_TO_FILE")
endif(LOG_TO_FILE)

if (DEBUG2)
    message("Enable debug2")
    set(CFLAGS "${CFLAGS} -DDEBUG2")
endif(DEBUG2)

if (CMAKE_SYSTEM_PROCESSOR MATCHES "(x86)|(X86)|(amd64)|(AMD64)")
    set(css-src
            ../include/threads.h
            ../include/semalloc.hh
            ../include/defines.hh
            ../include/MemoryManager.hh
            ../include/BIBOP.hh
            ../include/SingleBIBOP.hh
            ../include/debug.hh
            ../include/MemoryPool.hh
            ../include/hash.h
            ../include/HelperObjects.hh
            ../include/GlobalBIBOP.hh
            ../include/IndividualBIBOP.hh
            SingleBIBOP.cc
            semalloc.cc
            wrapper.cc
            MemoryManager.cc
            BIBOP.cc
            MemoryPool.cc
            GlobalBIBOP.cc
            IndividualBIBOP.cc
            )
else()
    set(css-src
            ../include/threads.h
            ../include/semalloc.hh
            ../include/defines.hh
            ../include/MemoryManager.hh
            ../include/BIBOP.hh
            ../include/SingleBIBOP.hh
            ../include/debug.hh
            ../include/MemoryPool.hh
            ../include/hash.h
            ../include/HelperObjects.hh
            ../include/GlobalBIBOP.hh
            ../include/IndividualBIBOP.hh
            SingleBIBOP.cc
            semalloc.cc
            wrapper.cc
            MemoryManager.cc
            BIBOP.cc
            MemoryPool.cc
            GlobalBIBOP.cc
            IndividualBIBOP.cc
            )
endif()

unset(GLIBC_OVERRIDE CACHE)
unset(DEBUG CACHE)
unset(LOG_TO_FILE CACHE)
unset(DEBUG2 CACHE)

set(CMAKE_C_FLAGS "${CFLAGS}")
set(CMAKE_CXX_FLAGS "${CFLAGS}")

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

add_library(semalloc SHARED ${css-src})



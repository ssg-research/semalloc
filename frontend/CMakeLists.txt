cmake_minimum_required(VERSION 3.5.1)
project(KANALYZER)

set(LT_LLVM_INSTALL_DIR "/data/ruizhe/llvm15/build")
list(APPEND CMAKE_PREFIX_PATH "${LT_LLVM_INSTALL_DIR}/lib/cmake/llvm/")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17 -fpic -g")

#message("${CMAKE_PREFIX_PATH}")
#
include_directories(${LT_LLVM_INSTALL_DIR}/include)
include_directories(external)

link_directories(${LT_LLVM_INSTALL_DIR}/lib)

find_package(LLVM 15 REQUIRED CONFIG PATHS ${LT_LLVM_INSTALL_DIR})

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")
set(CMAKE_CXX_STANDARD 17)

# Set your project compile flags.
# E.g. if using the C++ header files
# you will need to enable C++14 support
# for your compiler.
# Check for C++14 support and set the compilation flag
include(CheckCXXCompilerFlag)

include_directories(SYSTEM ${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

add_subdirectory (src)

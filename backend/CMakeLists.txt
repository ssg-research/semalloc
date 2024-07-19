cmake_minimum_required(VERSION 3.16)
project(semalloc)

enable_testing()
add_subdirectory(src)
#add_subdirectory(monitor)
add_subdirectory(test/ctest)
#add_subdirectory(test/ctest/expect_pass)

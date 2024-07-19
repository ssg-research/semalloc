cmake_minimum_required(VERSION 3.16)
project(semalloc)

set(CMAKE_C_STANDARD 14)
#set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDEBUG")
enable_testing()

include_directories(../../include)

# regular tests
file(GLOB tests "*.cc")
file(GLOB thread_tests "thread_*.cc")
#list(REMOVE_ITEM tests ${thread_tests})

message(STATUS "files: ${tests}")

foreach(test ${tests})
    get_filename_component(test_case ${test} NAME_WLE)
    list(APPEND test_cases ${test_case})
endforeach()

foreach (test_case ${test_cases})
    add_executable(${test_case} ${test_case}.cc)
    target_link_libraries(${test_case} semalloc)
    add_test(${test_case} ${test_case})
endforeach()

# thread tests
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -pthread")

foreach(test ${thread_tests})
    get_filename_component(test_case ${test} NAME_WLE)
    list(APPEND thread_cases ${test_case})
endforeach()

foreach(test ${thread_cases})
    get_filename_component(test_case ${test} NAME_WLE)
    list(APPEND test_cases ${test_case})
endforeach()

foreach (test_case ${thread_cases})
    add_executable(${test_case} ${test_case}.cc)
    target_link_libraries(${test_case} semalloc)
    add_test(${test_case} ${test_case})
endforeach()
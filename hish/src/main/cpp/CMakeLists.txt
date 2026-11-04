cmake_minimum_required(VERSION 3.5.0)
project(hish)

set(CMAKE_CXX_STANDARD 17)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

# QEMU itself (libqemu-system-aarch64.so) is prebuilt and loaded at runtime with dlopen;
# it is placed in hish/libs/<abi>/ by scripts/fetch-hish.ps1.
add_library(hish SHARED hish_napi.cpp)
target_link_libraries(hish PUBLIC libace_napi.z.so libhilog_ndk.z.so)

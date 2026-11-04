# Motionix C++ core — built into the app as libmotionix_core.so.
# Loaded from Dart via dart:ffi (DynamicLibrary.open).
cmake_minimum_required(VERSION 3.22.1)
project(motionix_core LANGUAGES CXX)

add_library(motionix_core SHARED
    src/core_api.cpp
    src/rational.cpp
    src/timecode.cpp
    src/proxy_planner.cpp
    src/project.cpp
)

target_include_directories(motionix_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty
)

target_compile_definitions(motionix_core PRIVATE MX_BUILDING=1)

set_target_properties(motionix_core PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

# -O2 for speed, small code to keep the .so lean on low-RAM devices.
target_compile_options(motionix_core PRIVATE -O2 -fexceptions -ffunction-sections -fdata-sections)
target_link_options(motionix_core PRIVATE -Wl,--gc-sections)

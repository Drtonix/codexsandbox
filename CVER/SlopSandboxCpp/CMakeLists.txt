cmake_minimum_required(VERSION 3.20)
project(SlopSandboxCpp LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Raylib options
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(USE_EXTERNAL_GLFW OFF CACHE BOOL "" FORCE)

# Box2D options
set(BOX2D_BUILD_TESTBED OFF CACHE BOOL "" FORCE)
set(BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)

add_subdirectory(third_party/raylib)
add_subdirectory(third_party/box2d)

add_executable(SlopSandboxCpp
    src/main.cpp
)

target_include_directories(SlopSandboxCpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/box2d/include
)

target_link_libraries(SlopSandboxCpp PRIVATE raylib box2d)

if(APPLE)
    target_link_libraries(SlopSandboxCpp PRIVATE
        "-framework Cocoa"
        "-framework IOKit"
        "-framework CoreVideo"
    )
endif()

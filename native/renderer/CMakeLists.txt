cmake_minimum_required(VERSION 3.16)
project(arboria_native VERSION 7.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ARBORIA_SOURCES
    core/arboria_mesh_resource.cpp
    core/arboria_runtime.cpp
    core/arboria_security.cpp
    gpu/arboria_buffer_manager.cpp
    gpu/arboria_compute_dispatch.cpp
    gpu/arboria_indirect_renderer.cpp
    integration/arboria_scene_bridge.cpp
    integration/arboria_render_pass.cpp
    integration/arboria_gdextension.cpp
)

set(ARBORIA_HEADERS
    core/arboria_types.h
    core/arboria_mesh_resource.h
    core/arboria_runtime.h
    core/arboria_security.h
    gpu/arboria_buffer_manager.h
    gpu/arboria_compute_dispatch.h
    gpu/arboria_indirect_renderer.h
    integration/arboria_scene_bridge.h
    integration/arboria_render_pass.h
)

# Compilar Shared Library (DLL)
add_library(arboria_native SHARED ${ARBORIA_SOURCES} ${ARBORIA_HEADERS})
target_include_directories(arboria_native PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Compilar Static Library
add_library(arboria_native_static STATIC ${ARBORIA_SOURCES} ${ARBORIA_HEADERS})
target_include_directories(arboria_native_static PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Compilar Teste Executável Unitário Autônomo
add_executable(test_native_core tests/test_native_core.cpp ${ARBORIA_SOURCES})
target_include_directories(test_native_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# The test uses assert() for its checks; keep those active in Release builds.
if(MSVC)
    target_compile_options(test_native_core PRIVATE /UNDEBUG)
else()
    target_compile_options(test_native_core PRIVATE -UNDEBUG)
endif()

enable_testing()
add_test(NAME arboria_native_core
    COMMAND test_native_core "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/dense_rock_verified.vgmesh")
set_tests_properties(arboria_native_core PROPERTIES
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")

# Copiar DLL para binários do projeto
add_custom_command(TARGET arboria_native POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_native>
    ${CMAKE_CURRENT_SOURCE_DIR}/build/arboria_native.dll
    COMMAND ${CMAKE_COMMAND} -E make_directory
    ${CMAKE_CURRENT_SOURCE_DIR}/../../project/bin
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_native>
    ${CMAKE_CURRENT_SOURCE_DIR}/../../project/bin/libarboria_native.dll
)

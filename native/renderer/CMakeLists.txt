cmake_minimum_required(VERSION 3.16)
project(arboria_native VERSION 7.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ARBORIA_SOURCES
    core/arboria_logger.cpp
    core/arboria_mesh_resource.cpp
    core/arboria_mutable_geometry.cpp
    core/arboria_runtime.cpp
    core/arboria_security.cpp
    core/arboria_geometric_compiler.cpp
    core/arboria_compiler_bridge.cpp
    core/arboria_mesh_loader.cpp
    gpu/arboria_buffer_manager.cpp
    gpu/arboria_compute_dispatch.cpp
    gpu/arboria_indirect_renderer.cpp
    integration/arboria_scene_bridge.cpp
    integration/arboria_render_pass.cpp
    integration/arboria_abi.cpp
    integration/arboria_gdextension.cpp
    scene/arboria_mesh_registry.cpp
    scene/arboria_material_table.cpp
    scene/arboria_instance_registry.cpp
    scene/arboria_visibility_manager.cpp
    scene/arboria_indirect_command_manager.cpp
    scene/arboria_gpu_scene.cpp
    scene/arboria_render_world.cpp
    gpu/arboria_memory_manager.cpp
    scene/arboria_streaming_manager.cpp
)

set(ARBORIA_HEADERS
    core/arboria_logger.h
    core/arboria_types.h
    core/arboria_error.h
    core/arboria_handle.h
    core/arboria_mesh_resource.h
    core/arboria_mutable_geometry.h
    core/arboria_runtime.h
    core/arboria_security.h
    core/arboria_geometric_compiler.h
    core/arboria_compiler_bridge.h
    core/arboria_mesh_loader.h
    gpu/arboria_gpu_driver.h
    gpu/arboria_buffer_manager.h
    gpu/arboria_compute_dispatch.h
    gpu/arboria_indirect_renderer.h
    gpu/arboria_memory_manager.h
    integration/arboria_abi.h
    integration/arboria_scene_bridge.h
    integration/arboria_render_pass.h
    scene/arboria_gpu_scene_types.h
    scene/arboria_mesh_registry.h
    scene/arboria_material_table.h
    scene/arboria_instance_registry.h
    scene/arboria_visibility_manager.h
    scene/arboria_indirect_command_manager.h
    scene/arboria_gpu_scene.h
    scene/arboria_render_world.h
    scene/arboria_streaming_manager.h
)

# Compilar Shared Library (DLL)
add_library(arboria_native SHARED ${ARBORIA_SOURCES} ${ARBORIA_HEADERS})
target_include_directories(arboria_native PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
if(MINGW)
    target_link_options(arboria_native PRIVATE -static)
endif()

# Compilar Static Library
add_library(arboria_native_static STATIC ${ARBORIA_SOURCES} ${ARBORIA_HEADERS})
target_include_directories(arboria_native_static PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Compilar Teste Executavel Unitario Autonomo
add_executable(test_native_core tests/test_native_core.cpp ${ARBORIA_SOURCES})
target_include_directories(test_native_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

if(MSVC)
    target_compile_options(test_native_core PRIVATE /UNDEBUG)
else()
    target_compile_options(test_native_core PRIVATE -UNDEBUG)
endif()

# Compilar Teste Executavel Unitario Avancado (stress, concorrencia, regressao)
add_executable(test_native_advanced tests/test_arboria_advanced.cpp ${ARBORIA_SOURCES})
target_include_directories(test_native_advanced PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

if(MSVC)
    target_compile_options(test_native_advanced PRIVATE /UNDEBUG)
else()
    target_compile_options(test_native_advanced PRIVATE -UNDEBUG)
endif()

enable_testing()
add_test(NAME arboria_native_core
    COMMAND test_native_core "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/dense_rock.vgmesh")
set_tests_properties(arboria_native_core PROPERTIES
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
add_test(NAME arboria_native_advanced
    COMMAND test_native_advanced)
set_tests_properties(arboria_native_advanced PROPERTIES
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")

# Copiar DLL para todos os caminhos do projeto
add_custom_command(TARGET arboria_native POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_native>
    ${CMAKE_CURRENT_SOURCE_DIR}/build/arboria_native.dll
    COMMAND ${CMAKE_COMMAND} -E make_directory
    ${CMAKE_CURRENT_SOURCE_DIR}/../../project/bin
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_native>
    ${CMAKE_CURRENT_SOURCE_DIR}/../../project/bin/libarboria_native.dll
    COMMAND ${CMAKE_COMMAND} -E make_directory
    ${CMAKE_CURRENT_SOURCE_DIR}/../../addons/arboria/bin
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_native>
    ${CMAKE_CURRENT_SOURCE_DIR}/../../addons/arboria/bin/libarboria_native.dll
    COMMAND ${CMAKE_COMMAND} -E make_directory
    ${CMAKE_CURRENT_SOURCE_DIR}/../../project/addons/arboria/bin
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_native>
    ${CMAKE_CURRENT_SOURCE_DIR}/../../project/addons/arboria/bin/libarboria_native.dll
)

# ---------------------------------------------------------------------------
# Sanitizer builds (ASan / TSan) — detecção de vazamentos, data races e UB
# Usar:   cmake -DARBORIA_SANITIZER=address   ..
#         cmake -DARBORIA_SANITIZER=thread    ..
#         cmake -DARBORIA_SANITIZER=address,undefined ..
# ---------------------------------------------------------------------------
option(ARBORIA_SANITIZER "Enable sanitizer build (address, thread, undefined, or comma-separated list)" "")

if(ARBORIA_SANITIZER)
    string(REPLACE "," ";" ARBORIA_SANITIZER_LIST "${ARBORIA_SANITIZER}")
    foreach(san ${ARBORIA_SANITIZER_LIST})
        if(san STREQUAL "address" OR san STREQUAL "asan")
            list(APPEND ARBORIA_SAN_FLAGS "-fsanitize=address")
            list(APPEND ARBORIA_SAN_LINK_FLAGS "-fsanitize=address")
        elseif(san STREQUAL "thread" OR san STREQUAL "tsan")
            list(APPEND ARBORIA_SAN_FLAGS "-fsanitize=thread")
            list(APPEND ARBORIA_SAN_LINK_FLAGS "-fsanitize=thread")
        elseif(san STREQUAL "undefined" OR san STREQUAL "ubsan")
            list(APPEND ARBORIA_SAN_FLAGS "-fsanitize=undefined")
            list(APPEND ARBORIA_SAN_LINK_FLAGS "-fsanitize=undefined")
        else()
            message(WARNING "Sanitizer desconhecido ignorado: ${san}")
        endif()
    endforeach()

    if(ARBORIA_SAN_FLAGS)
        message(STATUS "Arboria Sanitizers ativados: ${ARBORIA_SANITIZER}")
        target_compile_options(arboria_native PRIVATE ${ARBORIA_SAN_FLAGS})
        target_compile_options(arboria_native_static PRIVATE ${ARBORIA_SAN_FLAGS})
        target_compile_options(test_native_core PRIVATE ${ARBORIA_SAN_FLAGS})
        target_compile_options(test_native_advanced PRIVATE ${ARBORIA_SAN_FLAGS})
        target_link_options(arboria_native PRIVATE ${ARBORIA_SAN_LINK_FLAGS})
        target_link_options(arboria_native_static PRIVATE ${ARBORIA_SAN_LINK_FLAGS})
        target_link_options(test_native_core PRIVATE ${ARBORIA_SAN_LINK_FLAGS})
        target_link_options(test_native_advanced PRIVATE ${ARBORIA_SAN_LINK_FLAGS})
    endif()
endif()

cmake_minimum_required(VERSION 3.20)
project(ArboriaVirtualGeometry LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/meshoptimizer
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

file(GLOB MESHMESH_SRC "thirdparty/meshoptimizer/*.cpp")

add_executable(arboria_baker_cli
    src/arboria_baker_main.cpp
    ${MESHMESH_SRC}
)

if (WIN32)
    target_link_libraries(arboria_baker_cli PRIVATE psapi)
endif()

set_target_properties(arboria_baker_cli PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../bin"
)

# Compatibilidade: gera cópia vg_baker_cli no diretório bin para scripts existentes
add_custom_command(TARGET arboria_baker_cli POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:arboria_baker_cli>
    "${CMAKE_CURRENT_SOURCE_DIR}/../../bin/vg_baker_cli$<TARGET_FILE_SUFFIX:arboria_baker_cli>"
)

cmake_minimum_required(VERSION 3.20)
project(ArboriaVirtualGeometry LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/meshoptimizer
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

file(GLOB MESHMESH_SRC "thirdparty/meshoptimizer/*.cpp")

add_executable(vg_baker_cli
    src/vg_baker_main.cpp
    ${MESHMESH_SRC}
)

if (WIN32)
    target_link_libraries(vg_baker_cli PRIVATE psapi)
endif()

set_target_properties(vg_baker_cli PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../bin"
)

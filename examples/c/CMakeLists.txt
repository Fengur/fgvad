cmake_minimum_required(VERSION 3.18)
project(fgvad_cli C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# 项目根目录(examples/c 的上两级)
set(FGVAD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(CARGO_PROFILE "release")
set(CARGO_TARGET_DIR "${FGVAD_ROOT}/target")

if(APPLE)
  set(FGVAD_DYLIB "${CARGO_TARGET_DIR}/${CARGO_PROFILE}/libfgvad.dylib")
else()
  message(FATAL_ERROR "本 demo 第一版仅支持 macOS")
endif()

# CMake 每次 build 都尝试触发 cargo;cargo 自己负责增量。
add_custom_command(
  OUTPUT "${FGVAD_DYLIB}"
  COMMAND cargo build --release
  WORKING_DIRECTORY "${FGVAD_ROOT}"
  COMMENT "构建 libfgvad (${CARGO_PROFILE})"
)
add_custom_target(fgvad_build DEPENDS "${FGVAD_DYLIB}")

add_library(fgvad SHARED IMPORTED)
set_target_properties(fgvad PROPERTIES
  IMPORTED_LOCATION "${FGVAD_DYLIB}"
)

add_executable(fgvad_cli src/fgvad_cli.c)
target_include_directories(fgvad_cli PRIVATE "${FGVAD_ROOT}/include")
target_link_libraries(fgvad_cli PRIVATE fgvad)
target_compile_options(fgvad_cli PRIVATE -Wall -Wextra -Wpedantic)
add_dependencies(fgvad_cli fgvad_build)

# 使可执行文件能在原地找到 libfgvad.dylib(开发期方便)
if(APPLE)
  set_target_properties(fgvad_cli PROPERTIES
    BUILD_RPATH "${CARGO_TARGET_DIR}/${CARGO_PROFILE}"
  )
endif()

# CTest
enable_testing()

cmake_minimum_required(VERSION 3.18)
project(fgvad_cli C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# 项目根目录(examples/c 的上两级)
set(FGVAD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(CARGO_PROFILE "release")
if(CARGO_PROFILE STREQUAL "release")
  set(CARGO_PROFILE_FLAG --release)
else()
  set(CARGO_PROFILE_FLAG "")
endif()
set(CARGO_TARGET_DIR "${FGVAD_ROOT}/target")

if(APPLE)
  set(FGVAD_DYLIB "${CARGO_TARGET_DIR}/${CARGO_PROFILE}/libfgvad.dylib")
else()
  message(FATAL_ERROR "本 demo 第一版仅支持 macOS")
endif()

# CMake 每次 build 都调用 cargo;cargo 自己负责增量判断。
# 使用 add_custom_target(ALL) 而非 add_custom_command(OUTPUT)，
# 确保即使产物文件已存在也会重跑——改 Rust 源码后能正确重链。
add_custom_target(fgvad_build ALL
  COMMAND cargo build ${CARGO_PROFILE_FLAG}
  WORKING_DIRECTORY "${FGVAD_ROOT}"
  COMMENT "构建 libfgvad (${CARGO_PROFILE})"
  BYPRODUCTS "${FGVAD_DYLIB}"
  VERBATIM
)

add_library(fgvad SHARED IMPORTED)
set_target_properties(fgvad PROPERTIES
  IMPORTED_LOCATION "${FGVAD_DYLIB}"
)

add_executable(fgvad_cli
  src/fgvad_cli.c
  src/wav_io.c
  src/event_fmt.c
)
target_include_directories(fgvad_cli PRIVATE "${FGVAD_ROOT}/include")
target_include_directories(fgvad_cli PRIVATE src)
target_link_libraries(fgvad_cli PRIVATE fgvad)
target_compile_options(fgvad_cli PRIVATE -Wall -Wextra -Wpedantic)
# Debug 构建可额外开启 sanitizer:
#   cmake -B build-debug -DCMAKE_BUILD_TYPE=Debug \
#         -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"
add_dependencies(fgvad_cli fgvad_build)

# 使可执行文件能在原地找到 libfgvad.dylib(开发期方便)
if(APPLE)
  set_target_properties(fgvad_cli PROPERTIES
    BUILD_RPATH "${CARGO_TARGET_DIR}/${CARGO_PROFILE}"
  )
endif()

# CTest
enable_testing()

add_executable(test_wav_io tests/test_wav_io.c src/wav_io.c)
target_include_directories(test_wav_io PRIVATE src)
target_compile_options(test_wav_io PRIVATE -Wall -Wextra -Wpedantic)
add_test(NAME wav_io COMMAND test_wav_io
         WORKING_DIRECTORY ${CMAKE_BINARY_DIR})

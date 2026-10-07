cmake_minimum_required(VERSION 3.20)
project(PureRecomp VERSION 0.1.0 LANGUAGES C CXX)

# The framework (TeamGDB/PortableKit, MIT) is vendored at the commit in vendor/PIN by tools/vendor_setup.sh.
set(PSPRECOMP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/portablekit portablekit)

# Our profile. PROFILE_DIR is the repo root, so the corpus lives in generated/ and the player's files in game/
# (both git-ignored), as docs/PROFILE_GUIDE.md in the framework lays out.
# Our own main() (src/host/pure_main.cpp) runs ge_replay for `--replay` and the framework's main, compiled as
# portablekit_main, otherwise (task 022).
# The Metal GE backend's files, by concern (docs/metal-backend.md, "Files"; task 049).
set(metal_backend_sources src/gpu/metal_backend.mm src/gpu/metal_targets.mm src/gpu/metal_textures.mm
    src/gpu/metal_pipelines.mm src/gpu/metal_trace.mm)
portablekit_add_game(PureNative
    PROFILE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
    HOST_MAIN_NAME portablekit_main
    SOURCES src/profile/pure_profile.cpp src/hle/audio_capture.cpp
            src/host/pure_main.cpp src/tools/ge_replay.cpp
            ${metal_backend_sources} src/gpu/metal_device.mm src/gpu/metal_shell.cpp
            src/host/metal_shell.mm third_party/imgui_metal/imgui_impl_metal.mm)

# The Metal GE backend (PURE_GE_BACKEND=metal, docs/metal-backend.md), the Metal shell (PURE_SHELL=metal) and Dear
# ImGui's Metal renderer backend (1.92.9b, the vendored ImGui's release, MIT): Objective-C++ with ARC, compiled by the
# same clang as everything else. Their shaders are MSL source compiled at run time, so no Xcode is needed. The backend
# and the shell share one device and command queue (src/gpu/metal_device.mm, task 031).
set(objc_sources ${metal_backend_sources} src/gpu/metal_device.mm src/host/metal_shell.mm
    third_party/imgui_metal/imgui_impl_metal.mm)
list(TRANSFORM objc_sources PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
set_source_files_properties(${objc_sources}
    PROPERTIES LANGUAGE CXX COMPILE_OPTIONS "-x;objective-c++;-fobjc-arc")
target_include_directories(PureNative PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/third_party/imgui_metal")
# The backend's shaders are src/gpu/shaders/ge.metal, a plain Metal source file (task 049), turned at build time into a
# generated header that holds its text as a raw string (pure::metal::kShaderSource), so the app carries them and no
# build reads a path at run time; the backend compiles them when it starts, as before.
set(metal_shader_header "${CMAKE_CURRENT_BINARY_DIR}/generated_metal/ge_metal.hpp")
add_custom_command(
    OUTPUT "${metal_shader_header}"
    COMMAND ${CMAKE_COMMAND} "-DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/shaders/ge.metal"
            "-DOUTPUT=${metal_shader_header}" -DNAME=kShaderSource
            -P "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/shaders/embed.cmake"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/shaders/ge.metal" "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/shaders/embed.cmake"
    VERBATIM
    COMMENT "Embedding the Metal shaders")
target_sources(PureNative PRIVATE "${metal_shader_header}")
target_include_directories(PureNative PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated_metal")
# CoreGraphics for the Metal shell's sRGB colour space.
target_link_libraries(PureNative PRIVATE "-framework Metal" "-framework Foundation" "-framework QuartzCore"
    "-framework CoreGraphics")

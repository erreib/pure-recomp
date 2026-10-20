cmake_minimum_required(VERSION 3.20)
project(PureRecomp VERSION 0.2.0 LANGUAGES C CXX)

# The framework (TeamGDB/PortableKit, MIT) is vendored at the commit in vendor/PIN by tools/vendor_setup.sh.
set(PSPRECOMP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/portablekit portablekit)

# The Metal GE backend, the Metal shell and ImGui's Metal renderer backend are macOS only (docs/windows.md); on
# Windows and Linux the framework's Vulkan renderer and shell are the path, and none of src/gpu/ is built.
if(APPLE)
    # The Metal GE backend's files, by concern (docs/metal-backend.md, "Files"; task 049).
    set(metal_backend_sources src/gpu/metal_backend.mm src/gpu/metal_targets.mm src/gpu/metal_textures.mm
        src/gpu/metal_texture_pack.mm src/gpu/metal_pipelines.mm src/gpu/metal_effects.mm src/gpu/metal_trace.mm
        src/gpu/metal_draw.mm)
    set(platform_sources ${metal_backend_sources} src/gpu/sprite_upscale.cpp src/gpu/metal_device.mm
        src/host/metal_shell.mm third_party/imgui_metal/imgui_impl_metal.mm)
else()
    set(platform_sources)
endif()

# Our profile. PROFILE_DIR is the repo root, so the corpus lives in generated/ and the player's files in game/
# (both git-ignored), as docs/PROFILE_GUIDE.md in the framework lays out.
# Our own main() (src/host/pure_main.cpp) runs ge_replay for `--replay` and the framework's main, compiled as
# portablekit_main, otherwise (task 022). The record backend (PURE_GE_BACKEND=record, which writes what ge_replay
# reads) is built on every platform, as the framework built it before task 095 moved it here, and so is the models
# backend (PURE_GE_BACKEND=models, the default since task 102: figures drawn as models, src/gpu/models_backend.cpp).
portablekit_add_game(PureNative
    PROFILE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
    HOST_MAIN_NAME portablekit_main
    SOURCES src/profile/pure_profile.cpp src/profile/enhancements.cpp src/profile/test_hooks.cpp
            src/profile/aspect.cpp src/hle/audio_capture.cpp
            src/host/pure_main.cpp src/tools/ge_replay.cpp src/tools/ge_extract.cpp src/tools/record_backend.cpp
            src/gpu/models_backend.cpp
            ${platform_sources})

# Zstandard's decoder for the ZIM images of HD texture packs (D-024, task 099): the framework compiles
# host/gpu/texture_pack.cpp into PureNative itself, so linking the library here gives it zstd.h and the symbols.
include(cmake/Zstd.cmake)
target_link_libraries(PureNative PRIVATE pure_zstd_decoder)

# The Windows release (task 061, docs/release.md "Windows"): the windows subsystem, so a player who starts the program
# from Explorer gets no console window; the entry stays the C runtime's main(). The developer build keeps the console
# subsystem, whose stdout every tool reads.
if(WIN32 AND PORTABLEKIT_RELEASE)
    set_target_properties(PureNative PROPERTIES WIN32_EXECUTABLE TRUE)
    target_link_options(PureNative PRIVATE /ENTRY:mainCRTStartup)
endif()

# The executable's icon and version resource (task 071), in both Windows presets: packaging/windows/pure.rc, compiled
# by llvm-rc (CMAKE_RC_COMPILER), with the project version; the icon is packaging/windows/pure.ico (make_icon.py).
if(WIN32)
    target_sources(PureNative PRIVATE packaging/windows/pure.rc)
    set_source_files_properties(packaging/windows/pure.rc PROPERTIES
        COMPILE_DEFINITIONS "PURE_VERSION_MAJOR=${PROJECT_VERSION_MAJOR};PURE_VERSION_MINOR=${PROJECT_VERSION_MINOR};PURE_VERSION_PATCH=${PROJECT_VERSION_PATCH}"
        OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/packaging/windows/pure.ico")
endif()

if(APPLE)
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
endif()

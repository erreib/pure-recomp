cmake_minimum_required(VERSION 3.20)
project(PureRecomp VERSION 0.1.0 LANGUAGES C CXX)

# The framework (TeamGDB/PortableKit, MIT) is vendored at the commit in vendor/PIN by tools/vendor_setup.sh.
set(PSPRECOMP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/portablekit portablekit)

# Our profile. PROFILE_DIR is the repo root, so the corpus lives in generated/ and the player's files in game/
# (both git-ignored), as docs/PROFILE_GUIDE.md in the framework lays out.
# Our own main() (src/host/pure_main.cpp) runs ge_replay for `--replay` and the framework's main, compiled as
# portablekit_main, otherwise (task 022).
portablekit_add_game(PureNative
    PROFILE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
    HOST_MAIN_NAME portablekit_main
    SOURCES src/profile/pure_profile.cpp src/hle/audio_capture.cpp
            src/host/pure_main.cpp src/tools/ge_replay.cpp
            src/gpu/metal_backend.mm src/gpu/metal_shell.cpp)

# The Metal GE backend (PURE_GE_BACKEND=metal, docs/metal-backend.md): Objective-C++ with ARC, compiled by the
# same clang as everything else. Its shaders are MSL source compiled at run time, so no Xcode is needed.
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/metal_backend.mm"
    PROPERTIES LANGUAGE CXX COMPILE_OPTIONS "-x;objective-c++;-fobjc-arc")
target_link_libraries(PureNative PRIVATE "-framework Metal" "-framework Foundation" "-framework QuartzCore")

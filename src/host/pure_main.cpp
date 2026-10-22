// Our entry point (task 022). `PureNative --replay FILE ...` replays a GE backend recording (src/tools/ge_replay.cpp);
// anything else goes to the framework's main, which CMakeLists.txt compiles as portablekit_main (HOST_MAIN_NAME), so
// the game starts exactly as it did when that was main().
//
// On macOS the game runs on the Metal shell and the Metal GE backend unless the environment names others (D-008, task
// 028): PURE_SHELL and PURE_GE_BACKEND are set here only when unset, so an explicit value (also an empty one, which
// the framework reads as vulkan) always wins, and PURE_NO_RENDER keeps its meaning (the headless shell, whatever
// PURE_SHELL says). Under the Vulkan shell (PURE_SHELL vulkan or empty, PURE_NO_RENDER unset) the backend left unset
// is vulkan: that shell shows only the Vulkan backend's pictures (task 093), so PURE_SHELL=vulkan alone is the Vulkan
// path. A replay names its backends on its command line and is left alone.
// Since task 102 (D-025) the backend left unset is `models` on every platform, which wraps the one above: it draws
// the figures as models when the Video tab's Crowds and people row says so and hands every other call over unchanged
// (src/gpu/models_backend.cpp). The backend it wraps is PURE_GE_MODELS_INNER, set here when unset to what
// PURE_GE_BACKEND would have been: metal, or vulkan under the Vulkan shell, and vulkan elsewhere. A tool that names a
// backend (PURE_GE_BACKEND=metal, vulkan, null or record) runs without the wrapper.
// In a release build (PURE_MODELS 0, D-027) the backend left unset is the one the wrapper would wrap, metal or vulkan,
// as before task 102: the models features are not in a release.
#include "../tools/ge_replay.hpp"

#include <cstdlib>
#include <string_view>

namespace {
// Sets `name` to `value` unless the environment already has it (an empty value counts as set).
void set_default(const char *name, const char *value) {
#if defined(_WIN32)
    if (std::getenv(name) == nullptr) _putenv_s(name, value);
#else
    setenv(name, value, 0);
#endif
}
} // namespace

#ifndef PURE_MODELS
#define PURE_MODELS 1  // CMakeLists.txt defines it for this file: 0 in a release build (D-027)
#endif

int portablekit_main(int argc, char **argv);

int main(int argc, char **argv) {
    if (argc > 1 && std::string_view(argv[1]) == "--replay") return pure::replay::run(argc, argv);
#if defined(__APPLE__)
    set_default("PURE_SHELL", "metal");
    const char *shell = std::getenv("PURE_SHELL");
    const bool vulkan_shell =
        std::getenv("PURE_NO_RENDER") == nullptr && (*shell == '\0' || std::string_view(shell) == "vulkan");
    const char *platform = vulkan_shell ? "vulkan" : "metal";
#else
    const char *platform = "vulkan";
#endif
#if PURE_MODELS
    set_default("PURE_GE_MODELS_INNER", platform);
    set_default("PURE_GE_BACKEND", "models");
#else
    set_default("PURE_GE_BACKEND", platform);
#endif
    return portablekit_main(argc, argv);
}

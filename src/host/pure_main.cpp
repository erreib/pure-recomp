// Our entry point (task 022). `PureNative --replay FILE ...` replays a GE backend recording (src/tools/ge_replay.cpp);
// anything else goes to the framework's main, which CMakeLists.txt compiles as portablekit_main (HOST_MAIN_NAME), so
// the game starts exactly as it did when that was main().
//
// On macOS the game runs on the Metal shell and the Metal GE backend unless the environment names others (D-008, task
// 028): PURE_SHELL and PURE_GE_BACKEND are set here only when unset, so an explicit value (also an empty one, which
// the framework reads as vulkan) always wins, and PURE_NO_RENDER keeps its meaning (the headless shell, whatever
// PURE_SHELL says). The Vulkan path stays one setting away: PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan. A replay names
// its backends on its command line and is left alone.
#include "../tools/ge_replay.hpp"

#include <cstdlib>
#include <string_view>

int portablekit_main(int argc, char **argv);

int main(int argc, char **argv) {
    if (argc > 1 && std::string_view(argv[1]) == "--replay") return pure::replay::run(argc, argv);
#if defined(__APPLE__)
    setenv("PURE_SHELL", "metal", 0);
    setenv("PURE_GE_BACKEND", "metal", 0);
#endif
    return portablekit_main(argc, argv);
}

// Our entry point (task 022). `PureNative --replay FILE ...` replays a GE backend recording (src/tools/ge_replay.cpp);
// anything else goes to the framework's main, which CMakeLists.txt compiles as portablekit_main (HOST_MAIN_NAME), so
// the game starts exactly as it did when that was main().
#include "../tools/ge_replay.hpp"

#include <string_view>

int portablekit_main(int argc, char **argv);

int main(int argc, char **argv) {
    if (argc > 1 && std::string_view(argv[1]) == "--replay") return pure::replay::run(argc, argv);
    return portablekit_main(argc, argv);
}

#pragma once

// ge_replay (task 022): feeds a GE backend recording (.gerec, the record backend of patch 0009) to any registered GE
// backend outside the game and compares what it presents. src/host/pure_main.cpp runs it for
// `PureNative --replay FILE ...`; docs/ge-backend.md, section 7, describes it.
namespace pure::replay {

// argv[1] is "--replay". Returns the process's exit code: 0 when every compared frame passed (or nothing was
// compared), 1 when one failed, 2 for bad arguments, a bad file or a backend that cannot run.
int run(int argc, char **argv);

} // namespace pure::replay

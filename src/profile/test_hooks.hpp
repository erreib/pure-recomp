// The test instruments (task 051): every test switch and probe of the port, apart from the game's profile
// (pure_profile.cpp), so the profile reads as the port and these as what they are. They are PURE_TEST_NO_DAMAGE,
// PURE_TEST_UNLOCK_ALL, PURE_TEST_RACE_CLOCK, PURE_VFPU_DOT, PURE_WATCH_MOVIE, PURE_WATCH_SHIP, PURE_WATCH_GRID,
// PURE_WATCH_RAND, PURE_WATCH_WORDS, PURE_TRACE_RAND and PURE_TRACE_CALLS (README.md, the switches tables: each one
// test-only). None is for play, and each is off unless set. The run-control switches (PURE_EXIT_AT_FRAME,
// PURE_FRAME_LOG, PURE_PACED_FROM) stay in the profile: they shape a run, they do not change or watch the game.
#pragma once

#include "hle/hle_common.hpp"

#include <cstdint>

namespace portablekit::test_hooks {

// What the profile answers on the test switches' behalf.
struct Hooks {
    // sceKernelGetGPI's answer: 0 as on retail, 1 (bit 0: every frontend lock open) under PURE_TEST_UNLOCK_ALL or a
    // PURE_TEST_RACE_CLOCK file's `unlocked 1`.
    std::uint32_t gpi = 0u;
};

// The one call, at start: from the profile's register_extra_hle hook, after the profile has bound its flip counter
// (sceDisplaySetFrameBuf, which PURE_TRACE_CALLS may wrap) and before the audio capture and sceKernelGetGPI. Prints
// each switch's start-up line, wraps sceKernelGetSystemTimeWide for the race clock's frame times and the calls
// PURE_TRACE_CALLS names, and returns the answers above.
[[nodiscard]] Hooks install(HleRegistrar &hle);

// The per-flip hook: called by the profile's flip counter once a flip, before the game's own sceDisplaySetFrameBuf
// runs, with the flip's number (1 the first). At the first flip (after the corpus is registered) it puts in the native
// srand() and rand() copies of PURE_TEST_RACE_CLOCK and PURE_TRACE_RAND and sets PURE_VFPU_DOT's rounding; every flip
// it runs the probes and PURE_TEST_NO_DAMAGE.
void flip(Runtime &rt, std::uint64_t frame);

} // namespace portablekit::test_hooks

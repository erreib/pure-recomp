// The enhancements: what the port offers beyond the PSP's game, each a player's option in the Esc menu
// (GameProfile::options, patch 0019-game-option-rows) and a hook of the profile's that reads it. E4 (D-017, task 072):
// Frame rate, game.sixty_fps, PURE_SIXTY_FPS. E6 (D-016, task 070): Flashes, game.smooth_flashes, PURE_SMOOTH_FLASHES.
// Every tool run has them off unless it names them (tools/purelib/port.py), so the checks measure the PSP's game;
// tools/framerate_check.sh is the check with E4 on, tools/flash_check.sh the one with E6 on.
#pragma once

#include "hle/hle_common.hpp"
#include "profile.hpp"

#include <span>

namespace portablekit::enhancements {

// This game's options, for GameProfile::options.
[[nodiscard]] std::span<const GameOption> options();

// The hooks behind them: from the profile's register_extra_hle hook, once, after the framework's media calls are
// bound and before the test hooks (which PURE_TRACE_CALLS may wrap over them). Prints each option's start-up line.
void install(HleRegistrar &hle);

} // namespace portablekit::enhancements

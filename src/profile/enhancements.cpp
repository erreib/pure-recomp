// The enhancements (enhancements.hpp says what is here and why it is apart from the profile).
#include "enhancements.hpp"

#include "kernel/kernel.hpp"
#include "settings/settings.hpp"

#include <cstdint>
#include <iostream>

namespace portablekit::enhancements {
namespace {

// --- E6: Flashes (D-016, task 070) -----------------------------------------------------------------------------------
// The full-screen flash FxScreen (FUN_0882da04) stores 2 to the frame object's countdown at +0x117c on every frame its
// effect runs, and the end-of-frame routine FUN_0886511c waits two vblanks a frame while that countdown is not 0 or
// the mode's byte at +0x116c is 0 (docs/timing.md, step 5): the race-start fade, a weapon going off near the camera
// and the ship put back on the track run at 30 fps on the PSP. The game integrates a measured dt (FUN_08804390), so
// the wait does not set the race's speed. Smooth clears the countdown in the free-running modes (+0x116c is 1: Single
// Race and Tournament) before the routine reads it: at its GE sync (step 1, FUN_088eda8c, the only caller of
// sceGeDrawSync). The 30-fps modes and the frontend (+0x116c 0) are left alone. FUN_0886511c is the only reader of
// +0x117c in the corpus (task 070).
const char *const kFlashChoices[] = {"Original", "Smooth"};

const GameOption kOptions[] = {
    {.key = "smooth_flashes",
     .label = "Flashes",
     .choices = kFlashChoices,
     .description = "The PSP halves the frame rate while a full-screen flash plays: the race-start fade, a weapon "
                    "going off near you, your ship put back on the track. Smooth keeps the race's frame rate through "
                    "them. The game's speed is the same either way (it measures time). Time Trial, Free Play and Zone "
                    "run at 30 fps on the PSP and still do.",
     .default_choice = 1u,
     .tab = MenuTab::Video},
};

constexpr std::uint32_t kNidSceGeDrawSync = 0xB287BD61u;
constexpr std::uint32_t kFrameObjectPtr = 0x08A8E960u;  // DAT_08a8e960: the frame object FUN_0886511c is handed
constexpr std::uint32_t kFreeRunning = 0x116Cu;         // u8: 1 in Single Race and Tournament, 0 in the 30-fps modes
constexpr std::uint32_t kFlashCountdown = 0x117Cu;      // s32: FxScreen's countdown, two vblanks a frame while not 0
constexpr std::uint32_t kUserBase = 0x08800000u, kUserEnd = 0x0A000000u;

void smooth_flashes(HleRegistrar &hle) {
    static HleFunction original = hle.bound_function("sceGe_user", kNidSceGeDrawSync);
    if (!original) return;
    if (settings::game_option("smooth_flashes") == 0u) std::cout << "[pure] smooth flashes: off\n";
    hle.bind("sceGe_user", kNidSceGeDrawSync, [](Runtime &rt, AllegrexContext &ctx) {
        if (settings::game_option("smooth_flashes") == 1u) {
            auto &m = rt.memory();
            const std::uint32_t frame = m.load32(kFrameObjectPtr);
            if (frame >= kUserBase && frame + kFlashCountdown + 4u <= kUserEnd && m.load8(frame + kFreeRunning) == 1u) {
                m.store32(frame + kFlashCountdown, 0u);
                static bool announced = false;
                if (!announced) {
                    announced = true;
                    std::cout << "[pure] smooth flashes: on (game.smooth_flashes)\n";
                }
            }
        }
        original(rt, ctx);
    });
}

} // namespace

std::span<const GameOption> options() { return kOptions; }

void install(HleRegistrar &hle) { smooth_flashes(hle); }

} // namespace portablekit::enhancements

// The enhancements (enhancements.hpp says what is here and why it is apart from the profile).
#include "enhancements.hpp"

#include "kernel/kernel.hpp"
#include "settings/settings.hpp"

#include <cstdint>
#include <iostream>

namespace portablekit::enhancements {
namespace {

// --- E4: 30 fps modes (D-017, task 072) --------------------------------------------------------------------------------
// The end-of-frame routine FUN_0886511c waits two vblanks a frame while the frame object's byte at +0x116c is 0
// (docs/timing.md, step 5). The race backend's constructor (BackendRoot_cpp__0880c068) sets it to 1 and the race
// managers of Free Play, Time Trial and Zone (LinkObj_etc__08818d80, LinkObj_etc__08819a0c, LinkObj_etc__0881bc8c) set
// it back to 0, so those modes run at 30 fps on the PSP. The game integrates a measured dt (FUN_08804390) and the
// audit found nothing in those modes that advances per frame (D-017). 60 fps stores 1 to the byte while the backend
// lives (DAT_08a8c5f4 set), at the same GE sync as E6 and before it, so a flash in a free-running Time Trial takes E6's
// path too. The frontend (no backend) keeps its byte. The byte's other readers are MemStickUtil's save-dialog
// functions, which save it to DAT_08b17c14 and store 0 before a dialog; the dialog driver FUN_08897f20 puts it back
// after (task 072, docs/timing.md "E4").
const char *const kFrameRateChoices[] = {"Original", "60 fps"};

// --- E6: Flashes (D-016, task 070) -----------------------------------------------------------------------------------
// The full-screen flash FxScreen (FUN_0882da04) stores 2 to the frame object's countdown at +0x117c on every frame its
// effect runs, and the end-of-frame routine FUN_0886511c waits two vblanks a frame while that countdown is not 0 or
// the mode's byte at +0x116c is 0 (docs/timing.md, step 5): the race-start fade, a weapon going off near the camera
// and the ship put back on the track run at 30 fps on the PSP. The game integrates a measured dt (FUN_08804390), so
// the wait does not set the race's speed. Smooth clears the countdown in the free-running modes (+0x116c is 1: Single
// Race and Tournament, and the 30-fps modes under E4's 60 fps) before the routine reads it: at its GE sync (step 1,
// FUN_088eda8c, the only caller of sceGeDrawSync). With +0x116c 0 (the 30-fps modes at Original, the frontend) nothing
// is written. FUN_0886511c is the only reader of +0x117c in the corpus (task 070).
const char *const kFlashChoices[] = {"Original", "Smooth"};

const GameOption kOptions[] = {
    {.key = "sixty_fps",
     .label = "30 fps modes",
     .choices = kFrameRateChoices,
     .description = "Time Trial, Free Play and Zone run at 30 fps on the PSP. 60 fps runs them at the display's rate, "
                    "as Single Race and Tournament already do. The game's speed is the same either way (it measures "
                    "time).",
     .default_choice = 1u,
     .tab = MenuTab::Video},
    {.key = "smooth_flashes",
     .label = "Flashes",
     .choices = kFlashChoices,
     .description = "The PSP halves the frame rate while a full-screen flash plays: the race-start fade, a weapon "
                    "going off near you, your ship put back on the track. Smooth keeps the race's frame rate through "
                    "them. The game's speed is the same either way (it measures time). Time Trial, Free Play and Zone "
                    "run at 30 fps unless the 30 fps modes row says 60 fps.",
     .default_choice = 1u,
     .tab = MenuTab::Video},
};

constexpr std::uint32_t kNidSceGeDrawSync = 0xB287BD61u;
constexpr std::uint32_t kFrameObjectPtr = 0x08A8E960u;  // DAT_08a8e960: the frame object FUN_0886511c is handed
// DAT_08a8c5f4: the race backend object, stored by its constructor BackendRoot_cpp__0880c068 (at 0x0880c0cc) and
// zeroed by its destructor BackendRoot_cpp__0880c328 (at 0x0880c5cc), its only writers; 0 in the executable's .data,
// so 0 in the frontend.
constexpr std::uint32_t kBackendPtr = 0x08A8C5F4u;
constexpr std::uint32_t kFreeRunning = 0x116Cu;         // u8: 1 in Single Race and Tournament, 0 in the 30-fps modes
constexpr std::uint32_t kFlashCountdown = 0x117Cu;      // s32: FxScreen's countdown, two vblanks a frame while not 0
constexpr std::uint32_t kUserBase = 0x08800000u, kUserEnd = 0x0A000000u;

// E4: the 30-fps modes' byte set back to 1 while the race backend lives.
void sixty_fps(psprecomp::GuestMemory &m) {
    const std::uint32_t backend = m.load32(kBackendPtr);
    const std::uint32_t frame = m.load32(kFrameObjectPtr);
    if (backend < kUserBase || backend >= kUserEnd || frame < kUserBase || frame + kFreeRunning >= kUserEnd ||
        m.load8(frame + kFreeRunning) != 0u)
        return;
    m.store8(frame + kFreeRunning, 1u);
    static bool announced = false;
    if (!announced) {
        announced = true;
        std::cout << "[pure] sixty fps: on (game.sixty_fps)\n";
    }
}

// E6: the flash countdown cleared in a free-running frame.
void smooth_flashes(psprecomp::GuestMemory &m) {
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

// Both at the end-of-frame routine's GE sync (step 1, before step 5 reads the two fields), E4 first.
void wrap_draw_sync(HleRegistrar &hle) {
    static HleFunction original = hle.bound_function("sceGe_user", kNidSceGeDrawSync);
    if (!original) return;
    if (settings::game_option("sixty_fps") == 0u) std::cout << "[pure] sixty fps: off\n";
    if (settings::game_option("smooth_flashes") == 0u) std::cout << "[pure] smooth flashes: off\n";
    hle.bind("sceGe_user", kNidSceGeDrawSync, [](Runtime &rt, AllegrexContext &ctx) {
        auto &m = rt.memory();
        if (settings::game_option("sixty_fps") == 1u) sixty_fps(m);
        if (settings::game_option("smooth_flashes") == 1u) smooth_flashes(m);
        original(rt, ctx);
    });
}

} // namespace

std::span<const GameOption> options() { return kOptions; }

void install(HleRegistrar &hle) { wrap_draw_sync(hle); }

} // namespace portablekit::enhancements

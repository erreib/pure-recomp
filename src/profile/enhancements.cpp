// The enhancements (enhancements.hpp says what is here and why it is apart from the profile).
#include "enhancements.hpp"

#include "kernel/kernel.hpp"
#include "settings/settings.hpp"
#if defined(PORTABLEKIT_HAS_RENDERER)
#include "shell/shell.hpp"
#include "ui/layer.hpp"
#endif

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <utility>

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

// --- E7: Text and sprites (D-018, task 073) --------------------------------------------------------------------------
// The menus' text and art and the race HUD are bitmap atlases (CLUT4 fonts, CLUT8 art) drawn as 2D draws (orthographic,
// unlit), so a higher internal scale only magnifies their texels. Upscaled has the Metal backend redraw such a
// texture 4x finer at decode (src/gpu/sprite_upscale.cpp, docs/metal-backend.md "Sprite upscale"); the backend reads
// the option itself, once a frame, so there is no hook here. The Vulkan renderer draws the originals either way.
// Original is the default since 2026-10-12 (D-018, amended): Erik judged the resample soft against the sharp 3D and
// unlike the elements the rule leaves alone; a sharp menu is an asset job (redrawn atlases through the pack), not a filter.
const char *const kSpriteChoices[] = {"Original", "Upscaled"};

// --- E5: Texture detail (D-019, task 075) ----------------------------------------------------------------------------
// The GE picks a mipmapped texture's level for the PSP's 480x272 pixels, and the Metal backend picks it the same way at
// any internal scale (task 037, D-015), so at scale S the track ahead and the angled walls are drawn from a level
// log2(S) coarser than the pixels could show, and isotropically. Enhanced has the backend lower the GE's D by
// 16 x log2(S) and sample those draws anisotropically through explicit gradients (docs/metal-backend.md "Texture
// detail"); the backend reads the option itself, once a frame, so there is no hook here. The Vulkan renderer does the
// same since task 076 (patch 0020-vulkan-texture-detail), reading it through the profile's texture_detail_option.
const char *const kTextureDetailChoices[] = {"Original", "Enhanced"};

// --- E8: Display rate (D-022, task 089) ------------------------------------------------------------------------------
// The game's frame rate is its vblank rate: Single Race and Tournament (and the 30-fps modes under E4) wait one vblank
// a frame, the frontend and the 30-fps modes at Original two. The kernel ticks the vblank at the PSP's 59.94 Hz
// (kVBlankPeriodUs) unless told another period (patch 0030-vblank-period: Kernel::set_vblank_period_us, which the
// tick, the media HLE's vblank arithmetic, the pacer's game frame and the Metal shell's present timing follow). Display
// sets the period from the display's refresh when that is above 60.5 Hz, round(1e6 / (rate x (1 - margin))) with the
// rate clamped to 240 Hz, while the race backend lives (DAT_08a8c5f4 and the frame object in user RAM: E4's gate), and
// the PSP's period outside it; a change applies from the next vblank. The margin (task 091): at exactly the display's
// refresh vsync is the clock that paces the game, so a frame that misses its refresh is real time lost for good (the
// game can never present faster than the display to make it up), and the sound, made on the game's clock, falls
// behind until the audio sink skips. A game a little slower than the display has room to catch up (docs/timing.md
// "E8"); kDisplayMargin is the smallest that kept a race's sound whole on both renderers. The race's speed does not
// change: its frame timer
// FUN_08804390 measures dt from the system clock and every object integrates it (docs/timing.md, "The game's clock in a
// race"). The frontend stays at the PSP's cadence because its screens' build-in and build-out transitions count frames
// and ran at twice the speed at 120 (task 089's measurement, docs/timing.md "E8"; the decision's review, 2026-10-14).
const char *const kDisplayRateChoices[] = {"Original", "Display"};

// --- Crowds and people (D-025, task 102) -----------------------------------------------------------------------------
// The crowd on the grandstands and the pit marshals on the start line's booths are flat cut-out quads on the PSP
// (docs/research.md, "The crowd, surveyed"). Models has the models GE backend (src/gpu/models_backend.cpp, the default
// backend since task 102, wrapping the platform's) draw each quad of a texture models/models.ini names as a 3D model
// of ours instead: the marshal today. The backend reads the option itself, once a frame, so there is no hook here.
// Original until the crowd's models exist (D-025, point 4).
const char *const kCrowdModelChoices[] = {"Original", "Models"};

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
    {.key = "sprite_upscale",
     .label = "Text and sprites",
     .choices = kSpriteChoices,
     .description = "The menus' text and art and the race HUD are small bitmaps on the PSP. Upscaled redraws them four "
                    "times finer with smooth edges, which reads soft beside the sharp 3D picture. Metal only: the Vulkan "
                    "renderer draws the originals, or the same upscaled art from the texture pack tools/sprite_pack.sh "
                    "builds (the Texture pack row).",
     .default_choice = 0u,
     .tab = MenuTab::Video},
    {.key = "texture_detail",
     .label = "Texture detail",
     .choices = kTextureDetailChoices,
     .description = "The PSP picks each texture's level of detail for its own 480x272 pixels, so above 1x the track "
                    "ahead and angled walls stay as soft as on the PSP. Enhanced picks the level for the pixels drawn "
                    "and samples angled surfaces anisotropically. Shows above 1x. Both renderers.",
     .default_choice = 1u,
     .tab = MenuTab::Video},
    {.key = "display_rate",
     .label = "Display rate",
     .choices = kDisplayRateChoices,
     .description = "The game draws a frame every one or two refreshes of the PSP's 60 Hz display. Display runs that "
                    "refresh at your display's rate in a race when it is above 60 Hz: on a 120 Hz display Single "
                    "Race and Tournament draw 120 frames a second, and Time Trial, Free Play and Zone 120 with the "
                    "30 fps modes row at 60 fps or 60 at Original, a fraction under the display's rate so the sound "
                    "stays continuous. The menus keep the PSP's pace. The race's speed is the same either way (it "
                    "measures time).",
     .default_choice = 1u,
     .tab = MenuTab::Video},
    {.key = "crowd_models",
     .label = "Crowds and people",
     .choices = kCrowdModelChoices,
     .description = "The crowd and the figures by the track are flat pictures on the PSP. Models draws them as 3D "
                    "figures where the port has a model for them: the start line's marshals and the grandstands' crowd. "
                    "Both renderers.",
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
constexpr double kMinDisplayHz = 60.5;   // E8: a display at 60 Hz (59.94 or 60) keeps the PSP's period
constexpr double kMaxDisplayHz = 240.0;  // and one above 240 Hz runs the vblank at 240
// E8: the race's vblank runs this fraction under the display's refresh (task 091's measurement: docs/timing.md "E8").
constexpr double kDisplayMargin = 0.005;

// E8: whether the race backend lives, E4's gate: DAT_08a8c5f4 (set by the backend's constructor during the race load,
// zeroed by its destructor) and the frame object both in user RAM. Every race mode, whatever the lock byte +0x116c says
// (0 in the 30-fps modes at Original and while the save dialog runs, 1 otherwise).
bool race_backend(const psprecomp::GuestMemory &m) {
    const std::uint32_t backend = m.load32(kBackendPtr);
    const std::uint32_t frame = m.load32(kFrameObjectPtr);
    return backend >= kUserBase && backend < kUserEnd && frame >= kUserBase && frame < kUserEnd;
}

// E4: the 30-fps modes' byte set back to 1 while the race backend lives.
void sixty_fps(psprecomp::GuestMemory &m) {
    if (!race_backend(m)) return;
    const std::uint32_t frame = m.load32(kFrameObjectPtr);
    if (frame + kFreeRunning >= kUserEnd || m.load8(frame + kFreeRunning) != 0u) return;
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

// E8: the display's refresh in Hz, 0 when unknown. PURE_DISPLAY_HZ=N (a test switch: a headless run has no display)
// names it; else the window shell's display_refresh().
double display_hz() {
    static const double named = [] {
        const char *v = env("DISPLAY_HZ");
        return v != nullptr ? std::strtod(v, nullptr) : 0.0;
    }();
    if (named > 0.0) return named;
#if defined(PORTABLEKIT_HAS_RENDERER)
    if (ui::Layer::get().attached()) return static_cast<double>(ui::Layer::get().shell().display_refresh());
#endif
    return 0.0;
}

// E8: the margin under the display's refresh, kDisplayMargin unless the test switch PURE_DISPLAY_MARGIN=F names a
// fraction from 0 (the exact display rate, for the comparison) to below 0.5.
double display_margin() {
    static const double margin = [] {
        const char *v = env("DISPLAY_MARGIN");
        if (v == nullptr) return kDisplayMargin;
        char *end = nullptr;
        const double named = std::strtod(v, &end);
        return end != v && named >= 0.0 && named < 0.5 ? named : kDisplayMargin;
    }();
    return margin;
}

// E8: the kernel's vblank period from the option, the display's rate, the margin and the race backend, set and
// announced when it changes: at start (no backend) and at every frame's GE sync (the race load and its end, the row
// changed in the menu, the window moved to another display). A line a change, not a flip: `off` (Original, or no
// display above 60.5 Hz), `120 Hz display, the game at 119.40 Hz in a race (margin 0.005), the PSP's 59.94 Hz outside
// one` (Display, outside a race) and `120 Hz display, the game at 119.40 Hz (margin 0.005, 8375 us a vblank)` (in
// one); the game's rate is 1e6 over the period.
void display_rate(const psprecomp::GuestMemory *m) {
    double hz = 0.0;
    if (settings::game_option("display_rate") == 1u) hz = display_hz();
    std::uint64_t period = kVBlankPeriodUs;
    std::uint64_t display_period = 0u;
    enum class State { Off, Outside, Race } state = State::Off;
    if (hz > kMinDisplayHz) {
        hz = std::min(hz, kMaxDisplayHz);
        display_period = static_cast<std::uint64_t>(std::llround(1e6 / (hz * (1.0 - display_margin()))));
        state = m != nullptr && race_backend(*m) ? State::Race : State::Outside;
        if (state == State::Race) period = display_period;
    }
    static std::optional<std::pair<State, std::uint64_t>> applied;
    if (applied && applied->first == state && applied->second == display_period) return;
    applied = std::pair{state, display_period};
    kernel().set_vblank_period_us(period);
    std::ostringstream line;
    line << "[pure] display rate: ";
    if (state == State::Off) {
        line << "off";
    } else {
        line << std::lround(hz) << " Hz display, the game at " << std::fixed << std::setprecision(2)
             << 1e6 / static_cast<double>(display_period) << " Hz" << std::defaultfloat << std::setprecision(6);
        if (state == State::Outside)
            line << " in a race (margin " << display_margin() << "), the PSP's 59.94 Hz outside one";
        else
            line << " (margin " << display_margin() << ", " << period << " us a vblank)";
    }
    std::cout << line.str() << "\n";
}

// All at the end-of-frame routine's GE sync (step 1, before step 5 reads the two fields): E8's period first (it reads
// the backend, not the byte E4 writes), then E4, then E6.
void wrap_draw_sync(HleRegistrar &hle) {
    static HleFunction original = hle.bound_function("sceGe_user", kNidSceGeDrawSync);
    if (!original) return;
    if (settings::game_option("sixty_fps") == 0u) std::cout << "[pure] sixty fps: off\n";
    if (settings::game_option("smooth_flashes") == 0u) std::cout << "[pure] smooth flashes: off\n";
    display_rate(nullptr);
    hle.bind("sceGe_user", kNidSceGeDrawSync, [](Runtime &rt, AllegrexContext &ctx) {
        auto &m = rt.memory();
        display_rate(&m);
        if (settings::game_option("sixty_fps") == 1u) sixty_fps(m);
        if (settings::game_option("smooth_flashes") == 1u) smooth_flashes(m);
        original(rt, ctx);
    });
}

} // namespace

std::span<const GameOption> options() { return kOptions; }

void install(HleRegistrar &hle) { wrap_draw_sync(hle); }

} // namespace portablekit::enhancements

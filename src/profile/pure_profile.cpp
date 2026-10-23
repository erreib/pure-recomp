// The Wipeout Pure profile: what the framework cannot read off the executable. See vendor/portablekit/host/profile.hpp.
// Values below were read from Erik's disc (docs/research.md, "Erik's dump") and from spike S4 (docs/codegen-baseline.md).
// The test switches and probes are in test_hooks.cpp (task 051); this file keeps the game's port and the run-control
// switches (PURE_EXIT_AT_FRAME, PURE_FRAME_LOG, PURE_PACED_FROM); the enhancements, each a menu option, are in
// enhancements.cpp (task 070).
#include "profile.hpp"
#include "aspect.hpp"
#include "enhancements.hpp"
#include "shield_step.hpp"
#include "test_hooks.hpp"

#include "hle/hle_common.hpp"
#include "kernel/kernel.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <optional>

namespace portablekit {

// PURE_AUDIO_WAV (src/hle/audio_capture.cpp).
void register_audio_capture(HleRegistrar &hle);

namespace {

// Save folders the executable itself names: profiles are "UCUS98612P%04d" (PROFILE.BIN + PARAM.SFO + ICON0.PNG),
// ghosts "UCUS98612G%x", and download packs "UCUS98612D<PACK>" (PI.WAD + PARAM.SFO + TEST.BIN, docs/dlc.md).
// This list is the save transfer's and the Esc menu's save screen's only (save_transfer.cpp): Import accepts a folder
// by these names and the screen shows the description; the game's own save-data calls name their folders themselves.
// The twelve US packs follow the profiles (task 077), each with its PARAM.SFO's SAVEDATA_TITLE (Delta 1's "Delat"
// corrected). A pack is the game's data, not the player's save: exported is false, and content_pack (task 078, patch
// 0021-content-packs) puts it in the System tab's Download packs section instead of among the saves, leaves it out of
// Export and Back up saves, and lets Import skip the file list entry that names no file in seven of the twelve.
constexpr SaveFolder kSaveFolders[] = {
    {"UCUS98612P0000", "Profile 1", true},   // the game's list starts at P0000 (task 014)
    {"UCUS98612P0001", "Profile 2", true},
    {"UCUS98612P0002", "Profile 3", true},
    {"UCUS98612P0003", "Profile 4", true},
    {"UCUS98612P0004", "Profile 5", true},
    {"UCUS98612DCLASSICPACK1", "Classic Pack 1", false, true},
    {"UCUS98612DCLASSICPACK2", "Classic Pack 2", false, true},
    {"UCUS98612DCLASSICPACK3", "Classic Pack 3", false, true},
    {"UCUS98612DDELTAPACK1", "Delta Pack 1", false, true},
    {"UCUS98612DDELTAPACK2", "Delta Pack 2", false, true},
    {"UCUS98612DGAMMAPACK1", "Gamma Pack 1", false, true},
    {"UCUS98612DGAMMAPACK2", "Gamma Pack 2", false, true},
    {"UCUS98612DGAMMAPACK3", "Gamma Pack 3", false, true},
    {"UCUS98612DPAKDAXTER", "Daxter Pack", false, true},
    {"UCUS98612DPAKJAKX", "Jak X Pack", false, true},
    {"UCUS98612DPAKSOCOM3", "Socom 3 Pack", false, true},
    {"UCUS98612DPAKSOCOMFTB", "Socom FTB Pack", false, true},
};

void return_zero(Runtime &, AllegrexContext &ctx) { kernel().finish(ctx, 0u); }
void return_one(Runtime &, AllegrexContext &ctx) { kernel().finish(ctx, 1u); }

// Frame counter behind PURE_EXIT_AT_FRAME (bounded, deterministic runs for the tools) and PURE_FRAME_LOG (a line
// every N frames), and the test hooks' per-flip hook. It wraps the framework's sceDisplaySetFrameBuf handler, the
// game's flip, so it counts headless too.
constexpr std::uint32_t kNidSceDisplaySetFrameBuf = 0x289D82FEu;

// PURE_PACED_FROM=N (task 034), for the tools: the kernel's clock runs unpaced (Kernel::set_paced(false), patch
// 0005-kernel-host-waits-and-pacing) from start-up until flip N, and is held to real time (set_paced(true)) from flip N
// on, whatever the shell.
// Without a window the menus before a race then take seconds, while the race, where tools/campaign_sweep.py steers
// closed loop from the probe's lines, keeps real time. A window still presents at the display's rate (the Metal
// shell waits for a drawable at vsync), so a windowed run gains little. 0 is paced from the start; unset (or empty)
// leaves pacing to the shell, as before: paced with a window, unpaced without. Set every flip, so nothing the shell
// does later undoes it.
std::optional<std::uint64_t> paced_from() {
    static const std::optional<std::uint64_t> value = []() -> std::optional<std::uint64_t> {
        const char *v = env("PACED_FROM");
        if (v == nullptr || *v == '\0') return std::nullopt;
        char *end = nullptr;
        const std::uint64_t n = std::strtoull(v, &end, 10);
        if (end == nullptr || *end != '\0') {
            std::cout << "[pure] PURE_PACED_FROM=" << v << " is not a flip number; ignored\n";
            return std::nullopt;
        }
        return n;
    }();
    return value;
}

void apply_paced_from(std::uint64_t frame) {
    const auto from = paced_from();
    if (!from) return;
    const bool paced = frame >= *from;
    static bool announced = false;
    if (paced && !announced && *from != 0u) {
        announced = true;
        std::cout << "[pure] paced from frame " << frame << " t=" << kernel().now_us() << "\n";
    }
    kernel().set_paced(paced);
}

void wrap_flip_counter(HleRegistrar &hle) {
    static HleFunction original = hle.bound_function("sceDisplay", kNidSceDisplaySetFrameBuf);
    if (!original) return;
    hle.bind("sceDisplay", kNidSceDisplaySetFrameBuf, [](Runtime &rt, AllegrexContext &ctx) {
        static std::uint64_t frames = 0;
        static const std::uint64_t exit_at = [] { const char *v = env("EXIT_AT_FRAME"); return v ? std::strtoull(v, nullptr, 10) : 0ull; }();
        static const std::uint64_t log_every = [] { const char *v = env("FRAME_LOG"); return v ? std::strtoull(v, nullptr, 10) : 0ull; }();
        ++frames;
        apply_paced_from(frames);
        if (log_every != 0u && frames % log_every == 0u) std::cout << "[pure] frame " << frames << "\n";
        test_hooks::flip(rt, frames);
        shield_step::flip(rt, frames);  // PURE_TRACE_SHIELD (task 107)
        original(rt, ctx);
        if (exit_at != 0u && frames >= exit_at) {
            std::cout << "[pure] exit at frame " << frames << "\n";
            rt.stop("PURE_EXIT_AT_FRAME reached");
        }
    });
}

// Calls the framework does not implement, or that this game needs answered differently. Each one is here because
// the interpreter run of spike S3 hit it before the frontend. Keep this list short; a call any game makes belongs in
// the framework or in an HLE extension module (docs/HLE_EXTENSIONS.md), not here.
void register_pure_hle(HleRegistrar &hle) {
    if (const auto from = paced_from()) {
        // The shell (register_media, before this hook) has set the pace from its window; the switch wins from here.
        std::cout << "[pure] PURE_PACED_FROM=" << *from
                  << (*from == 0u ? ": paced to real time from the start\n"
                                  : ": unpaced until that flip, paced to real time from it\n");
        apply_paced_from(0u);
    }
    wrap_flip_counter(hle);
    // The enhancements' hooks (enhancements.cpp): E4 and E6 wrap sceGeDrawSync, which PURE_TRACE_CALLS may then wrap.
    enhancements::install(hle);
    // The test switches and probes (test_hooks.cpp), installed here, once: after the flip counter, which
    // PURE_TRACE_CALLS may wrap, and before the audio capture and the GPI answer, which are bound over what it wrapped.
    const test_hooks::Hooks tests = test_hooks::install(hle);
    register_audio_capture(hle);

    // The dev-kit switch block. Retail reads 0, which selects display mode 0 and the normal pacing path
    // (docs/timing.md). The test switch PURE_TEST_UNLOCK_ALL, and a PURE_TEST_RACE_CLOCK file's `unlocked 1`, answer 1
    // instead: the frontend's lock checks then read everything as unlocked (test_hooks.cpp).
    hle.add("UtilsForUser", "sceKernelGetGPI", tests.gpi != 0u ? return_one : return_zero);

    // sceKernelUSec2SysClock(usec, SceKernelSysClock *clock): the 64-bit clock is just the microsecond count.
    hle.add("ThreadManForUser", "sceKernelUSec2SysClock", [](Runtime &rt, AllegrexContext &ctx) {
        if (arg(ctx, 1) != 0u) store64(rt.memory(), arg(ctx, 1), static_cast<std::uint64_t>(arg(ctx, 0)));
        kernel().finish(ctx, 0u);
    });

    // sceKernelGetThreadmanIdList(type, buf, count, idcount*): report no ids until something needs them.
    hle.add("ThreadManForUser", "sceKernelGetThreadmanIdList", [](Runtime &rt, AllegrexContext &ctx) {
        if (arg(ctx, 3) != 0u) rt.memory().store32(arg(ctx, 3), 0u);
        kernel().finish(ctx, 0u);
    });

    // sceKernelRotateThreadReadyQueue(priority): a yield hint; the scheduler's own preemption covers it.
    hle.add("ThreadManForUser", "sceKernelRotateThreadReadyQueue", return_zero);

    // sceKernelSetVTimerHandler(uid, SceKernelSysClock *time, handler, common): the narrow form of the Wide one the
    // framework implements; the schedule is a 64-bit clock behind a pointer instead of in registers.
    hle.add("ThreadManForUser", "sceKernelSetVTimerHandler", [](Runtime &rt, AllegrexContext &ctx) {
        auto found = kernel().vtimers.find(static_cast<std::int32_t>(arg(ctx, 0)));
        if (found == kernel().vtimers.end()) {
            kernel().finish(ctx, 0x800201C1u); // SCE_KERNEL_ERROR_UNKNOWN_VTID
            return;
        }
        const std::uint32_t clock = arg(ctx, 1);
        found->second.schedule_us =
            clock == 0u ? 0u
                        : (static_cast<std::uint64_t>(rt.memory().load32(clock + 4u)) << 32u) | rt.memory().load32(clock);
        found->second.handler = arg(ctx, 2);
        found->second.common = arg(ctx, 3);
        kernel().finish(ctx, 0u);
    });
}

} // namespace

const GameProfile &game() {
    static const GameProfile profile{
        .app_name = "PureNative",
        .project_name = "Wipeout Pure Native",
        .env_prefix = "PURE",
        .data_organization = "pure-recomp",
        .data_application = "PureNative",

        .disc_id = "UCUS98612",
        .disc_id_display = "UCUS-98612",
        .game_title = "Wipeout Pure",
        // The plain executable the disc carries beside the encrypted EBOOT.BIN: the installer takes it as it is
        // (its SHA-256 is executable_sha256 below), so no decryption key is needed (task 029).
        .executable_path_on_disc = "PSP_GAME/SYSDIR/BOOT.BIN",
        .param_sfo_path_on_disc = "PSP_GAME/PARAM.SFO",
        .release_name = "the US Greatest Hits release (v2.00)",
        // SHA-256 of PSP_GAME/SYSDIR/EBOOT.BIN (encrypted; kept for the record) and of PSP_GAME/SYSDIR/BOOT.BIN, the
        // plain executable the corpus is generated from and both the developer layout (game/EBOOT.ELF) and the
        // installer use. Nothing decrypts, so the key for tag 0x08000000 stays empty.
        .encrypted_executable_sha256 = "0228768504ea79edf5c2c5301e0c3fd3c4f1bfc32b6e59e2dd0de5fef8028453",
        .executable_sha256 = "9033e4dd3433116eee2fd309f9c775e332e54da292d7a85075d3b4ccdb9b5750",
        .decryption_tag = 0x08000000u,
        .decryption_key = {},
        .run_unknown_executables = true,

        .load_base = 0x08804000u,
        .guest_ram_bytes = 32u * 1024u * 1024u,
        .boot_path = "disc0:/PSP_GAME/SYSDIR/EBOOT.BIN",
        .overlay_slots = {},

        .save_game_name = "UCUS98612",
        .save_folders = kSaveFolders,
        // The System tab's section for the packs (task 078): the count installed, each pack, "Install download packs…".
        .content_packs_label = "Download packs",
        .player_name_label = "Pilot name",
        .default_player_name = "Pilot",

        .adhoc_product_code = "UCUS98612",

        .register_extra_hle = &register_pure_hle,

        // E2 (D-020, task 084): the 3D view at the shape of the picture under the Vulkan renderer's Fill aspect
        // (aspect.cpp); with the hook set the renderer offers Fill. At the PSP's 480:272 it changes nothing.
        .view_aspect_frame = &aspect::view_aspect_frame,

        // E3 (D-015, task 067): the picture at the display's own resolution out of the box. Auto draws the Metal
        // backend's screen-wide targets at the smallest multiple of 272 lines that covers the window's drawable (4 in
        // the default window on a 2x display), and the Vulkan renderer's at the window's size. A settings.ini that
        // already holds a value keeps it (patch 0017-internal-scale-by-backend).
        .default_internal_scale = 0u,

        // Single Race and Tournament run free up to the vblank rate; the other modes lock to two vblanks
        // (docs/timing.md) unless E4's 30 fps modes row frees them. 1 keeps the renderer's frame-rate menu honest for the
        // fast modes.
        .frame_vblanks = 1u,

        // A US console: English, cross confirms.
        .system_language = 1u,
        .confirm_button = 1u,

        // The menu's game rows (patch 0016-menu-rows-by-capability, D-014): ad hoc play is not a feature of this port
        // yet, and there is no right-stick or mouse camera (the PSP has neither; the race camera is the game's own).
        .features = {.adhoc = false, .right_stick_camera = false, .mouse_camera = false},

        // The enhancements, each a row of the menu's Game section (patch 0019-game-option-rows; enhancements.cpp): E4,
        // the 30 fps modes row (D-017, task 072), game.sixty_fps, default 60 fps; E6, Flashes (D-016, task 070),
        // game.smooth_flashes, default Smooth; E8, Display rate (D-022, task 089), game.display_rate, default Display.
        .options = enhancements::options(),
        // E5, Texture detail (D-019): the row the Vulkan renderer reads for the level shift and the anisotropic
        // sampling (patch 0020-vulkan-texture-detail, task 076); the Metal backend reads it itself (task 075).
        .texture_detail_option = "texture_detail",
    };
    return profile;
}

} // namespace portablekit

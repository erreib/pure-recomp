// The Wipeout Pure profile: what the framework cannot read off the executable. See vendor/portablekit/host/profile.hpp.
// Values below were read from Erik's disc (docs/research.md, "Erik's dump") and from spike S4 (docs/codegen-baseline.md).
#include "profile.hpp"

#include "hle/hle_common.hpp"
#include "kernel/kernel.hpp"

#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <vector>
#include <iostream>
#include <string>

namespace portablekit {
namespace {

// Save folders the executable itself names: profiles are "UCUS98612P%04d" (PROFILE.BIN + PARAM.SFO + ICON0.PNG),
// ghosts "UCUS98612G%x", and download packs "UCUS98612D<PACK>" (PI.WAD), which is the door DLC walks through later.
constexpr SaveFolder kSaveFolders[] = {
    {"UCUS98612P0001", "Profile 1", true},
    {"UCUS98612P0002", "Profile 2", true},
    {"UCUS98612P0003", "Profile 3", true},
    {"UCUS98612P0004", "Profile 4", true},
};

void return_zero(Runtime &, AllegrexContext &ctx) { kernel().finish(ctx, 0u); }

// Frame counter behind PURE_EXIT_AT_FRAME (bounded, deterministic runs for the tools) and PURE_FRAME_LOG (a line
// every N frames). It wraps the framework's sceDisplaySetFrameBuf handler, the game's flip, so it counts headless too.
constexpr std::uint32_t kNidSceDisplaySetFrameBuf = 0x289D82FEu;

std::string item_hex(std::uint32_t v) { char b[16]; std::snprintf(b, sizeof b, "0x%08X", v); return b; }

void wrap_flip_counter(HleRegistrar &hle) {
    static HleFunction original = hle.bound_function("sceDisplay", kNidSceDisplaySetFrameBuf);
    if (!original) return;
    hle.bind("sceDisplay", kNidSceDisplaySetFrameBuf, [](Runtime &rt, AllegrexContext &ctx) {
        static std::uint64_t frames = 0;
        static const std::uint64_t exit_at = [] { const char *v = env("EXIT_AT_FRAME"); return v ? std::strtoull(v, nullptr, 10) : 0ull; }();
        static const std::uint64_t log_every = [] { const char *v = env("FRAME_LOG"); return v ? std::strtoull(v, nullptr, 10) : 0ull; }();
        ++frames;
        if (log_every != 0u && frames % log_every == 0u) std::cout << "[pure] frame " << frames << "\n";
        original(rt, ctx);
        if (exit_at != 0u && frames >= exit_at) {
            std::cout << "[pure] exit at frame " << frames << "\n";
            rt.stop("PURE_EXIT_AT_FRAME reached");
        }
    });
}

// PURE_TRACE_CALLS=lib:0xNID,lib:0xNID,...: wraps the named HLE calls and prints their arguments and the virtual time
// (NIDs from config/imports.csv; the registrar resolves names only for its own table). A probe for whatever is chased.
void wrap_call_traces(HleRegistrar &hle) {
    const char *spec = env("TRACE_CALLS");
    if (spec == nullptr || *spec == '\0') return;
    std::stringstream ss(spec);
    std::string item;
    while (std::getline(ss, item, ',')) {
        const auto colon = item.find(':');
        if (colon == std::string::npos) continue;
        const std::string lib = item.substr(0, colon);
        const std::uint32_t nid = static_cast<std::uint32_t>(std::strtoul(item.substr(colon + 1).c_str(), nullptr, 16));
        HleFunction original = hle.bound_function(lib, nid);
        if (!original) { std::cout << "[pure] TRACE_CALLS: nothing bound for " << item << "\n"; continue; }
        const std::string label = lib + ":" + item.substr(colon + 1);
        hle.bind(lib, nid, [original, label](Runtime &r, AllegrexContext &ctx) {
            const std::uint32_t a[4] = {arg(ctx, 0), arg(ctx, 1), arg(ctx, 2), arg(ctx, 3)};
            const std::uint64_t t = kernel().now_us();
            original(r, ctx);
            std::cout << "[call] " << label << std::hex << " a0=" << a[0] << " a1=" << a[1] << " a2=" << a[2] << " a3=" << a[3]
                      << " v0=" << ctx.gpr[2] << std::dec << " t=" << t << "\n";
        });
    }
}

// Calls the framework does not implement, or that this game needs answered differently. Each one is here because
// the interpreter run of spike S3 hit it before the frontend. Keep this list short; a call any game makes belongs in
// the framework or in an HLE extension module (docs/HLE_EXTENSIONS.md), not here.
void register_pure_hle(HleRegistrar &hle) {
    wrap_flip_counter(hle);
    wrap_call_traces(hle);

    // The dev-kit switch block. Retail reads 0, which selects display mode 0 and the normal pacing path
    // (docs/timing.md).
    hle.add("UtilsForUser", "sceKernelGetGPI", return_zero);

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
        .executable_path_on_disc = "PSP_GAME/SYSDIR/EBOOT.BIN",
        .param_sfo_path_on_disc = "PSP_GAME/PARAM.SFO",
        .release_name = "the US Greatest Hits release (v2.00)",
        // SHA-256 of PSP_GAME/SYSDIR/EBOOT.BIN (encrypted) and of PSP_GAME/SYSDIR/BOOT.BIN, the plain executable the
        // disc also carries and the corpus is generated from. The developer layout (game/EBOOT.ELF = BOOT.BIN)
        // never decrypts; the installer path needs the key for tag 0x08000000, which is not filled in yet.
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
        .player_name_label = "Pilot name",
        .default_player_name = "Pilot",

        .adhoc_product_code = "UCUS98612",

        .register_extra_hle = &register_pure_hle,

        // Single Race and Tournament run free up to the vblank rate; the other modes lock to two vblanks
        // (docs/timing.md). 1 keeps the renderer's frame-rate menu honest for the fast modes.
        .frame_vblanks = 1u,

        // A US console: English, cross confirms.
        .system_language = 1u,
        .confirm_button = 1u,
    };
    return profile;
}

} // namespace portablekit

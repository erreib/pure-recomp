// The Wipeout Pure profile: what the framework cannot read off the executable. See vendor/portablekit/host/profile.hpp.
// Values below were read from Erik's disc (docs/research.md, "Erik's dump") and from spike S4 (docs/codegen-baseline.md).
#include "profile.hpp"

#include "hle/hle_common.hpp"
#include "kernel/kernel.hpp"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <vector>
#include <iostream>
#include <string>

namespace portablekit {

// PURE_AUDIO_WAV (src/hle/audio_capture.cpp).
void register_audio_capture(HleRegistrar &hle);

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

// PURE_WATCH_MOVIE=1: once per flip, the fields of the game's MovieManager object (docs/tasks/005), printed when
// they change. The object is the one the per-frame update FUN_089488a8 last stored at DAT_08ab45bc (0 when no movie
// runs). Fields: +0 active, +1 ended, +0x124 paused (u8); +0xd0 reader state (0 reading, 1 whole file in the ring,
// 2 stopping); +0x118 picture-queue capacity, +0x120 pictures queued, +0x128 pictures handed to the renderer,
// +0x10c/+0x110 write/read slots, +0x11c the picture array.
constexpr std::uint32_t kMovieObjectPtr = 0x08AB45BCu;

void watch_movie(Runtime &rt, std::uint64_t frame) {
    static const bool on = [] { const char *v = env("WATCH_MOVIE"); return v != nullptr && *v != '\0' && *v != '0'; }();
    if (!on) return;
    static std::string last;
    const std::uint32_t s = rt.memory().load32(kMovieObjectPtr);
    std::ostringstream o;
    o << "s=" << item_hex(s);
    if (s != 0u) {
        const auto &m = rt.memory();
        o << " active=" << unsigned(m.load8(s)) << " ended=" << unsigned(m.load8(s + 1u))
          << " paused=" << unsigned(m.load8(s + 0x124u)) << " reader=" << m.load32(s + 0xd0u)
          << " cap=" << m.load32(s + 0x118u) << " queued=" << static_cast<std::int32_t>(m.load32(s + 0x120u))
          << " shown=" << m.load32(s + 0x128u) << " wr=" << m.load32(s + 0x10cu) << " rd=" << m.load32(s + 0x110u)
          << " pics=" << item_hex(m.load32(s + 0x11cu));
    }
    if (o.str() == last) return;
    last = o.str();
    std::cout << "[pure] movie frame " << frame << " t=" << kernel().now_us() << " " << last << "\n";
}

// PURE_WATCH_SHIP=1 (task 007): once per flip during a race, the player's ship as the game's per-ship race record holds
// it, printed when it changes (`[pure] ship frame N t=... clock=... pos=... vel=... kmh=... dist=... lap=...`).
// The race records are a .bss array of 0x1C0-byte entries, one per ship; relative to entry k's position vector at
// 0x08B72010 + k * 0x1C0: -0x20 velocity (m/s; the HUD speed is |v| * 3.6), +0 position (x, y, z, 1; the same as
// the ship object's matrix row at +0x70), +0x10 lap counter, +0x14 the entry's ship index, +0x18 distance along the
// track, +0x1C race clock (s). The player's entry is found through its be::Ship object (vtable 0x08AC259C at +0x3c,
// set by LinkObj_etc__089261ac): +0x480 ship index, +0x488 kind (0/1 player, 2/3 AI), +0xcc AI flag. The objects
// are found by scanning user RAM every 30 flips until one is there, and again when the race is torn down.
constexpr std::uint32_t kShipVtable = 0x08AC259Cu;
constexpr std::uint32_t kRaceRecordPos = 0x08B72010u;
constexpr std::uint32_t kRaceRecordStride = 0x1C0u;

std::uint32_t find_player_ship(Runtime &rt) {
    const auto &m = rt.memory();
    constexpr std::uint32_t kBase = 0x08800000u, kSize = 0x01800000u;
    const std::uint8_t *ram = m.raw_pointer(kBase, kSize);
    if (ram == nullptr) return 0u;
    for (std::uint32_t off = 0x3cu; off + 4u <= kSize; off += 4u) {
        std::uint32_t v;
        std::memcpy(&v, ram + off, 4);
        if (v != kShipVtable) continue;
        const std::uint32_t obj = kBase + off - 0x3cu;
        if (m.load32(obj + 0x488u) <= 1u && m.load8(obj + 0xccu) == 0u && m.load32(obj + 0x480u) < 8u) return obj;
    }
    return 0u;
}

std::string item_f(float v) { char b[24]; std::snprintf(b, sizeof b, "%.3f", static_cast<double>(v)); return b; }

void watch_ship(Runtime &rt, std::uint64_t frame) {
    static const bool on = [] { const char *v = env("WATCH_SHIP"); return v != nullptr && *v != '\0' && *v != '0'; }();
    if (!on) return;
    static std::uint32_t ship = 0u;
    static std::uint64_t last_scan = 0u;
    static std::string last;
    const auto &m = rt.memory();
    if (ship != 0u && m.load32(ship + 0x3cu) != kShipVtable) ship = 0u;
    if (ship == 0u) {
        if (frame - last_scan < 30u) return;
        last_scan = frame;
        ship = find_player_ship(rt);
        if (ship == 0u) return;
        std::cout << "[pure] ship frame " << frame << " player object " << item_hex(ship) << " index "
                  << m.load32(ship + 0x480u) << "\n";
    }
    const std::uint32_t rec = kRaceRecordPos + m.load32(ship + 0x480u) * kRaceRecordStride;
    const auto f = [&m](std::uint32_t a) { const std::uint32_t u = m.load32(a); float x; std::memcpy(&x, &u, 4); return x; };
    const float vx = f(rec - 0x20u), vy = f(rec - 0x1cu), vz = f(rec - 0x18u);
    std::ostringstream o;
    o << "clock=" << item_f(f(rec + 0x1cu)) << " pos=" << item_f(f(rec)) << "," << item_f(f(rec + 4u)) << ","
      << item_f(f(rec + 8u)) << " vel=" << item_f(vx) << "," << item_f(vy) << "," << item_f(vz)
      << " kmh=" << item_f(3.6f * std::sqrt(vx * vx + vy * vy + vz * vz)) << " dist=" << item_f(f(rec + 0x18u))
      << " lap=" << m.load32(rec + 0x10u);
    if (o.str() == last) return;
    last = o.str();
    std::cout << "[pure] ship frame " << frame << " t=" << kernel().now_us() << " " << last << "\n";
}

void wrap_flip_counter(HleRegistrar &hle) {
    static HleFunction original = hle.bound_function("sceDisplay", kNidSceDisplaySetFrameBuf);
    if (!original) return;
    hle.bind("sceDisplay", kNidSceDisplaySetFrameBuf, [](Runtime &rt, AllegrexContext &ctx) {
        static std::uint64_t frames = 0;
        static const std::uint64_t exit_at = [] { const char *v = env("EXIT_AT_FRAME"); return v ? std::strtoull(v, nullptr, 10) : 0ull; }();
        static const std::uint64_t log_every = [] { const char *v = env("FRAME_LOG"); return v ? std::strtoull(v, nullptr, 10) : 0ull; }();
        ++frames;
        if (log_every != 0u && frames % log_every == 0u) std::cout << "[pure] frame " << frames << "\n";
        watch_movie(rt, frames);
        watch_ship(rt, frames);
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
    register_audio_capture(hle);

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

// The test instruments (task 051; test_hooks.hpp says what is here and why it is apart from the profile). Each switch
// has its own function below, commented with its README.md row's text and then the finding behind it. The code, the
// switches' names, their log lines and their effects are what they were in pure_profile.cpp: moved, not rewritten.
#include "test_hooks.hpp"

#include "../helpers.hpp"
#include "kernel/kernel.hpp"
#include "profile.hpp"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace portablekit::test_hooks {
namespace {

using pure::env_on;
using pure::hex;
using pure::load_float;

std::string item_f(float v) { char b[24]; std::snprintf(b, sizeof b, "%.3f", static_cast<double>(v)); return b; }

// --- The player's ship and the race records, for the probes and the switch that read them ------------------------

// The race records are a .bss array of 0x1C0-byte entries, one per ship; relative to entry k's position vector at
// 0x08B72010 + k * 0x1C0: -0x20 velocity (m/s; the HUD speed is |v| * 3.6), +0 position (x, y, z, 1; the same as the
// ship object's matrix row at +0x70), +0x10 lap counter, +0x14 the entry's ship index, +0x18 distance along the
// track, +0x1C race clock (s) (task 007). The player's entry is found through its be::Ship object (vtable 0x08AC259C
// at +0x3c, set by LinkObj_etc__089261ac): +0x480 ship index, +0x488 kind (0/1 player, 2/3 AI), +0xcc AI flag. The
// objects are found by scanning user RAM every 30 flips until one is there, and again when the race is torn down.
constexpr std::uint32_t kShipVtable = 0x08AC259Cu;
constexpr std::uint32_t kRaceRecordPos = 0x08B72010u;
constexpr std::uint32_t kRaceRecordStride = 0x1C0u;

// The shield (energy) of a be::Ship (task 017): a float at +0xF8. FUN_0892478c reads it (in the modes below 9 that
// DAT_08b173e4 numbers; the network modes keep it in a net record instead) and FUN_089247dc writes it, clamped to
// the ship type's maximum at *(*(ship + 0xC8) + 0x74) + 0x84; for the player the setter also tells the HUD
// (FUN_0881e944, the ~CRAFTCRITICAL warning under 20 and 10). Damage goes through FUN_08928274(amount, ship, kind),
// called from the ship's collision handling in FUN_08926ae4 (a wall or ship contact: amount = impact * 0.05 * 0.7):
// it lowers the shield, plays "energycritical" when it falls through 20, and at 0 or below puts the ship in state 4
// (destroyed, FUN_08928824). FUN_08923b78 refills it to the maximum, FUN_08923b9c adds to it (absorbing a pickup).
constexpr std::uint32_t kShipShield = 0xF8u;

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

// The player's be::Ship object for the probes and switches that need it (0 when there is none): found by the scan
// above every 30 flips until one is there, dropped when its vtable is gone (the race torn down).
std::uint32_t player_ship(Runtime &rt, std::uint64_t frame) {
    static std::uint32_t ship = 0u;
    static std::uint64_t last_scan = 0u;
    const auto &m = rt.memory();
    if (ship != 0u && m.load32(ship + 0x3cu) != kShipVtable) ship = 0u;
    if (ship == 0u) {
        if (frame - last_scan < 30u) return 0u;
        last_scan = frame;
        ship = find_player_ship(rt);
        if (ship == 0u) return 0u;
        std::cout << "[pure] ship frame " << frame << " player object " << hex(ship) << " index "
                  << m.load32(ship + 0x480u) << "\n";
    }
    return ship;
}

// The ship type's full shield, the setter's clamp; 0 when the type data is not there yet.
float ship_shield_max(Runtime &rt, std::uint32_t ship) {
    const auto &m = rt.memory();
    const std::uint32_t sim = m.load32(ship + 0xC8u);
    if (sim < 0x08800000u || sim >= 0x0A000000u) return 0.0f;
    const std::uint32_t type = m.load32(sim + 0x74u);
    if (type < 0x08800000u || type >= 0x0A000000u) return 0.0f;
    const float full = load_float(m, type + 0x84u);
    return std::isfinite(full) && full > 0.0f ? full : 0.0f;
}

// --- PURE_WATCH_SHIP=1 ---------------------------------------------------------------------------------------------
// README.md: (task 007) once per flip during a race, while it changes: the player's race record (`.bss` array of
// 0x1C0-byte entries, position of entry k at `0x08B72010 + k*0x1C0`): race clock, position, velocity, km/h, track
// distance, lap, and (task 017) the shield from the ship object (`be::Ship` +0xF8, float, 100 full on the Feisar)
// (`[pure] ship frame N t=... clock=... pos=... vel=... kmh=... dist=... lap=... shield=...`). PPSSPP reads the same
// race-record addresses.
// `shield` is the ship object's own field (kShipShield), not the race record's.
void watch_ship(Runtime &rt, std::uint64_t frame, std::uint32_t ship) {
    static std::string last;
    if (ship == 0u) return;
    const auto &m = rt.memory();
    const std::uint32_t rec = kRaceRecordPos + m.load32(ship + 0x480u) * kRaceRecordStride;
    const auto f = [&m](std::uint32_t a) { return load_float(m, a); };
    const float vx = f(rec - 0x20u), vy = f(rec - 0x1cu), vz = f(rec - 0x18u);
    std::ostringstream o;
    o << "clock=" << item_f(f(rec + 0x1cu)) << " pos=" << item_f(f(rec)) << "," << item_f(f(rec + 4u)) << ","
      << item_f(f(rec + 8u)) << " vel=" << item_f(vx) << "," << item_f(vy) << "," << item_f(vz)
      << " kmh=" << item_f(3.6f * std::sqrt(vx * vx + vy * vy + vz * vz)) << " dist=" << item_f(f(rec + 0x18u))
      << " lap=" << m.load32(rec + 0x10u) << " shield=" << item_f(f(ship + kShipShield));
    if (o.str() == last) return;
    last = o.str();
    std::cout << "[pure] ship frame " << frame << " t=" << kernel().now_us() << " " << last << "\n";
}

// --- PURE_WATCH_GRID=1 ---------------------------------------------------------------------------------------------
// README.md: (task 032) during a race (while the player's ship object is there), once per flip, every entry of the
// race-record array, k = 0 to 7, each line when it changes: `[pure] grid frame N k=K clock=C pos=x,y,z vel=vx,vy,vz
// dist=D lap=L` (the ship probe's race-record fields for each ship; the player's entry is the index of the `player
// object` line, 7 on a Single Race grid). Eight lines a flip: for recording racing lines (`tools/pp_lines.py
// --port`), not for long runs.
// Entry k is the ship with index k; tools/pp_lines.py --port turns a log of these lines into a racing line from the
// port's own AI ships.
void watch_grid(Runtime &rt, std::uint64_t frame, std::uint32_t ship) {
    static std::string last[8];
    if (ship == 0u) {
        for (auto &l : last) l.clear();
        return;
    }
    const auto &m = rt.memory();
    const auto f = [&m](std::uint32_t a) { return load_float(m, a); };
    for (std::uint32_t k = 0u; k < 8u; ++k) {
        const std::uint32_t rec = kRaceRecordPos + k * kRaceRecordStride;
        std::ostringstream o;
        o << "clock=" << item_f(f(rec + 0x1cu)) << " pos=" << item_f(f(rec)) << "," << item_f(f(rec + 4u)) << ","
          << item_f(f(rec + 8u)) << " vel=" << item_f(f(rec - 0x20u)) << "," << item_f(f(rec - 0x1cu)) << ","
          << item_f(f(rec - 0x18u)) << " dist=" << item_f(f(rec + 0x18u)) << " lap=" << m.load32(rec + 0x10u);
        if (o.str() == last[k]) continue;
        last[k] = o.str();
        std::cout << "[pure] grid frame " << frame << " k=" << k << " " << last[k] << "\n";
    }
}

// --- PURE_WATCH_RAND=1|2 -------------------------------------------------------------------------------------------
// README.md: (task 046) once per flip, while it changes (`2`: every flip), the game's libc `rand()` state (the word at
// +0x58 of the structure `0x08AB1A6C` points at) and the game's own clock (the frontend root's +0x44, a float in
// seconds): `[pure] rand frame N t=... state=0x... clock=S (0x...)`. The race's random sequence (docs/fidelity.md
// difference 13).
// rand() is FUN_088e0568 (state = state * 1103515245 + 12345, returns state & 0x7fffffff), srand() FUN_088e0558; the
// state is the word at +0x58 of the reent structure the pointer at 0x08AB1A6C names. The AI, the particles, the
// weather, the billboards and the replay camera all draw from it. `clock` is the game's own clock, the float at +0x44
// of the frontend root (DAT_08b17c18): seconds since the frontend started, summed from each frame's measured time
// (FUN_08804390, capped at 0.067 s a frame), the race seed's source.
constexpr std::uint32_t kReentPtr = 0x08AB1A6Cu;
constexpr std::uint32_t kRandState = 0x58u;
constexpr std::uint32_t kFrontendRoot = 0x08B17C18u;
constexpr std::uint32_t kGameClock = 0x44u;

void watch_rand(Runtime &rt, std::uint64_t frame) {
    static const bool on = env_on("WATCH_RAND"), every = on && std::strcmp(env("WATCH_RAND"), "2") == 0;
    if (!on) return;
    static std::uint32_t last = 0u;
    static bool any = false;
    const auto &m = rt.memory();
    const std::uint32_t reent = m.load32(kReentPtr);
    if (reent < 0x08800000u || reent >= 0x0A000000u) return;
    const std::uint32_t s = m.load32(reent + kRandState);
    if (any && s == last && !every) return;
    any = true;
    last = s;
    const std::uint32_t root = m.load32(kFrontendRoot);
    const std::uint32_t bits = (root >= 0x08800000u && root < 0x0A000000u) ? m.load32(root + kGameClock) : 0u;
    float clock;
    std::memcpy(&clock, &bits, 4);
    std::cout << "[pure] rand frame " << frame << " t=" << kernel().now_us() << " state=" << hex(s)
              << " clock=" << item_f(clock) << " (" << hex(bits) << ")\n";
}

// --- PURE_WATCH_WORDS=ADDR[,ADDR...] -------------------------------------------------------------------------------
// README.md: (task 046) once per flip, the 32-bit words at those guest addresses (hex): `[pure] words frame N t=...:
// 0x... ...`, to compare frame for frame with a PPSSPP log-only breakpoint reading the same words.
void watch_words(Runtime &rt, std::uint64_t frame) {
    static const std::vector<std::uint32_t> addrs = [] {
        std::vector<std::uint32_t> out;
        const char *v = env("WATCH_WORDS");
        if (v == nullptr) return out;
        std::stringstream ss(v);
        std::string item;
        while (std::getline(ss, item, ',')) out.push_back(static_cast<std::uint32_t>(std::strtoul(item.c_str(), nullptr, 16)));
        return out;
    }();
    if (addrs.empty()) return;
    std::cout << "[pure] words frame " << frame << " t=" << kernel().now_us() << ":";
    for (const std::uint32_t a : addrs) std::cout << " " << hex(rt.memory().load32(a));
    std::cout << "\n";
}

// --- PURE_TRACE_RAND=1 ---------------------------------------------------------------------------------------------
// README.md: (task 046) `rand()` (FUN_088E0568) runs as a native copy that counts its callers; each flip prints
// `[pure] rand calls frame N: 0xRA*n ...`. The copy's extra dispatches move the virtual clock, so the run's frame
// times (and with them the race) change unless `PURE_TEST_RACE_CLOCK` replays them.
// The copy is registered at the first flip, after the corpus; the counts are by return address, in call order.
constexpr std::uint32_t kRand = 0x088E0568u;
std::vector<std::pair<std::uint32_t, std::uint32_t>> &rand_calls() {
    static std::vector<std::pair<std::uint32_t, std::uint32_t>> calls;
    return calls;
}

void traced_rand(psprecomp::CorpusRuntime &crt, AllegrexContext &ctx) {
    const std::uint32_t ra = ctx.gpr[31];
    auto &calls = rand_calls();
    if (!calls.empty() && calls.back().first == ra) ++calls.back().second;
    else calls.emplace_back(ra, 1u);
    // The game's own body: a0 = reent, a2 = the old state, a1 = the new one (state * 1103515245 + 12345),
    // v0 = the new state & 0x7fffffff.
    ctx.gpr[4] = crt.aot_load32(kReentPtr);
    ctx.gpr[6] = crt.aot_load32(ctx.gpr[4] + kRandState);
    const std::uint32_t s = ctx.gpr[6] * 1103515245u + 12345u;
    crt.aot_store32(ctx.gpr[4] + kRandState, s);
    ctx.gpr[5] = s;
    ctx.gpr[2] = s & 0x7FFFFFFFu;
    ctx.lo = s - 12345u;
    ctx.pc = ra;
}

void trace_rand(Runtime &rt, std::uint64_t frame) {
    static const bool on = env_on("TRACE_RAND");
    if (!on) return;
    static bool installed = false;
    if (!installed) {
        installed = true;
        rt.register_function(kRand, &traced_rand, "pure_trace_rand");
    }
    auto &calls = rand_calls();
    if (calls.empty()) return;
    std::cout << "[pure] rand calls frame " << frame << ":";
    for (const auto &[ra, n] : calls) std::cout << " " << hex(ra) << "*" << n;
    std::cout << "\n";
    calls.clear();
}

// --- PURE_TRACE_CALLS=lib:0xNID[,lib:0xNID...] ---------------------------------------------------------------------
// README.md: (task 005) wraps the named HLE calls (NIDs from `config/imports.csv`; the registrar resolves names only
// for its own table) and prints each call's arguments, result and virtual time (`[call] lib:0xNID a0=... a1=... a2=...
// a3=... v0=... t=...`, the registers in hex); `[pure] TRACE_CALLS: nothing bound for lib:0xNID` when nothing is
// bound there yet. A probe for whatever is chased (`tools/scorecard.py` counts flips with `sceDisplay:0x289D82FE`).
// It wraps what is bound when install() runs: the profile's flip counter (bound before it) and the race clock's
// sceKernelGetSystemTimeWide among them; the audio capture and sceKernelGetGPI are bound after it and replace or wrap
// what it wrapped, as they did when this lived in the profile.
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

// --- PURE_VFPU_DOT=ppsspp|psp --------------------------------------------------------------------------------------
// README.md: (patch 0009-vfpu-rounding, D-013; test only) the rounding of the VFPU's dot products: `psp`, the
// default, rounds as a real PSP does (pspautotests' rule); `ppsspp` rounds as PPSSPP's JIT does (a fused chain), so a
// run can be compared with PPSSPP's references bit for bit. `PURE_TEST_RACE_CLOCK` selects `ppsspp` by itself: the
// reference race is PPSSPP's.
// Set once, at the first flip; the race clock's own choice is made earlier (at start-up, when its file is read), so
// this switch, when set, wins over it.
void vfpu_dot() {
    static const bool vfpu_dot_set = [] {
        if (const char *m = env("VFPU_DOT"); m != nullptr && *m != '\0')
            psprecomp::AllegrexContext::vfpu_dot_mode() = std::strcmp(m, "ppsspp") == 0 ? 1u : 0u;
        return true;
    }();
    (void)vfpu_dot_set;
}

// --- PURE_TEST_NO_DAMAGE=1 -----------------------------------------------------------------------------------------
// README.md: (task 017) before every flip the player's shield (`be::Ship` +0xF8) is set back to its full value (the
// ship type's maximum, `*(*(ship + 0xC8) + 0x74) + 0x84`), so contacts never destroy the ship. For
// `tools/campaign_sweep.py --no-damage`, which only has to reach every results screen to look for halts.
// A test instrument, never for play: only the field is written (the HUD's warning follows it at the next hit).
// Announced once at start-up as `[pure] TEST SWITCH: no damage`.
void no_damage_start() {
    if (env_on("TEST_NO_DAMAGE"))
        std::cout << "[pure] TEST SWITCH: no damage (PURE_TEST_NO_DAMAGE=1: the player's shield is refilled every "
                     "flip; a sweep instrument, never for play)\n";
}

void test_no_damage(Runtime &rt, std::uint32_t ship) {
    if (ship == 0u) return;
    const float full = ship_shield_max(rt, ship);
    if (full <= 0.0f) return;
    std::uint32_t u;
    std::memcpy(&u, &full, 4);
    rt.memory().store32(ship + kShipShield, u);
}

// --- PURE_TEST_RACE_CLOCK=FILE -------------------------------------------------------------------------------------
// README.md: (task 046) one race on PPSSPP's clock, for the scorecard's AI rows (`tools/ai_seed_check.sh` writes the
// files; `SCORECARD_RACE_CLOCK=DIR` makes `tools/scorecard.py` pass `DIR/<track>.txt`): `team 0x...` and `race 0x...`
// are the seeds the AI team pick (FUN_0880e0d0) and the billboard shuffle (FUN_0886011c) pass `srand()`, which is
// replaced by a native copy that stores them; `frame N` lines are PPSSPP's answers to the frame timer's
// `sceKernelGetSystemTimeWide` (return address 0x08804428), replayed as differences from the race seed on (the port's
// own differences after the last); `unlocked 0|1` decides `sceKernelGetGPI` as the reference's route had it, over
// `PURE_TEST_UNLOCK_ALL`. Every other caller of the clock gets the port's time. Prints `[pure] TEST SWITCH: race clock
// ...`, `[pure] srand from ... pinned to ...` and `[pure] frame times replayed from here: N answers`.
//
// A test instrument for the scorecard's trajectory runs, never for play: the clock one race reads, as PPSSPP's
// reference run of that race read it, so the port's race can be compared with PPSSPP's ship for ship
// (docs/fidelity.md difference 13). FILE is text, `#` comments, one item a line:
//   team 0x...   the seed the AI team pick passes srand(): FUN_0880e0d0 (srand's return address 0x0880E160), which
//                draws the order of the seven AI teams on the grid, seeds with the low word of
//                sceKernelGetSystemTimeWide, the microseconds since boot at the TEAM SELECTION confirm;
//   race 0x...   the seed of the race's random sequence: the billboard shuffle the Billboard constructor runs while
//                the race loads (FUN_0886011c, return address 0x08860150) seeds with the bits of the float at the
//                frontend root's +0x44, the game's own clock in seconds since the frontend started; every later
//                rand() of the race (the AI's choices among them) continues this sequence;
//   frame N      PPSSPP's answers to the frame timer's sceKernelGetSystemTimeWide (FUN_08804390, return address
//                0x08804428), in order: the first is the last one before the race seed, the rest follow it. From
//                the race seed on, the port's frame timer is answered with the same differences, so each frame's
//                measured time (dt, capped at 0.067 s) is PPSSPP's; when the list runs out it continues with the
//                port's own differences. Every other caller of the clock gets the port's own time;
//   unlocked 0|1 whether the reference's route had everything unlocked (the Beta and Classic routes run the game's
//                own unlock code, the Alpha routes unlock nothing): the AI team pick draws only from unlocked teams
//                (FUN_088b43d4), and PURE_TEST_UNLOCK_ALL adds ZONE and MEDIEVIL to a new profile's eight, so the
//                file's value decides what sceKernelGetGPI answers (1 or 0), whatever PURE_TEST_UNLOCK_ALL says.
// The seeds are clock readings at the moment the player confirms: on a PSP they differ from play to play, and between
// the port's and PPSSPP's scripted routes. The frame times are where the port's clock differs in kind: it advances in
// 1 ms quanta (the kernel's starvation tick), so its frame times jitter by +-1 ms where PPSSPP's follow each frame's
// emulated CPU time. srand() (FUN_088E0558) is replaced by a native copy that stores the pinned seed for the two
// callers (the given one for every other), registered at the first flip, after the corpus, and only with the switch.
constexpr std::uint32_t kSrand = 0x088E0558u;
constexpr std::uint32_t kSrandFromTeamPick = 0x0880E160u;
constexpr std::uint32_t kSrandFromBillboards = 0x08860150u;
constexpr std::uint32_t kFrameTimerReturn = 0x08804428u;
constexpr std::uint32_t kNidGetSystemTimeWide = 0x82BC5777u;

struct RaceClock {
    bool on = false;
    std::string path;
    std::optional<std::uint32_t> team, race;
    std::vector<std::uint64_t> frames;
    std::optional<bool> unlocked;
};

const RaceClock &race_clock() {
    static const RaceClock clock = [] {
        RaceClock c;
        const char *v = env("TEST_RACE_CLOCK");
        if (v == nullptr || *v == '\0') return c;
        c.path = v;
        std::ifstream in(c.path);
        if (!in) {
            std::cout << "[pure] PURE_TEST_RACE_CLOCK=" << c.path << ": cannot read it; ignored\n";
            return c;
        }
        std::string line;
        while (std::getline(in, line)) {
            std::istringstream ls(line);
            std::string key, value;
            if (!(ls >> key >> value) || key[0] == '#') continue;
            const unsigned long long x = std::strtoull(value.c_str(), nullptr, 0);
            if (key == "team") c.team = static_cast<std::uint32_t>(x);
            else if (key == "race") c.race = static_cast<std::uint32_t>(x);
            else if (key == "frame") c.frames.push_back(x);
            else if (key == "unlocked") c.unlocked = x != 0u;
        }
        c.on = c.team.has_value() || c.race.has_value() || c.frames.size() > 1u;
        if (!c.on) std::cout << "[pure] PURE_TEST_RACE_CLOCK=" << c.path << " holds no seed and no frame times; ignored\n";
        // The reference race is PPSSPP's: its dot-product rounding too (D-013).
        psprecomp::AllegrexContext::vfpu_dot_mode() = 1u;
        return c;
    }();
    return clock;
}

// The frame timer's replay: armed by the race seed's srand(), then one answer a frame-timer call.
struct FrameReplay {
    bool armed = false;
    std::size_t next = 1u;           // index into race_clock().frames of the next answer
    std::uint64_t base = 0u;         // the port's last frame-timer answer before the race seed
    std::uint64_t last_answer = 0u;  // the last answer given (replayed or the port's own)
    std::uint64_t last_now = 0u;     // the port's clock at that answer
    bool said_end = false;
};
FrameReplay &frame_replay() {
    static FrameReplay r;
    return r;
}

void pinned_srand(psprecomp::CorpusRuntime &crt, AllegrexContext &ctx) {
    const RaceClock &clock = race_clock();
    const std::uint32_t ra = ctx.gpr[31];
    std::uint32_t seed = ctx.gpr[4];
    const std::optional<std::uint32_t> &want = ra == kSrandFromTeamPick ? clock.team
                                               : ra == kSrandFromBillboards ? clock.race : std::optional<std::uint32_t>{};
    if (want) {
        std::cout << "[pure] srand from " << hex(ra) << " t=" << kernel().now_us() << " seed " << hex(seed)
                  << " pinned to " << hex(*want) << "\n";
        seed = *want;
    }
    if (ra == kSrandFromBillboards && clock.frames.size() > 1u) {
        FrameReplay &r = frame_replay();
        r.armed = true;
        r.next = 1u;
        r.base = r.last_answer;
        r.said_end = false;
        std::cout << "[pure] frame times replayed from here: " << clock.frames.size() - 1u << " answers\n";
    }
    // The game's own body: a1 = the reent pointer; reent->rand_next = a0; return.
    ctx.gpr[5] = crt.aot_load32(kReentPtr);
    crt.aot_store32(ctx.gpr[5] + kRandState, seed);
    ctx.pc = ra;
}

// Per flip: the native srand(), registered at the first flip (after the corpus).
void install_race_clock(Runtime &rt) {
    static bool done = false;
    if (done || !race_clock().on) return;
    done = true;
    rt.register_function(kSrand, &pinned_srand, "pure_test_srand");
}

// sceKernelGetSystemTimeWide with the replay: the frame timer's calls answered from the file once armed.
void wrap_frame_timer(HleRegistrar &hle) {
    if (race_clock().frames.size() <= 1u) return;
    static HleFunction original = hle.bound_function("ThreadManForUser", kNidGetSystemTimeWide);
    if (!original) return;
    hle.bind("ThreadManForUser", kNidGetSystemTimeWide, [](Runtime &rt, AllegrexContext &ctx) {
        if (ctx.gpr[31] != kFrameTimerReturn) {
            original(rt, ctx);
            return;
        }
        FrameReplay &r = frame_replay();
        const auto &frames = race_clock().frames;
        const std::uint64_t now = kernel().now_us();
        std::uint64_t answer = now;
        if (r.armed && r.next < frames.size()) {
            answer = r.base + (frames[r.next] - frames[0]);
            ++r.next;
        } else if (r.armed) {
            if (!r.said_end) {
                r.said_end = true;
                std::cout << "[pure] frame times: the replay ran out at t=" << now << "; the port's own from here\n";
            }
            answer = r.last_answer + (now - r.last_now);
        }
        r.last_answer = answer;
        r.last_now = now;
        kernel().finish64(ctx, answer);
    });
}

// At start-up: reads the file (the first race_clock() call), announces the switch, and wraps the frame timer.
void race_clock_start(HleRegistrar &hle) {
    if (race_clock().on) {
        const auto show = [](const std::optional<std::uint32_t> &w) { return w ? hex(*w) : std::string("-"); };
        const std::size_t n = race_clock().frames.empty() ? 0u : race_clock().frames.size() - 1u;
        std::cout << "[pure] TEST SWITCH: race clock (PURE_TEST_RACE_CLOCK=" << race_clock().path << ": the AI team "
                  << "pick's seed " << show(race_clock().team) << ", the race's seed " << show(race_clock().race) << ", "
                  << n << " frame times; a scorecard instrument, never for play)\n";
    }
    wrap_frame_timer(hle);
}

// --- PURE_TEST_UNLOCK_ALL=1 ----------------------------------------------------------------------------------------
// README.md: (task 032) `sceKernelGetGPI` returns 1 (bit 0 only; retail reads 0). Every frontend lock check reads
// `unlocked = (GPI & 1) ? 1 : profile->0x381` (the profile byte the main menu's hidden button sequence sets,
// "Everything"), so on any profile, also a new one, CLASS SELECTION lists VECTOR, VENOM, FLASH, RAPIER, PHANTOM (a new
// profile: VECTOR, VENOM), LEAGUE SELECTION ALPHA, BETA, CLASSIC (a new profile: ALPHA), Zone's TRACK SELECTION PRO
// TOZO, MALLAVOL, CORIDON 12, SYNCOPIA (a new profile: PRO TOZO), and TEAM SELECTION adds ZONE and MEDIEVIL after the
// eight teams. Nothing else changes: a 2200-flip frontend run is pixel-identical with and without it. For
// `tools/campaign_sweep.py`, which sets it for the cells that need it (docs/tracks.md).
//
// A test instrument for tools/campaign_sweep.py, never for play. The lock checks are FUN_088b43d4, FUN_0894fa5c and
// FUN_089516b8; the profile byte is what the main menu's hidden button sequence in FUN_0894d4c8 sets. Bits
// 0x20/0x40/0x80, the frame limiter's and the display mode's (FUN_0886511c), stay 0; the game copies GPI to GPO each
// frame (FUN_08804390), which the framework ignores. PURE_TEST_RACE_CLOCK's `unlocked` (above) takes precedence: the
// race as PPSSPP's reference route ran it. Returns the answer, which the profile gives sceKernelGetGPI.
std::uint32_t unlock_all_start() {
    const bool unlock_all = race_clock().unlocked ? *race_clock().unlocked : env_on("TEST_UNLOCK_ALL");
    if (race_clock().unlocked && *race_clock().unlocked != env_on("TEST_UNLOCK_ALL"))
        std::cout << "[pure] PURE_TEST_RACE_CLOCK: unlocked " << (unlock_all ? 1 : 0)
                  << " (the reference's route), so sceKernelGetGPI returns " << (unlock_all ? 1 : 0) << "\n";
    if (unlock_all)
        std::cout << "[pure] TEST SWITCH: unlock all (PURE_TEST_UNLOCK_ALL=1: sceKernelGetGPI returns 1, which the "
                     "frontend's lock checks read as everything unlocked; a sweep instrument, never for play)\n";
    return unlock_all ? 1u : 0u;
}

} // namespace

Hooks install(HleRegistrar &hle) {
    race_clock_start(hle);
    no_damage_start();
    wrap_call_traces(hle);
    Hooks hooks;
    hooks.gpi = unlock_all_start();
    return hooks;
}

void flip(Runtime &rt, std::uint64_t frame) {
    install_race_clock(rt);
    trace_rand(rt, frame);
    watch_words(rt, frame);
    vfpu_dot();
    static const bool watch = env_on("WATCH_SHIP"), no_damage = env_on("TEST_NO_DAMAGE"), grid = env_on("WATCH_GRID");
    watch_rand(rt, frame);
    if (watch || no_damage || grid) {
        const std::uint32_t ship = player_ship(rt, frame);
        if (watch) watch_ship(rt, frame, ship);
        if (grid) watch_grid(rt, frame, ship);
        if (no_damage) test_no_damage(rt, ship);
    }
}

} // namespace portablekit::test_hooks

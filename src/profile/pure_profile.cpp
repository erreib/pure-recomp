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
#include <fstream>
#include <optional>
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
    {"UCUS98612P0000", "Profile 1", true},   // the game's list starts at P0000 (task 014)
    {"UCUS98612P0001", "Profile 2", true},
    {"UCUS98612P0002", "Profile 3", true},
    {"UCUS98612P0003", "Profile 4", true},
    {"UCUS98612P0004", "Profile 5", true},
};

void return_zero(Runtime &, AllegrexContext &ctx) { kernel().finish(ctx, 0u); }
void return_one(Runtime &, AllegrexContext &ctx) { kernel().finish(ctx, 1u); }

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
// it, printed when it changes (`[pure] ship frame N t=... clock=... pos=... vel=... kmh=... dist=... lap=...
// shield=...`). The race records are a .bss array of 0x1C0-byte entries, one per ship; relative to entry k's position
// vector at 0x08B72010 + k * 0x1C0: -0x20 velocity (m/s; the HUD speed is |v| * 3.6), +0 position (x, y, z, 1; the
// same as the ship object's matrix row at +0x70), +0x10 lap counter, +0x14 the entry's ship index, +0x18 distance
// along the track, +0x1C race clock (s). The player's entry is found through its be::Ship object (vtable 0x08AC259C
// at +0x3c, set by LinkObj_etc__089261ac): +0x480 ship index, +0x488 kind (0/1 player, 2/3 AI), +0xcc AI flag. The
// objects are found by scanning user RAM every 30 flips until one is there, and again when the race is torn down.
// `shield` is the ship object's own field (below), not the race record's.
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

bool env_on(const char *name) { const char *v = env(name); return v != nullptr && *v != '\0' && *v != '0'; }

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
        std::cout << "[pure] ship frame " << frame << " player object " << item_hex(ship) << " index "
                  << m.load32(ship + 0x480u) << "\n";
    }
    return ship;
}

float load_float(Runtime &rt, std::uint32_t a) {
    const std::uint32_t u = rt.memory().load32(a);
    float x;
    std::memcpy(&x, &u, 4);
    return x;
}

// The ship type's full shield, the setter's clamp; 0 when the type data is not there yet.
float ship_shield_max(Runtime &rt, std::uint32_t ship) {
    const auto &m = rt.memory();
    const std::uint32_t sim = m.load32(ship + 0xC8u);
    if (sim < 0x08800000u || sim >= 0x0A000000u) return 0.0f;
    const std::uint32_t type = m.load32(sim + 0x74u);
    if (type < 0x08800000u || type >= 0x0A000000u) return 0.0f;
    const float full = load_float(rt, type + 0x84u);
    return std::isfinite(full) && full > 0.0f ? full : 0.0f;
}

std::string item_f(float v) { char b[24]; std::snprintf(b, sizeof b, "%.3f", static_cast<double>(v)); return b; }

void watch_ship(Runtime &rt, std::uint64_t frame, std::uint32_t ship) {
    static std::string last;
    if (ship == 0u) return;
    const auto &m = rt.memory();
    const std::uint32_t rec = kRaceRecordPos + m.load32(ship + 0x480u) * kRaceRecordStride;
    const auto f = [&rt](std::uint32_t a) { return load_float(rt, a); };
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

// PURE_WATCH_GRID=1 (task 032): during a race (while the player's ship object is there), once per flip, every entry
// of the race record array, k = 0..7, printed when it changes: `[pure] grid frame N k=K clock=C pos=x,y,z
// vel=vx,vy,vz dist=D lap=L`, the ship probe's race-record fields for each ship (entry k is the ship with index k;
// the player's is the index the `player object` line names, 7 on a Single Race grid). tools/pp_lines.py --port turns
// a log of these lines into a racing line from the port's own AI ships.
void watch_grid(Runtime &rt, std::uint64_t frame, std::uint32_t ship) {
    static std::string last[8];
    if (ship == 0u) {
        for (auto &l : last) l.clear();
        return;
    }
    const auto &m = rt.memory();
    const auto f = [&rt](std::uint32_t a) { return load_float(rt, a); };
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

// PURE_WATCH_RAND=1 (task 046): once per flip, the game's libc rand() state, printed when it changes (=2: every flip):
// `[pure] rand frame N t=... state=0x... clock=S (0x...)`. rand() is FUN_088e0568 (state = state * 1103515245 + 12345,
// returns state & 0x7fffffff), srand() FUN_088e0558; the state is the word at +0x58 of the reent structure the pointer
// at 0x08AB1A6C names. The AI, the particles, the weather, the billboards and the replay camera all draw from it.
// `clock` is the game's own clock, the float at +0x44 of the frontend root (DAT_08b17c18): seconds since the frontend
// started, summed from each frame's measured time (FUN_08804390, capped at 0.067 s a frame), the race seed's source.
constexpr std::uint32_t kReentPtr = 0x08AB1A6Cu;
constexpr std::uint32_t kRandState = 0x58u;
constexpr std::uint32_t kFrontendRoot = 0x08B17C18u;
constexpr std::uint32_t kGameClock = 0x44u;

void watch_rand(Runtime &rt, std::uint64_t frame) {
    static const char *v = env("WATCH_RAND");
    static const bool on = v != nullptr && *v != '\0' && *v != '0', every = on && std::strcmp(v, "2") == 0;
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
    std::cout << "[pure] rand frame " << frame << " t=" << kernel().now_us() << " state=" << item_hex(s)
              << " clock=" << item_f(clock) << " (" << item_hex(bits) << ")\n";
}

// PURE_TEST_RACE_CLOCK=FILE (task 046), a test instrument for the scorecard's trajectory runs, never for play: the
// clock one race reads, as PPSSPP's reference run of that race read it, so the port's race can be compared with
// PPSSPP's ship for ship (docs/fidelity.md difference 13). FILE is text, `#` comments, one item a line:
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
        std::cout << "[pure] srand from " << item_hex(ra) << " t=" << kernel().now_us() << " seed " << item_hex(seed)
                  << " pinned to " << item_hex(*want) << "\n";
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

// PURE_WATCH_WORDS=ADDR[,ADDR...] (task 046), a probe: once per flip, the 32-bit words at those guest addresses (hex),
// `[pure] words frame N t=...: 0x... 0x...`, for comparing with a PPSSPP log-only breakpoint on the same words.
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
    for (const std::uint32_t a : addrs) std::cout << " " << item_hex(rt.memory().load32(a));
    std::cout << "\n";
}

// PURE_TRACE_RAND=1 (task 046), a probe: rand() (FUN_088E0568) is replaced by a native copy that counts its callers
// (return addresses), and each flip prints the frame's counts: `[pure] rand calls frame N: 0xRA*n ...`.
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
    for (const auto &[ra, n] : calls) std::cout << " " << item_hex(ra) << "*" << n;
    std::cout << "\n";
    calls.clear();
}

// PURE_TEST_NO_DAMAGE=1 (task 017), a test instrument for tools/campaign_sweep.py, never for play: before each flip
// the player's shield (+0xF8) is set back to its full value, so contacts never destroy the ship and the sweep can
// run a track to its results screen to look for halts. Only the field is written (the HUD's warning follows it at
// the next hit). Announced once at start-up as `[pure] TEST SWITCH: no damage`.
void test_no_damage(Runtime &rt, std::uint32_t ship) {
    if (ship == 0u) return;
    const float full = ship_shield_max(rt, ship);
    if (full <= 0.0f) return;
    std::uint32_t u;
    std::memcpy(&u, &full, 4);
    rt.memory().store32(ship + kShipShield, u);
}

// PURE_PACED_FROM=N (task 034), for the tools: the kernel's clock runs unpaced (Kernel::set_paced(false), patch
// 0011) from start-up until flip N, and is held to real time (set_paced(true)) from flip N on, whatever the shell.
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
        install_race_clock(rt);
        trace_rand(rt, frames);
        watch_words(rt, frames);
        apply_paced_from(frames);
        if (log_every != 0u && frames % log_every == 0u) std::cout << "[pure] frame " << frames << "\n";
        static const bool watch = env_on("WATCH_SHIP"), no_damage = env_on("TEST_NO_DAMAGE"),
                          grid = env_on("WATCH_GRID");
        watch_movie(rt, frames);
        watch_rand(rt, frames);
        if (watch || no_damage || grid) {
            const std::uint32_t ship = player_ship(rt, frames);
            if (watch) watch_ship(rt, frames, ship);
            if (grid) watch_grid(rt, frames, ship);
            if (no_damage) test_no_damage(rt, ship);
        }
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
    if (race_clock().on) {
        const auto show = [](const std::optional<std::uint32_t> &w) { return w ? item_hex(*w) : std::string("-"); };
        const std::size_t n = race_clock().frames.empty() ? 0u : race_clock().frames.size() - 1u;
        std::cout << "[pure] TEST SWITCH: race clock (PURE_TEST_RACE_CLOCK=" << race_clock().path << ": the AI team "
                  << "pick's seed " << show(race_clock().team) << ", the race's seed " << show(race_clock().race) << ", "
                  << n << " frame times; a scorecard instrument, never for play)\n";
    }
    if (env_on("TEST_NO_DAMAGE"))
        std::cout << "[pure] TEST SWITCH: no damage (PURE_TEST_NO_DAMAGE=1: the player's shield is refilled every "
                     "flip; a sweep instrument, never for play)\n";
    if (const auto from = paced_from()) {
        // The shell (register_media, before this hook) has set the pace from its window; the switch wins from here.
        std::cout << "[pure] PURE_PACED_FROM=" << *from
                  << (*from == 0u ? ": paced to real time from the start\n"
                                  : ": unpaced until that flip, paced to real time from it\n");
        apply_paced_from(0u);
    }
    wrap_flip_counter(hle);
    wrap_frame_timer(hle);
    wrap_call_traces(hle);
    register_audio_capture(hle);

    // The dev-kit switch block. Retail reads 0, which selects display mode 0 and the normal pacing path
    // (docs/timing.md).
    // PURE_TEST_UNLOCK_ALL=1 (task 032), a test instrument for tools/campaign_sweep.py, never for play: GPI reads 1
    // (bit 0 only). Every frontend lock check reads `unlocked = (sceKernelGetGPI() & 1) ? 1 : profile->0x381`
    // (FUN_088b43d4, FUN_0894fa5c, FUN_089516b8; the profile byte is what the main menu's hidden button sequence in
    // FUN_0894d4c8 sets, "Everything"), so every class, league and track is open on any profile. Bits 0x20/0x40/0x80,
    // the frame limiter's and the display mode's (FUN_0886511c), stay 0; the game copies GPI to GPO each frame
    // (FUN_08804390), which the framework ignores.
    // PURE_TEST_RACE_CLOCK's `unlocked` (above) takes precedence: the race as PPSSPP's reference route ran it.
    const bool unlock_all = race_clock().unlocked ? *race_clock().unlocked : env_on("TEST_UNLOCK_ALL");
    if (race_clock().unlocked && *race_clock().unlocked != env_on("TEST_UNLOCK_ALL"))
        std::cout << "[pure] PURE_TEST_RACE_CLOCK: unlocked " << (unlock_all ? 1 : 0)
                  << " (the reference's route), so sceKernelGetGPI returns " << (unlock_all ? 1 : 0) << "\n";
    if (unlock_all)
        std::cout << "[pure] TEST SWITCH: unlock all (PURE_TEST_UNLOCK_ALL=1: sceKernelGetGPI returns 1, which the "
                     "frontend's lock checks read as everything unlocked; a sweep instrument, never for play)\n";
    hle.add("UtilsForUser", "sceKernelGetGPI", unlock_all ? return_one : return_zero);

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

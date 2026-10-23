// The shield effect at the display's rate (shield_step.hpp says what is here; docs/timing.md "The shield effect (task
// 107)" holds the diagnosis).
//
// The Shield (Backend/Weapons/Shield.cpp) is a LinkObj the ship makes when it raises its shield
// (LinkObj_h__0892425c: it kills the ship's earlier one, constructs this one with FUN_08946054 and keeps it at the
// ship's +0x9fc). Its vtable 0x08AC2ACC has the update FUN_08946918(float dt in f12, Shield *this in a0) in the slot
// FUN_08893284 calls once a frame (+0x24); a 0 return marks the object dead and the walker skips it from then on.
// Fields: +0xc0 the owner ship, +0xc4 the dying flag, +0x108..+0x114 the target colour (RGBA floats), +0x118..+0x124
// the colour, +0x128 the colour's ease (0.15), +0x12c the target scale (1.0), +0x130 the scale (0.7 at start), +0x134
// the scale's ease (0.2), +0x15c the effect's clock (s), +0x160/+0x164 the two shells (vr_shield_cockpit.vex,
// vr_shield.vex). A contact (FUN_08947030, from the ship's update FUN_08926ae4 and FUN_0892935c) sets the colour to
// the flash colour outright and the scale to 1.1; the shield's end (FUN_08947080, from FUN_089243ec) sets the target
// colour to 0, the target scale to 1.2 and the dying flag. The update:
//   n = (int)(dt / 0.016666668);  for n steps colour += 0.15 * (target - colour);  for n steps scale += 0.2 * (1 - scale)
//   pulse = sin(clock * 15), the shells' colour (alpha * (0.75 + 0.25 pulse)) and scale matrix;  clock += dt
//   if (dying && colour.a <= 0.1) { mark dead; return 0; }  return 1;
// At 59.94 Hz n is 1 on most frames; at 119.40 Hz (a frame's dt 7.4 to 9.4 ms on the port's clock) it is 0 on every
// one, so nothing eases: the effect never builds up, a contact's flash stays, and the dying effect never fades to its
// delete test.
#include "shield_step.hpp"

#include "../helpers.hpp"
#include "kernel/kernel.hpp"

#include <bit>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <unordered_map>
#include <vector>

namespace portablekit::shield_step {
namespace {

using pure::env_on;
using pure::hex;
using pure::load_float;

constexpr std::uint32_t kShieldVtable = 0x08AC2ACCu;  // set by the constructor FUN_08946054
constexpr std::uint32_t kShipVtable = 0x08AC259Cu;    // be::Ship (test_hooks.cpp)
constexpr std::uint32_t kVtable = 0x3Cu;
constexpr std::uint32_t kFlags = 0x2Cu;               // LinkObj flags: 8 dead (the walker skips it)
constexpr std::uint32_t kDead = 8u;
constexpr std::uint32_t kOwner = 0xC0u;
constexpr std::uint32_t kDying = 0xC4u;
constexpr std::uint32_t kTargetAlpha = 0x114u;
constexpr std::uint32_t kColour = 0x118u;             // r, g, b, a
constexpr std::uint32_t kAlpha = 0x124u;
constexpr std::uint32_t kScale = 0x130u;
constexpr std::uint32_t kClock = 0x15Cu;
constexpr std::uint32_t kShipShield = 0x9FCu;         // the ship's Shield effect (LinkObj_h__0892425c)
constexpr std::uint32_t kShipIndex = 0x480u;
constexpr std::uint32_t kRaceClock = 0x08B7202Cu;     // the race record's clock (s): 0x08B72010 + 0x1C, test_hooks.cpp
constexpr std::uint32_t kRaceRecordStride = 0x1C0u;
constexpr std::uint32_t kUserBase = 0x08800000u, kUserEnd = 0x0A000000u;
constexpr float kFrame = 0.016666668f;                // the update's 1/60 (0x3C888889)

[[nodiscard]] bool user(std::uint32_t a) { return a >= kUserBase && a < kUserEnd - 0x200u; }

std::string f3(float v) {
    char b[24];
    std::snprintf(b, sizeof b, "%.3f", static_cast<double>(v));
    return b;
}

// --- PURE_TRACE_SHIELD=1 ------------------------------------------------------------------------------------------
// Once a flip, every ship's live Shield (the ship's +0x9fc, a Shield owned by it and not dead):
//   [pure] shield frame N ship K obj 0x... t=S clock=S n=N steps=N a=A target=A scale=X dying=0|1
// t the virtual time (s), clock the effect's own (the sum of the dts it was updated with), n the easing steps of the
// flip (the generated code's (int)(dt / (1/60)), dt the clock's advance since the last flip), steps their sum.
// A line when one appears (`new`, with its colour's alpha and target) and when it goes (`end`): how (`deleted`: its
// update deleted it, dying and faded; `replaced`: the ship raised a new one; `killed`: dead otherwise; `gone`: the
// ship or the race went), its life (its clock at the last flip it was live), its rise (the clock when the colour's
// alpha first reached 90% of the target's, `-` never) and its fade (from the dying flag to the end, `-` not dying).
bool trace_on() {
    static const bool on = env_on("TRACE_SHIELD");
    return on;
}

struct Effect {
    std::uint32_t ship = 0u;
    std::uint32_t index = 0u;
    float clock = 0.0f;     // at the last flip it was live
    std::uint64_t steps = 0u;
    float rise = -1.0f;     // the clock at 90% of the target's alpha
    float dying = -1.0f;    // the clock when the dying flag was first seen
    bool seen = false;      // live at this flip
};
std::unordered_map<std::uint32_t, Effect> effects;
std::vector<std::uint32_t> ships;
std::uint64_t last_scan = 0u;

// Every be::Ship in user RAM (the player's and the AI's, index +0x480 under 8).
void scan_ships(const psprecomp::GuestMemory &m) {
    ships.clear();
    constexpr std::uint32_t kSize = 0x01800000u;
    const std::uint8_t *ram = m.raw_pointer(kUserBase, kSize);
    if (ram == nullptr) return;
    for (std::uint32_t off = kVtable; off + 4u <= kSize; off += 4u) {
        std::uint32_t v;
        std::memcpy(&v, ram + off, 4);
        if (v != kShipVtable) continue;
        const std::uint32_t obj = kUserBase + off - kVtable;
        if (m.load32(obj + kShipIndex) < 8u) ships.push_back(obj);
    }
}

void end(std::uint64_t frame, std::uint32_t obj, const Effect &e, const char *how) {
    std::cout << "[pure] shield frame " << frame << " ship " << e.index << " obj " << hex(obj) << " end " << how
              << " life=" << f3(e.clock) << " rise=" << (e.rise >= 0.0f ? f3(e.rise) : "-")
              << " fade=" << (e.dying >= 0.0f ? f3(e.clock - e.dying) : "-") << " steps=" << e.steps << "\n";
}

void trace(psprecomp::Runtime &rt, std::uint64_t frame) {
    const auto &m = rt.memory();
    for (const std::uint32_t s : ships) {
        if (m.load32(s + kVtable) == kShipVtable) continue;
        ships.clear();  // the race torn down
        break;
    }
    if ((ships.empty() && frame - last_scan >= 30u) || frame - last_scan >= 600u) {
        last_scan = frame;
        scan_ships(m);
    }
    for (auto &[obj, e] : effects) e.seen = false;
    const double t = static_cast<double>(kernel().now_us()) / 1e6;
    for (const std::uint32_t ship : ships) {
        const std::uint32_t obj = m.load32(ship + kShipShield);
        if (!user(obj) || m.load32(obj + kVtable) != kShieldVtable || m.load32(obj + kOwner) != ship ||
            (m.load32(obj + kFlags) & kDead) != 0u)
            continue;
        const float clock = load_float(m, obj + kClock);
        const float a = load_float(m, obj + kAlpha), target = load_float(m, obj + kTargetAlpha);
        auto found = effects.find(obj);
        if (found != effects.end() && (found->second.ship != ship || clock < found->second.clock)) {
            end(frame, obj, found->second, "gone");  // another effect at the same address
            effects.erase(found);
            found = effects.end();
        }
        const bool fresh = found == effects.end();
        Effect &e = fresh ? effects[obj] : found->second;
        if (fresh) {
            e.ship = ship;
            e.index = m.load32(ship + kShipIndex);
            std::cout << "[pure] shield frame " << frame << " ship " << e.index << " obj " << hex(obj) << " new t="
                      << f3(static_cast<float>(t)) << " race="
                      << f3(load_float(m, kRaceClock + e.index * kRaceRecordStride)) << " a=" << f3(a)
                      << " target=" << f3(target) << "\n";
        }
        const int n = fresh ? 0 : static_cast<int>((clock - e.clock) / kFrame);
        e.steps += static_cast<std::uint64_t>(n > 0 ? n : 0);
        e.clock = clock;
        e.seen = true;
        const bool dying = m.load8(obj + kDying) != 0u;
        if (dying && e.dying < 0.0f) e.dying = clock;
        if (e.rise < 0.0f && target > 0.0f && a >= 0.9f * target) e.rise = clock;
        std::cout << "[pure] shield frame " << frame << " ship " << e.index << " obj " << hex(obj) << " t="
                  << f3(static_cast<float>(t)) << " clock=" << f3(clock) << " n=" << n << " steps=" << e.steps
                  << " a=" << f3(a) << " target=" << f3(target) << " scale=" << f3(load_float(m, obj + kScale))
                  << " dying=" << (dying ? 1 : 0) << "\n";
    }
    for (auto it = effects.begin(); it != effects.end();) {
        if (it->second.seen) {
            ++it;
            continue;
        }
        const std::uint32_t obj = it->first;
        const Effect &e = it->second;
        const char *how = "gone";
        if (m.load32(e.ship + kVtable) == kShipVtable) {
            if (m.load32(e.ship + kShipShield) != obj)
                how = "replaced";
            else if (e.dying >= 0.0f)
                how = "deleted";
            else
                how = "killed";
        }
        end(frame, obj, e, how);
        it = effects.erase(it);
    }
}

} // namespace

void frame(psprecomp::Runtime &) {}

void flip(psprecomp::Runtime &rt, std::uint64_t frame) {
    if (trace_on()) trace(rt, frame);
}

} // namespace portablekit::shield_step

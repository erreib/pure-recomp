// Small helpers more than one of our sources uses, each written once (task 093): a switch read as on or off, a
// number in hex, a float from guest memory.
#pragma once

#include "profile.hpp"  // portablekit::env
#include "psprecomp/guest_memory.hpp"

#include <bit>
#include <cstdint>
#include <cstdio>
#include <string>

namespace pure {

// PURE_<name> as an on/off switch: on when set to a value that does not start with 0 (`1` on, `0` off), and
// `unset` when it is not set or empty. A switch that is on when merely set, the framework's convention for its own
// names, is read with portablekit::env_set instead.
inline bool env_on(const char *name, bool unset = false) {
    const char *value = portablekit::env(name);
    return value == nullptr || *value == '\0' ? unset : *value != '0';
}

// `value` as 0x and `digits` upper-case hex digits.
inline std::string hex(std::uint32_t value, int digits = 8) {
    char text[16];
    std::snprintf(text, sizeof text, "0x%0*X", digits, value);
    return text;
}

// The float the game keeps at `address`.
inline float load_float(const psprecomp::GuestMemory &memory, std::uint32_t address) {
    return std::bit_cast<float>(memory.load32(address));
}

} // namespace pure

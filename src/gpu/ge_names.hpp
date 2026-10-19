// The names the GE's primitive types and texture formats are printed with (task 093): the Metal backend's lines
// (PURE_METAL_LOG's draws, the texture warnings) and ge_replay's description of a differing draw. Plain C++ with no
// Metal in it, so ge_replay, which every platform builds, includes it too.
#pragma once

#include "gpu/ge_state.hpp"

#include <cstddef>
#include <iterator>

namespace pure::gpu {

inline const char *primitive_name(portablekit::gpu::PrimitiveType type) {
    static constexpr const char *kNames[] = {"points", "lines", "linestrip", "triangles", "tristrip", "trifan", "sprites"};
    const auto index = static_cast<std::size_t>(type);
    return index < std::size(kNames) ? kNames[index] : "?";
}

inline const char *texture_format_name(portablekit::gpu::TextureFormat format) {
    static constexpr const char *kNames[] = {"5650",   "5551",   "4444", "8888", "CLUT4", "CLUT8",
                                             "CLUT16", "CLUT32", "DXT1", "DXT3", "DXT5"};
    const auto index = static_cast<std::size_t>(format);
    return index < std::size(kNames) ? kNames[index] : "?";
}

} // namespace pure::gpu

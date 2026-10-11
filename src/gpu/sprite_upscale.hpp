// The sprite upscale (task 073, E7, D-018; docs/metal-backend.md, "Sprite upscale"): a texture of the menus' and the
// HUD's bitmap art, W x H RGBA8, redrawn 4W x 4H with an edge-preserving resample, the planning session's prototype
// (out/fe_tex/upscale_proto.py) in C++. The Metal backend calls it at decode for the textures of 2D draws;
// tools/sprite_proto_check.py runs the prototype's maths on the same input and compares. Plain C++, no Metal.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace pure::gpu {

// Output texels per input texel along each axis.
constexpr std::uint32_t kSpriteScale = 4u;

// `pixels`: width x height texels, 4 bytes each (red, green, blue, alpha), rows of `width`, top first. `out` becomes
// (4 width) x (4 height) texels in the same layout:
//   - each texel's colour premultiplied by its coverage, the alpha over the texture's peak alpha (the largest in it);
//   - separable Catmull-Rom at 4x, rows first, the four taps' weights (-t^3 + 2t^2 - t)/2, (3t^3 - 5t^2 + 2)/2,
//     (-3t^3 + 4t^2 + t)/2, (t^3 - t^2)/2 at the fraction t of the sample centre (o + 0.5)/4 - 0.5, the taps clamped
//     at the edges;
//   - the coverage clamped to 0..1, the colour divided by it (0 where it is at most 0.001) and clamped to 0..255;
//   - a mask-like texture (at least 60% of its texels at alpha 0 or within 1 of the peak) takes its coverage through
//     a smoothstep of half-width 0.22 about 0.5, crisp antialiased outlines; any other keeps the resampled coverage;
//   - the alpha the coverage times the peak, each channel rounded to the nearest level.
// In double precision with the prototype's operations in its order, so the result is the prototype's to the level.
// One departure, for a case the prototype's inputs do not have: a texture whose alpha is 0 everywhere has its colour
// resampled as if every texel covered (the prototype would turn it black) and keeps alpha 0.
void upscale_sprite(const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height,
                    std::vector<std::uint8_t> &out);

// Writes width x height texels in the layout above as an RGBA PNG at `path`, with the stb_image_write the framework
// vendors (third_party/stb_image_write.h). False when the file cannot be written. For PURE_SPRITE_DUMP.
bool write_png(const std::string &path, const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height);

} // namespace pure::gpu

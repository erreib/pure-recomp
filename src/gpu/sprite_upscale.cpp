// See sprite_upscale.hpp.
#include "sprite_upscale.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>

#define STBI_WRITE_NO_STDIO
#define STB_IMAGE_WRITE_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <fstream>

// The prototype's sums, a product added at a time in its order: no fused multiply-add, so each value is the one
// Python's doubles give.
#pragma clang fp contract(off)

namespace pure::gpu {
namespace {

// The four taps of one output texel along an axis: the input indices (clamped to the edges) and their weights.
struct Taps {
    std::array<std::uint32_t, 4> index;
    std::array<double, 4> weight;
};

// Catmull-Rom's weights for the taps at -1, 0, 1, 2 from the fraction t, as the prototype's cr(t) writes them.
std::array<double, 4> catmull_rom(double t) {
    const double t2 = t * t, t3 = t * t * t;
    return {-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2};
}

// The taps of each of the n_in x kSpriteScale output texels: the sample centre (o + 0.5) / 4 - 0.5 in input texels.
std::vector<Taps> taps_for(std::uint32_t n_in) {
    std::vector<Taps> taps(static_cast<std::size_t>(n_in) * kSpriteScale);
    for (std::size_t o = 0; o < taps.size(); ++o) {
        const double x = (static_cast<double>(o) + 0.5) / kSpriteScale - 0.5;
        const double i = std::floor(x);
        taps[o].weight = catmull_rom(x - i);
        for (int d = 0; d < 4; ++d) {
            const double at = std::clamp(i + d - 1.0, 0.0, static_cast<double>(n_in - 1u));
            taps[o].index[d] = static_cast<std::uint32_t>(at);
        }
    }
    return taps;
}

} // namespace

void upscale_sprite(const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height,
                    std::vector<std::uint8_t> &out) {
    const std::uint32_t out_width = width * kSpriteScale, out_height = height * kSpriteScale;
    out.assign(static_cast<std::size_t>(out_width) * out_height * 4u, 0u);
    if (width == 0u || height == 0u) return;
    const std::size_t texels = static_cast<std::size_t>(width) * height;

    // The peak alpha, and whether the texture is mask-like: at least 60% of its texels empty or at the peak.
    std::uint32_t peak = 0u;
    for (std::size_t p = 0; p < texels; ++p) peak = std::max<std::uint32_t>(peak, pixels[p * 4u + 3u]);
    const bool no_alpha = peak == 0u;  // drawn as if covered (sprite_upscale.hpp), alpha 0 kept
    if (no_alpha) peak = 255u;
    std::size_t covered_or_empty = 0u;
    for (std::size_t p = 0; p < texels; ++p) {
        const std::uint32_t a = pixels[p * 4u + 3u];
        if (a == 0u || a + 1u >= peak) ++covered_or_empty;
    }
    const bool mask_like = no_alpha || static_cast<double>(covered_or_empty) >= 0.6 * static_cast<double>(texels);

    // Premultiplied RGBA with the coverage a = alpha / peak.
    std::vector<double> source(texels * 4u);
    for (std::size_t p = 0; p < texels; ++p) {
        const double a = no_alpha ? 1.0 : static_cast<double>(pixels[p * 4u + 3u]) / static_cast<double>(peak);
        for (int c = 0; c < 3; ++c) source[p * 4u + c] = static_cast<double>(pixels[p * 4u + c]) * a;
        source[p * 4u + 3u] = a;
    }

    // Rows: width -> out_width, for each of the height rows.
    const std::vector<Taps> across = taps_for(width);
    std::vector<double> rows(static_cast<std::size_t>(out_width) * height * 4u);
    for (std::uint32_t y = 0; y < height; ++y) {
        const double *in = source.data() + static_cast<std::size_t>(y) * width * 4u;
        double *row = rows.data() + static_cast<std::size_t>(y) * out_width * 4u;
        for (std::uint32_t x = 0; x < out_width; ++x) {
            const Taps &tap = across[x];
            for (int c = 0; c < 4; ++c) {
                double sum = 0.0;
                for (int d = 0; d < 4; ++d) sum += in[tap.index[d] * 4u + c] * tap.weight[d];
                row[x * 4u + c] = sum;
            }
        }
    }

    // Columns: height -> out_height, each output texel finished as it is made.
    const std::vector<Taps> down = taps_for(height);
    constexpr double kHalfWidth = 0.22;
    for (std::uint32_t y = 0; y < out_height; ++y) {
        const Taps &tap = down[y];
        std::array<const double *, 4> from{};
        for (int d = 0; d < 4; ++d) from[d] = rows.data() + static_cast<std::size_t>(tap.index[d]) * out_width * 4u;
        std::uint8_t *line = out.data() + static_cast<std::size_t>(y) * out_width * 4u;
        for (std::uint32_t x = 0; x < out_width; ++x) {
            std::array<double, 4> v{};
            for (int c = 0; c < 4; ++c) {
                double sum = 0.0;
                for (int d = 0; d < 4; ++d) sum += from[d][x * 4u + c] * tap.weight[d];
                v[c] = sum;
            }
            double a = std::min(std::max(v[3], 0.0), 1.0);
            std::array<double, 3> color{};
            if (a > 0.001)
                for (int c = 0; c < 3; ++c) color[c] = std::min(std::max(v[c] / a, 0.0), 255.0);
            if (mask_like) {
                const double t = std::min(std::max((a - (0.5 - kHalfWidth)) / (2.0 * kHalfWidth), 0.0), 1.0);
                a = t * t * (3.0 - 2.0 * t);
            }
            std::uint8_t *texel = line + static_cast<std::size_t>(x) * 4u;
            for (int c = 0; c < 3; ++c) texel[c] = static_cast<std::uint8_t>(color[c] + 0.5);
            texel[3] = no_alpha ? 0u : static_cast<std::uint8_t>(a * static_cast<double>(peak) + 0.5);
        }
    }
}

bool write_png(const std::string &path, const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height) {
    int size = 0;
    unsigned char *png = stbi_write_png_to_mem(pixels, static_cast<int>(width * 4u), static_cast<int>(width),
                                               static_cast<int>(height), 4, &size);
    if (png == nullptr) return false;
    std::ofstream file(path, std::ios::binary);
    file.write(reinterpret_cast<const char *>(png), size);
    STBIW_FREE(png);
    return static_cast<bool>(file);
}

} // namespace pure::gpu

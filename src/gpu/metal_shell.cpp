// See metal_shell.hpp.
#include "metal_shell.hpp"

#if defined(PORTABLEKIT_HAS_RENDERER)
#include "gpu/vulkan_renderer.hpp"
#endif

#include <cstring>

namespace pure::gpu {

bool show_in_shell(portablekit::gpu::VulkanRenderer *shell, std::uint32_t address, const std::uint8_t *pixels,
                   std::uint32_t width, std::uint32_t height, std::vector<std::uint8_t> &scratch) {
#if defined(PORTABLEKIT_HAS_RENDERER)
    if (shell == nullptr || !shell->available() || pixels == nullptr || width == 0u || height == 0u) return false;
    const auto [target_width, target_height] = shell->target_size();
    if (target_width == 0u || target_height == 0u) return false;
    if (target_width == width && target_height == height) {
        shell->upload_frame(address, pixels, width, height, width);
        return true;
    }
    // Nearest neighbour, so that every pixel of the shell's target is one of ours.
    scratch.resize(static_cast<std::size_t>(target_width) * target_height * 4u);
    std::vector<std::uint32_t> columns(target_width);
    for (std::uint32_t x = 0; x < target_width; ++x)
        columns[x] = static_cast<std::uint32_t>(static_cast<std::uint64_t>(x) * width / target_width);
    for (std::uint32_t y = 0; y < target_height; ++y) {
        const std::uint32_t source_y = static_cast<std::uint32_t>(static_cast<std::uint64_t>(y) * height / target_height);
        const std::uint8_t *source = pixels + static_cast<std::size_t>(source_y) * width * 4u;
        std::uint8_t *destination = scratch.data() + static_cast<std::size_t>(y) * target_width * 4u;
        for (std::uint32_t x = 0; x < target_width; ++x) std::memcpy(destination + x * 4u, source + columns[x] * 4u, 4u);
    }
    shell->upload_frame(address, scratch.data(), target_width, target_height, target_width);
    return true;
#else
    (void)shell;
    (void)address;
    (void)pixels;
    (void)width;
    (void)height;
    (void)scratch;
    return false;
#endif
}

} // namespace pure::gpu

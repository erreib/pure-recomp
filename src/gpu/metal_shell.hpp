// The Metal backend's picture in the window shell, until the shell has a Metal presenter (task 026).
//
// The window and its captures belong to the Vulkan shell (VulkanRenderer): it presents its own target at
// the display address, and the input script's `shot` steps, which the frame regression suite captures
// with, read its window (VulkanRenderer::capture_window), not GeBackend::capture_frame. A backend that
// draws elsewhere leaves that window black. So the Metal backend reads each presented picture back and
// hands it to the shell as a CPU picture (VulkanRenderer::upload_frame), scaled by nearest neighbour to the
// shell's target size so that the shell's blit copies it 1:1: the window shows what Metal drew, and a
// window capture reduced to 480x272 by nearest neighbour gives Metal's pixels back exactly.
//
// Kept in a C++ file of its own so that the shell's headers never meet Objective-C.
#pragma once

#include <cstdint>
#include <vector>

namespace portablekit::gpu {
class VulkanRenderer;
}

namespace pure::gpu {

// Shows `width` x `height` RGBA pixels (red in the low byte, rows of `width`) in the shell's target at
// `address`, for its next present. False when there is no shell to show them in. `scratch` keeps the
// scaled copy between calls.
bool show_in_shell(portablekit::gpu::VulkanRenderer *shell, std::uint32_t address, const std::uint8_t *pixels,
                   std::uint32_t width, std::uint32_t height, std::vector<std::uint8_t> &scratch);

} // namespace pure::gpu

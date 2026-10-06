// The one Metal device and command queue of the program, shared by the Metal GE backend (metal_backend.mm) and the
// Metal shell (src/host/metal_shell.mm), task 031.
//
// Metal runs the command buffers of one queue in the order they are committed, and orders a tracked resource's
// writes before the reads of a later command buffer of that queue. The backend commits each frame at
// present_image(), and the shell commits the present that samples the frame's target after that, so on one queue
// the shell's sampling always comes after every draw of the frame (the race HUD included) and the next frame's
// draws after the sampling, with no wait and no MTLSharedEvent (docs/metal-backend.md, "The Metal shell"). On two
// queues nothing ordered them, and the window showed race frames without their HUD (task 028).
//
// Objective-C++ only (the two users are .mm files). Made once, on first use, with MTLCreateSystemDefaultDevice;
// both are nil when the machine has no Metal device. They live until the program exits.
#pragma once

#import <Metal/Metal.h>

#include <cstdint>

namespace pure::metal {

id<MTLDevice> device();
id<MTLCommandQueue> queue();

// The frame trace (PURE_METAL_TRACE, task 033; docs/metal-backend.md, "Frame times"). The backend writes a row per
// flip; the Metal shell, which presents the backend's picture right after present_image(), hands it its own part
// of each flip through these calls (the hook the brief offered, rather than a second file). The shell calls them
// only when trace_on(), which reads PURE_METAL_TRACE once.
bool trace_on();
// The backend, in present_image(): the flip whose picture the shell presents next.
void trace_flip(std::uint64_t flip);
std::uint64_t trace_current_flip();
// The shell, after its commit of a game picture: the CPU time of present() and, of it, the wait in nextDrawable.
void trace_shell_present(double cpu_ms, double drawable_ms);
// The shell's presented handler (any thread): when the drawable of `flip` reached the screen (CACurrentMediaTime's
// seconds; 0 when it never did) and how long after the start of present() that was.
void trace_presented(std::uint64_t flip, double presented_s, double latency_ms);

// The backend's side: the shell's present times since the last call, summed, and their count.
struct ShellPresents {
    double cpu_ms{};
    double drawable_ms{};
    std::uint32_t count{};
};
ShellPresents take_shell_presents();
// The presented time and latency of `flip`'s drawable, once the shell's handler has reported it (then forgotten).
bool take_presented(std::uint64_t flip, double &presented_s, double &latency_ms);

} // namespace pure::metal

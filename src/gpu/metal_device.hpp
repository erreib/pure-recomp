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

namespace pure::metal {

id<MTLDevice> device();
id<MTLCommandQueue> queue();

} // namespace pure::metal

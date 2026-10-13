// E2 (D-020, task 084): the game's 3D view at the shape of the picture it is drawn into. Under the Vulkan renderer's
// Fill aspect the game's 480x272 screen is spread over a target of the window's shape, and the renderer tells the
// profile that shape once a frame (GameProfile::view_aspect_frame). Wipeout Pure's projection takes its aspect as a
// constant compiled into its callers, so the hook overrides the projection builder FUN_08a31148 and also keeps the
// camera's horizontal half-angle tangent (0x08b1fb14) at the shape's width. At the PSP's 480:272 it does nothing.
// PURE_TRACE_ASPECT=1 prints the override's call counts once a second (README.md).
#pragma once

#include "profile.hpp"

namespace portablekit::aspect {

// GameProfile::view_aspect_frame: at each flip, with the width over height of the picture the next frame is drawn
// into (480/272 unless the renderer is under Fill in a window of another shape). The first call with another shape
// puts the override in (PURE_TRACE_ASPECT: the first call of all); until then nothing is registered or written.
void view_aspect_frame(psprecomp::Runtime &rt, float aspect);

} // namespace portablekit::aspect

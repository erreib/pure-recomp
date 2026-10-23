// The shield effect at the display's rate (task 107, GitHub issue 2; docs/timing.md "The shield effect (task 107)").
// The Shield's update FUN_08946918(dt, this) eases the shell's colour and scale in whole 60 Hz frames of the frame's
// dt, `n = (int)(dt / 0.016666668)`, which is 0 on every frame of a race at E8's Display rate (119.40 Hz on a 120 Hz
// display): the shell never builds up after a pickup, a contact's flash colour never fades, and the dying effect never
// reaches its delete test, so it shows for the rest of the race. While the race's vblank runs faster than the PSP's,
// the update is overridden so that it steps by the time (the fraction of a 60 Hz frame carried per effect from one
// call to the next) and the effect's clock keeps the real dt; at the PSP's rate nothing is registered.
// PURE_SHIELD_STEP=0 keeps the generated code at the display's rate; PURE_TRACE_SHIELD=1 prints every live effect once
// a flip, at any rate, from guest memory alone (README.md and docs/developing.md).
#pragma once

#include "profile.hpp"

#include <cstdint>

namespace portablekit::shield_step {

// From E8's hook in the end-of-frame routine's GE sync (enhancements.cpp), after it has set the vblank period: the
// first frame whose period is under the PSP's puts the override in, once (PURE_SHIELD_STEP=0: a line saying it is
// off instead). Until then nothing is registered.
void frame(psprecomp::Runtime &rt);

// PURE_TRACE_SHIELD=1: from the profile's flip counter once a flip with the flip's number; prints every live Shield
// effect of every ship (`[pure] shield frame N ship K ...`) and a line when one starts and ends. Reads guest memory
// only, so a traced run's dispatches are an untraced one's.
void flip(psprecomp::Runtime &rt, std::uint64_t frame);

} // namespace portablekit::shield_step

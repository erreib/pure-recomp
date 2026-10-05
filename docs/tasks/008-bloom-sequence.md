# 008: The bloom chain, exactly: what the game draws, reads and aliases per frame (spike S10)

Milestone: M3/M6 | Branch: task/008-bloom-sequence | Status: OPEN (after task 006)

## Goal
With the framework's framebuffer-texture path on, the race scene is tinted magenta; with `PURE_NO_FB_TEXTURES=1`
it is correct but has no bloom. Before anyone changes a renderer, write down the exact per-frame GE sequence of
Wipeout Pure's post-processing on a race frame: every change of framebuffer or depth address, every texture bind
whose address lies in VRAM targets, formats and strides, and what each pass draws. Then say what the framework's
Vulkan renderer does with each of those binds and where it goes wrong.

## Read first
- CLAUDE.md, docs/research.md (section "GE usage": the 0x04110000 depth area reused as a 256-wide RGBA8888 target,
  the lens-flare depth readback), docs/status.md Blockers (bloom row), docs/ppsspp.md
- ref/vineta_k_start.ppdmp (task 006) and PPSSPP's GE dump format (PPSSPP source GPU/Debugger/Record.cpp, read-only)
- vendor/portablekit/host/gpu/ge_state.cpp (DrawCall, BlockTransfer), host/gpu/vulkan_renderer.cpp (search for
  "large or copied texture", "fb_textures", the render-target cache keyed by address) and `PURE_TRACE_GE_LIST`,
  `PURE_TRACE_FB_TEXTURES`, `PURE_TRACE_RENDER` in the framework docs

## Deliverable
1. `docs/ge-effects.md`: the sequence for one race frame, as a numbered list: (framebuffer addr, format, stride,
   depth addr) → draws → (texture binds: addr, format, size, bufw, swizzle, which earlier target they alias) →
   blend mode → where the result lands → how it reaches the final frame. Get it from the PPSSPP dump (the ground
   truth) and confirm with our `PURE_TRACE_GE_LIST`/`PURE_TRACE_FB_TEXTURES` output on the same scene
   (`out/race-nofb.log` has a start; run the race route with the traces on and `PURE_NO_FB_TEXTURES` unset).
2. The same for the lens flare: where the CPU reads the depth buffer (research says a 4x4 around the sun) and
   whether our port does that read (grep the GE/IO traces, or a watch on reads of 0x04110000 if the framework has
   one; otherwise say it is untested).
3. A diagnosis section: for each bind the framework classifies as "large or copied texture", what it samples
   (which Vulkan image: the colour target, the depth target, a CPU copy) and why the result is magenta. A one-line
   fix proposal if there is an obvious one (e.g. the bind resolves to the depth image instead of the colour image
   the game wrote there after the scene), as a description, not a patch.

## Acceptance criteria
- [ ] docs/ge-effects.md has the per-frame sequence with concrete addresses and formats from the PPSSPP dump.
- [ ] The diagnosis names the file:line in the renderer where each bloom bind is resolved.

## Verify
`test -s docs/ge-effects.md && grep -q 0x04110000 docs/ge-effects.md && grep -qi 'magenta' docs/ge-effects.md`

## May touch
- docs/ge-effects.md, tools/ppsspp/ (a small .ppdmp parser is welcome under tools/ppsspp/ppdmp.py), out/

## Must not touch
- vendor/, patches/, src/, config/

## Estimated turns
40

## Escalate when
The .ppdmp format cannot be parsed with a reasonable effort (then use PPSSPP's GE debugger window by hand and
describe what you saw, with screenshots in out/).

## Result
(worker fills)

## Review
(Fable fills)

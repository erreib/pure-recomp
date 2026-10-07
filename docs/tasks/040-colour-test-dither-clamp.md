# 040: The colour test, dithering and depth clamping (fidelity differences 10 and 11)

Milestone: M8 | Branch: task/040-colour-test-dither-clamp | Status: OPEN (after tasks 036 and 037: the same files)

## Goal
Three small GE states the framework ignores: the colour test (COLORTEST NOT EQUAL black drops the pure black pixels of
the billboard screens' content and a few small objects, 3 to 14 draws a frame, which the port draws), dithering on
16-bit targets (DITHERENABLE on 6 to 95 draws a frame; the PSP dithers 5650/5551/4444 targets with its 4x4 matrix),
and depth clamping at the depth range's ends (CLIPENABLE on every 3D draw). This task carries the three in the GE
state (a vendor patch) and applies them in the Metal backend.

## Read first
- CLAUDE.md, docs/fidelity.md (differences 10 and 11, their draw counts), docs/metal-backend.md (the fragment path,
  the alpha test by GE numbering, the depth range remap), docs/tasks/036 and 037 (Results: the shape of a state
  patch and the record format's growth)
- vendor/portablekit/host/gpu/ge_state.hpp and .cpp (the ignored commands: COLORTEST 0xE1, its function COLORTESTENABLE
  0x23, COLORREF 0xE2, COLORMASK 0xE3; DITHERENABLE 0x25 and the DITHER matrix 0xD0 to 0xD3; CLIPENABLE 0x1D),
  host/gpu/shaders/ge.frag
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: the colour test's functions, reference and mask; the
  dither matrix's 4x4 of signed 4-bit offsets applied before the 16-bit quantisation; depth clamp)
- src/gpu/metal_backend.mm (the pipeline key, `FragmentUniforms`), src/gpu/metal_shaders.h

## Deliverable
1. Patch 0017 (`tools/patches.sh export 0017-colour-test-dither-clip`): `DrawCall` gains the colour test (enabled,
   function, reference, mask), dithering (enabled, the 4x4 matrix) and the clip-enable bit; `ge_state.cpp` sets them;
   the record format and `gerec_dump.py` carry them. The Vulkan backend unchanged (comment).
2. The Metal backend: the colour test in the fragment shader (discard by the GE's function on the masked RGB,
   as the alpha test is done), a pipeline-key bit for "has colour test"; dithering applied in the fragment shader
   for draws into 5650/5551/4444 targets (the matrix entry by the pixel's x and y modulo 4, added before the target's
   quantisation, which the backend does when it writes a 16-bit target in its own format: say where the quantisation
   happens today and apply the offset there); depth clamping: with CLIPENABLE off the PSP clamps z into the depth
   range instead of clipping (check the documentation's statement and apply what it says: Metal's
   `depthClipMode = clamp` when the GE does not clip).
3. The check: the billboard screens on a race frame (a region of `race_hud` or the Zone scenes where a screen shows
   content) against PPSSPP before and after, a 16-bit target's dither pattern (the 565 offscreen target at 0x04154000
   from docs/ge-effects.md, captured through a recording and `ge_replay --cut`, against the PPSSPP dump's pixels of
   it), and the suite.
4. Also in patch 0017: `RecordBackend::submit` records the texels of every mip level a draw names (task 037's
   levels; today only level 0's bytes are recorded, so a recording made since patch 0014 replays mipmapped draws
   from zeroed memory, 0.09 off its own picture). Check: a Blue Ridge or race frame recorded through Metal replays
   exactly into Metal without `PURE_NO_MIPMAPS`.
5. docs/metal-backend.md, docs/fidelity.md (differences 10 and 11's rows), patches/README.md.

## Acceptance criteria
- [ ] `tools/frame_regress.sh` passes with no scene more than 0.003 above its measured value; the race scenes at or
      below theirs; the billboard region reported before and after.
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` unchanged; `tools/patches.sh check` passes;
      `tools/hud_check.sh --shell headless` 61 of 61.

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh`

## May touch
- vendor/portablekit/host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp, record_backend.cpp, vulkan_renderer.cpp (comment), via
  `tools/patches.sh export 0017-colour-test-dither-clip`; patches/; src/gpu/; tools/gerec/gerec_dump.py;
  docs/metal-backend.md, docs/fidelity.md (differences 10, 11), README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/hle/, host/shell/, src/host/, src/profile/, src/tools/, tools/frame_regress.sh,
  config/, ref/, earlier patches

## Estimated turns
50

## Escalate when
Dithering cannot be applied where the 16-bit quantisation happens without changing what 8888 targets draw (report
where it is and why), or the depth-clamp rule differs between the documentation and what the reference shows (report
both pictures).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

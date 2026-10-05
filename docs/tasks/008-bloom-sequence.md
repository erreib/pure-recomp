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
Status: DONE

Changed: `docs/ge-effects.md` (new), `tools/ppsspp/ppdmp.py` (new: .ppdmp parser, stdlib plus the `zstd` CLI; also
replays our port's `PURE_TRACE_GE_LIST` output). Traces, screenshots and texture PNGs are in `out/008/` (ignored).
No renderer, vendor, src or config change. The .ppdmp format parsed without trouble, so the escalation fallback was
not used.

The sequence, in brief (PPSSPP frame 7155; our frame 6485 has the same structure and registers):
- Draw 0 clears 0x04088000 (8888, stride 512) with depth 0x04110000 (stride 512) and stencil/alpha 4. Four billboard
  render-to-texture rounds go into 0x04154000 (565, stride 128) and are sampled back as 565 128x128 bufw 128 (draws
  26, 45, 69, 82). The opaque world and the sky cube (to 602) write the bloom mask into alpha with stencil REPLACE:
  ref 4 for most materials, 0xFF for lights.
- A GE SIGNAL 0x0200 follows the sky. Its handler reads the depth buffer with the CPU for the lens flare. The
  translucent world comes next, then the flare (draw 832: 10 additive quads, depth test off, alphas 0x3F-0x79).
- The bloom is 833-838. 833: 0x04088000 downsampled 2:1 into 0x04110000 (8888, stride 256: the depth buffer's
  bytes) with blend add(SA, 0), so the scene is weighted by the stencil mask. 834/835: 0x04132000 (= 0x04110000 +
  256x136x4) is blacked, then gets an 11-tap horizontal blur of 0x04110000 (ONE+ONE). 836/837: 0x04110000 is
  blacked, then gets the vertical blur of 0x04132000. 838: 0x04110000 is upscaled 1:2 and added onto 0x04088000 at
  0xAF/0xFF, with alpha writes masked. Then the HUD and DISPLAY 0x04088000.
- Our port does the same thing. `PURE_TRACE_FB_TEXTURES` at frame 5707 and the `PURE_TRACE_GE_LIST` replay of frame
  6485 show the same addresses, strides, formats, vertex bounds, blends and masks.
- Lens flare: our port does the read. `PSPRECOMP_TRACE_VRAM_READS` shows 16 + 1 loads per frame in
  0x04120000-0x0413FFFF, each right after the stall update that runs the SIGNAL. But the read hits guest memory that
  holds no depth. The renderer keeps depth in per-target Vulkan images and never writes it back, so the read most
  likely returns zero ("sky"). The actual values were not measured.
- Diagnosis: `find_framebuffer_texture` (vendor/portablekit/host/gpu/vulkan_renderer.cpp:4199-4235) resolves three
  of the four bloom binds correctly. The v-blur source 0x04132000 lies inside two targets with stride 256. The lookup
  picks the one with the highest `draw_serial` (:4215), which is 0x04110000, because draw 836 bumped its serial
  (:6146). So the v-blur samples rows 136-271 of the 0x04110000 image, at offset (0,136). No draw ever writes those
  rows. The target starts undefined (:3412, :3475), and on this machine those rows read back with R and B high and
  G = 0. FB-on minus FB-off at r6400: +72.8 R, +0.4 G, +77.0 B, uniform. Blurred and added at 0.686, that gives the
  magenta wash.
- Fix proposal: in `find_framebuffer_texture`, prefer a target that starts exactly at the texture's address (or one
  whose drawn rows cover the texture) over the most recently drawn target that only contains it.

Verify output (the Verify line prints nothing; its exit status):
```
$ test -s docs/ge-effects.md && grep -q 0x04110000 docs/ge-effects.md && grep -qi 'magenta' docs/ge-effects.md; echo "exit $?"
exit 0
```

Open questions:
- Even with the bind fixed, the bloom will not match until stencil-as-alpha is emulated. The GE state ignores
  0x24/0xDC/0xDD (and the write masks 0xE8/0xE9), so the mask would come from texture alpha and the whole scene
  would bloom. That is a renderer task (R3/M6), as is storing depth into guest 0x04110000 when the flare SIGNAL is
  raised.
- What MoltenVK leaves in never-written target rows (here R/B high, G 0) is unexplained. Should new targets be
  cleared on creation, so that any other undrawn-row read is deterministic?
- The flare's read values, and our flare's vertex alphas, are untested. Confirming them needs a value-level VRAM
  read trace (address and value), which the framework does not have.
- GE list run indices are not reproducible between runs: the same index landed 34 frames later in run B. A
  frame-anchored `PURE_TRACE_GE_LIST` would make list dumps practical.
- Some texture and heap addresses differ slightly between PPSSPP and our port: the flare atlas is 0x0968A2B0 vs
  0x0968A4B0, and a VRAM trail texture is 0x041D0700 vs 0x041CEDC0. Compare dumps by role, not by address.

## Review
(Fable fills)

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
Status: DONE

What was done:
- **Patch 0017** (`0017-colour-test-dither-clip`): `DrawCall` carries the colour test, dithering and CLIPENABLE.
  - `color_test` (`ColorTestState`: enabled, function, reference, mask) comes from COLORTESTENABLE 0x27, COLORTEST
    0xD8, COLORREF 0xD9 and COLORTESTMASK 0xDA.
  - `dither` (`DitherState`: enabled, the four rows, `offset(x, y)`) comes from DITHERENABLE 0x20 and DITH0 to DITH3
    0xE2 to 0xE5.
  - `clip_enabled` comes from CLIPENABLE 0x1C.
  - The ten commands left the ignored list: 30 distinct remain, from 40.
  - The record format appends the three (`kPixelBytes`, 31 bytes). A Draw that ends before them reads as no colour
    test, no dithering and CLIPENABLE off, and `kVersion` stays 1. `gerec_dump.py` lists `ctest`, `dither` and
    `noclip`.
  - `RecordBackend::submit` now records the texels of every mip level a draw samples (deliverable 4).
  - The Vulkan renderer is unchanged; a comment says it draws none of the three.
- **Metal, the colour test**: in `shade()` after fog, where the alpha test is, on the 8-bit colour under the mask,
  with `discard_fragment`. It is compiled in by the function constant `kColorTest` (a `RenderKey` bit), and ALWAYS
  is compiled out.
- **Metal, dithering and the 16-bit quantisation.**
  - Where the quantisation happened before: only in `store_pixels`, when a target is stored in guest memory (block
    transfers, read-backs, the frame write-back). Every target is an RGBA8 texture. The 565 billboard target is
    sampled on the GPU straight from that texture, so it kept 8 bits a channel, and an offset applied at the store
    would change nothing on screen.
  - The PSP blends, then dithers, then keeps the format's bits, and 43 of Vineta K's 60 draws into that target
    blend. So the offset cannot go on the fragment before Metal's blend either.
  - What the backend does now: draws into 5650, 5551 and 4444 targets go through `ge_fragment_16`. It reads the
    target's colour (`[[color(0)]]`, programmable blending) and blends with the GE's factors and equation itself,
    so the pipeline does not blend. Then it adds the matrix's offset (row y & 3, column x & 3), clamps once, and keeps
    the top 5/6/5, 5/5/5 or 4/4/4 bits as the 8-bit values they expand to.
  - 8888 targets are drawn as before, so the escalation condition did not occur.
  - Clears into 16-bit targets keep the bits but are not dithered.
- **Metal, the depth clamp.**
  - The hardware notes ("Z Clipper", "Clipping enabled", "MinZ and MaxZ", "Z Clamp") put the clamp with CLIPENABLE
    **on**, not off as the brief said: clip at the near plane only, clamp each vertex's screen z to 0..65535, and leave
    the far side to the per-pixel MINZ/MAXZ test. The game sets CLIPENABLE on every transformed draw.
  - With it on, `ge_vertex` computes the GE's screen z, clamps it per vertex and outputs z / 65535 in a 0..1
    viewport. The near plane, MINZ and MAXZ are clip distances, and the encoder's depth clip mode is
    `MTLDepthClipModeClamp`.
  - CLIPENABLE off is drawn as before and named once. The game never draws a transformed draw with it off; old
    recordings read as off and replay as they did.
- **Switches**: `PURE_NO_COLOR_TEST`, `PURE_NO_DITHER` and `PURE_NO_DEPTH_CLAMP` give back the old drawing; with all
  three the 18 captures are pixel-identical to the build before the task. `PURE_METAL_SHOW_TARGET=ADDR` presents an
  offscreen target, which the dither check uses.
- **Where this departs from the brief.**
  - The brief's command numbers (0xE1, 0x23, 0xE2, 0xE3; 0x25, 0xD0 to 0xD3; 0x1D) are other registers. I used the
    framework's ignored list and the PSP SDK's numbers.
  - The depth clamp applies with CLIPENABLE on, as above.
  - Dithering needed the 16-bit quantisation in the draw path. Before the task there was none.

The scene fractions, headless Metal at tol 32 against PPSSPP. "Before" is the same build with the three switches;
its 18 captures are pixel-identical to the pre-task build.

| Scene | Before | After | Pixels changed (tol 0) |
|---|---|---|---|
| race_hud | 0.014874 (1942) | 0.014828 (1936) | 723: 640 from the colour test (a lamp's glow), 83 from the billboard |
| tt_hud | 0.011221 (1465) | 0.011213 (1464) | 377 (the billboards) |
| fp_hud | 0.011566 (1510) | 0.011336 (1480) | 413 (the billboards) |
| the other 15 scenes | | unchanged | 0 |
| Blue Ridge, flip 6016 (not a suite scene) | 0.024732 | 0.024732 | 27, none by more than 8 |

The depth clamp alone changes 0 pixels in the 18 scenes. That matches the 18 PPSSPP dumps: no vertex in front of the
near plane lies beyond the far plane (z/w at most 0.9999), and MINZ/MAXZ are the viewport's own range. So the
reference cannot show the rule either way, and that escalation did not occur either.

The regions, against PPSSPP:

| Region | tol 32 before | tol 32 after | tol 16 before | tol 16 after |
|---|---|---|---|---|
| race_hud billboard screen (201,126) 16x8 (draw #42's footprint) | 0.8828 | 0.8828 | 0.9063 | 0.9063 |
| tt_hud billboard screen (195,114) 29x29 | 0.4245 | 0.4221 | 0.4828 | 0.4828 |
| fp_hud billboard screen (195,114) 29x29 | 0.4269 | 0.3912 | 0.4816 | 0.4828 |
| race_hud lamp glow, colour test (307,107) 26x34 | 0.0328 | 0.0260 | 0.2285 | 0.1765 |

The billboard screens show other adverts than PPSSPP's frames (another point in the adverts' cycle), which is
almost all of their difference.

The 565 target's dither pattern. Race frame 6016 recorded through Metal and replayed with `--cut` 42, 72, 84 and 98
(the end of each billboard round) under `PURE_METAL_SHOW_TARGET=0x04154000`. PPSSPP's target comes from its dump
(the FRAMEBUF records at draws 26, 45, 69 and 82).
- Share of pixels that are 565 values: PPSSPP 1.0 in every round; the port before 0.556, 0.072, 0.000 and 0.996; the
  port after 1.0 in every round.
- Flat 4x4 blocks ordered as the round's matrix:
  - PPSSPP: 0.994, 1.0, 0.117 (its third round is a gradient, which the measure does not allow for) and 1.0.
  - The port after: 1.0 in all four rounds (710 to 1009 blocks).
  - The port before: no block shows any dither.
- The PSP's rule applied to the before pixels equals the after pixels on 100%, 100%, 100% and 99.98% of them.
- The rule itself comes from PPSSPP's fourth round. That round is a flat colour, and value 229 plus the offset with
  DITHn as row y & 3, cut to 5/6/5 bits, reproduces all 16384 of its pixels. With the matrix transposed, at best 6144.

The replay check of a mipmapped recording (deliverable 4). Both frames were recorded through Metal with this build
and replayed into Metal without `PURE_NO_MIPMAPS`:

| Recording | Replay against its own picture, tol 0 |
|---|---|
| race frame 6016, recorded with patch 0014's record backend | 0.0119 |
| race frame 6016, recorded now (611 Memory records against 283) | 0 pixels |
| Blue Ridge frame 6016, recorded now (974 draws; task 037 found 0.0913 at tol 32 without the levels) | 0 pixels |

Acceptance:
- Suite 18/18. No scene is above its measured value; the race scenes are at or below theirs (race_hud -0.0001,
  fp_hud -0.0003, tt_hud +0.0000). The billboard regions are reported above.
- `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18, every scene within 0.0005 of its vulkan column
  (19m 47s).
- `tools/patches.sh check`: 16 patches (0001 to 0015 and 0017).
- `tools/hud_check.sh --shell headless`: 61 of 61.

Changed:
- patches/0017-colour-test-dither-clip.patch: vendor host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp,
  record_backend.cpp, and a comment in vulkan_renderer.cpp.
- patches/README.md, src/gpu/metal_backend.mm, src/gpu/metal_shaders.h, tools/gerec/gerec_dump.py.
- docs/metal-backend.md: the new section "The colour test, 16-bit writes and the depth clamp", "Verify numbers /
  Task 040", the switches, the draw table, the pipeline key, the uniforms, the targets, the Vulkan differences and
  the mipmap recordings note.
- docs/fidelity.md: the rows of differences 10 and 11.
- README.md: the four switches and the `PURE_METAL_LOG` tags.

Verify output (last 20 lines; `tools/verify_task.sh 040` at 3d120f1, 2026-10-07):
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0113   0.11   32    0.0116 -0.0003  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0121   0.09   32    0.0121 +0.0000  PASS
zone_change   5679    0.0353   0.10   32    0.0353 +0.0000  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 24s)
verify 040: PASS
```

Open questions:
1. **Rules the documentation leaves open.** The game's frames do not settle these, and I chose as follows:
   - Fog comes before the colour test. That is the alpha test's place, and it matters for fogged glows.
   - A clear into a 16-bit target is not dithered. The game's are black and every round covers them.
   - The dither offset goes on before the single clamp. That matters only for blends that overflow.
   - 8888 targets are never dithered, as the brief says. No draw in the 18 dumps dithers an 8888 target.
2. **The pre-warm list lacks the new keys.** A race run makes 6 render pipelines on first use (four `sixteen=1`, two
   `color_test=1`), 1.2 ms in all at the first race frame on this machine. `config/` is Must not touch, so adding them
   to `config/metal_pipelines.txt` is a follow-up; `PURE_METAL_PIPELINES_OUT` writes them. The parser reads the old
   list's lines, which lack the two new fields, as 0.
3. **`tools/gerec/metal_check.sh` (outside May touch) needs `PURE_NO_MIPMAPS=1` beside `PURE_NO_TEXMAP=1` once it
   re-records.**
   - Recordings now carry the mip levels' texels, so Metal draws the levels the Vulkan backend does not. Race frame
     6016 with `PURE_NO_TEXMAP=1` alone is 0.0219 at tol 24, over its 0.02.
   - With both switches it is 3 pixels. Adding `PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1` leaves it at 3.
   - With `PURE_NO_DEPTH_CLAMP=1` too it is 2. The extra pixel, (146,124), is a depth tie that the clamp's arithmetic
     rounds the other way, and it shows only in that switch combination.
   - Its existing recordings replay as before.
4. **Not exercised by the game:**
   - 5551 and 4444 targets. The shader path covers them; only the 565 target is drawn.
   - The doubled blend factors and ABSDIFF in `ge_fragment_16`, which the shader draws exactly.
   - CLIPENABLE off, which is named and not emulated.
5. **The billboard region cannot show the gain.** The adverts differ from PPSSPP's at the suite's frames. A reference
   captured at the same point of the adverts' cycle would compare the dithered screen directly.
6. **Patch numbering.** 0017 applies after 0015; check that it still applies once 0016 lands. docs/ge-backend.md
   section 6 (the Draw record) is outside May touch and now three parts behind; the header in
   `ge_record_format.hpp` is current.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

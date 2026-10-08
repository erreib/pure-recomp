# 057: Vulkan: the texture mapping modes

Milestone: W3 (docs/windows.md step 3) | Branch: task/057-vulkan-texture-mapping | Status: OPEN

## Goal
The framework's Vulkan renderer draws every transformed draw with texture map mode 0 (UVs through the GE's scale
and offset). The Metal backend since task 036 also draws mode 1 (the texture matrix applied to position, UV or
normal, s and t divided by q per pixel) and mode 2 (the environment map from the normal and two lights) — the
reflections on the ships and the canopy. Port that into the Vulkan renderer as a vendor patch: the GE state
already carries the fields; the renderer reads none of them.

## Read first
- docs/metal-backend.md, "Texture mapping modes" (the modes, the maths, draw #359 the canopy, "Checking a draw")
- docs/tasks/036-environment-mapping.md (how the Metal side was built and measured, and its open follow-ups)
- src/gpu/shaders/ge.metal, `map_texture` (the reference implementation — read it, port its logic; the MSL file
  itself stays untouched)
- vendor/portablekit/host/gpu/shaders/ge.vert, ge.frag, vulkan_renderer.cpp (where mode 0 lives today)
- tools/gerec/gerec_dump.py and docs/metal-backend.md "Checking a draw" (cutting a frame at one draw)
- patches/README.md

## Deliverable
A vendor patch (export as 0011-vulkan-texture-mapping) that draws modes 1 and 2 in the Vulkan renderer: the
matrix and per-pixel q divide, the environment map's two light directions, the same rule Metal and the notes use.
The per-draw state must reach the shader the way the renderer already passes its uniforms; mode 0 draws must be
byte-for-byte what they were (the specialisation or branch must not disturb them).

## Acceptance criteria
- [ ] the canopy draw (race frame 6016, draw #359 by the "Checking a draw" method on this machine's race_warm
      recording): the environment-mapped pixels drawn, where before the task they took mode 0's UVs
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18, race_hud, tt_hud and fp_hud moved toward
      the Metal column (race_hud's Metal is 0.0149); no non-race scene moved more than 0.003
- [ ] `tools/gerec/replay_check.sh` still passes (replays are deterministic with the new modes)
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/ (measured columns, status), out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/ (the Metal backend is the reference, not a work site), config/,
  tools/

## Estimated turns
40

## Escalate when
The GE state turns out not to carry a field the modes need (docs/vendor-map.md rule: report the difference);
a change to include/psprecomp/ or the GE state recorder would be needed; a vendor host rebuild exceeds 5 minutes.

## Result
Status: DONE

Changed:
- patches/0011-vulkan-texture-mapping.patch (new; vendor host/gpu/vulkan_renderer.cpp, shaders/ge.vert, shaders/ge.frag)
  and its row and section in patches/README.md.
  - `ObjectBlock` (set 1, binding 1) grows from 144 to 256 bytes. The new fields are the map mode, the projection
    source, the two shade lights, the texture matrix, the viewer's direction (w: reversed normals) and `uv_remap`.
    The block is written for lit or mapped draws.
  - The per-draw state uses the uniforms the renderer already has. The push constants are full at 128 bytes, so
    the flags go in `texture_params.x`: bit 3 means mapped and bit 4 means divide by q.
  - `ge.vert` gets `map_texture`, ported from ge.metal's (mode 1: matrix times position, UV, normalized normal or
    normal; mode 2: (N.L'+1)/2 for the two shade lights, viewer added for a diffuse-and-specular light). q goes in a
    new varying at location 5. `ge.frag` divides s and t by q before its clamps.
  - The environment block is now also written for environment-mapped draws.
  - `framebuffer_source` is computed before the uniform blocks (the lookup is pure), so `uv_remap` can place mapped
    coordinates in a sampled target.
  - Mode 3 and transformed sprites keep their UVs, as on Metal.
  - Frame interpolation records a mapped draw's object block, so the blended world matrix moves the reflection.
  - `PURE_NO_TEXMAP=1` (the name the Metal backend already reads) restores the old path.
  - The host rebuild took 10 s. No include/psprecomp/ change. `tools/patches.sh check`: 11 patches reproduce the pin.
- docs/metal-backend.md: three statements that the Vulkan backend draws only mode 0 (the "Texture mapping modes"
  intro, "Metal against Vulkan", and the "differs on purpose" bullet). This patch makes them false, so they are
  corrected, not annotated. The edit was checked against the code this task changed.
- docs/status.md: a resolved row with the measured numbers. docs/fidelity.md: difference 1 names the Vulkan renderer.

Evidence:
- Recordings were made with this build on this machine (race 202 s, race_warm 199 s, frontend 25 s, title 60 s).
  `tools/gerec/replay_check.sh`: PASS (500 s). Step 2, race_warm frames 6014-6016: 0 px at tol 4.
- The canopy. On this machine's race_warm recording, frame 6016 has 886 draws, so the numbering differs from the
  Metal recording's 906. Metal's #359 is #350 here: the third of the player's three envmap draws (clut8 64x64,
  `envmap 0,1`), followed by the three lit livery draws #351-#353. The pixels it draws (cut 351 against cut 350)
  span PSP (225,176)-(254,232): 715 px at 960x544, about 179 PSP px (Metal's note: 178 px, (225,177)-(254,232)).
  - Cut after it, modes on against `PURE_NO_TEXMAP=1`: in the canopy box, 5246 of 6720 px differ, 4296 by more
    than 32, mean 66.4. Of the draw's own 715 px, 310 differ and 228 by more than 32.
  - Looking at the crop (out/canopy/compare.png): without the modes the hull is near-black with streaks. With them
    it has the grey reflection shading and the highlight on the canopy, as task 036 describes Metal.
- Mode 0 is byte for byte unchanged. A baseline binary (vendor with 0011 reversed) and this build with
  `PURE_NO_TEXMAP=1` replay all 9 frames of race_warm to identical BMPs (cmp). The frontend and title recordings
  (no mapped draws) replay identically with the modes on.
- Frame 6016 has 96 environment-mapped draws and 40 texture-matrix draws.
- The suite: the race scenes moved toward the reference, a lot: race_hud 0.0590 (column 0.067, task 056's run 0.0681),
  tt_hud 0.0707, fp_hud 0.0721, zone_hud 0.0478, zone_change 0.0518. The 13 non-race scenes give the same fractions
  as task 056's run, to the 4th decimal.

Verify output (last 20 lines), `tools/frame_regress.sh --shell vulkan --backend vulkan`:
```
scene       frame  fraction  limit  tol  measured   delta  result
lang          690    0.0544   0.07   24     0.054 +0.0004  PASS
title        1750    0.0302   0.05   24     0.030 +0.0002  PASS
profile      2100    0.0543   0.07   24     0.054 +0.0003  PASS
main_menu    4700    0.0330   0.05   24     0.033 +0.0000  PASS
race_hud     6016    0.0590   0.10   32     0.067 -0.0080  PASS
single_player   4765    0.0251   0.05   24     0.025 +0.0001  PASS
class_select   4990    0.0452   0.07   24     0.045 +0.0002  PASS
league_select   5185    0.0614   0.08   24     0.062 -0.0006  PASS
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0707   0.12   32     0.096 -0.0253  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0721   0.11   32     0.095 -0.0229  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0478   0.09   32     0.065 -0.0172  PASS
zone_change   5679    0.0518   0.10   32     0.082 -0.0302  PASS

moved more than 0.03 from the vulkan measured value: zone_change (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (20m 12s)
```
`python tools/docs_check.py`: PASS (33 files, 0 findings).

Open questions:
1. zone_change moved by 0.030, downward, and the suite flags it as "moved more than 0.03". It is a race scene and the
   move is toward the reference. The measured column lives in tools/frame_regress.sh, which this brief forbids, so
   it is not re-baselined. Per task 056's review, the column is re-measured at step 3's exit.
2. Mode 1 is not checked by any picture. In frame 6016 the 40 texture-matrix draws are clipped or culled, as on Metal
   (status.md's task 036 follow-up). The port is line for line, but it is unverified on screen.
3. "Moved toward the Metal column": there is no Metal run on this machine. race_hud went from 0.068 to 0.059 against
   Metal's 0.0149. The remaining gap is the other Metal-only features (mip levels, the filter bits, the colour test,
   and so on).
4. tt_hud and fp_hud came out at 0.071/0.072 this run. Whether their old bimodality (0.092/0.107) survives as a pair
   of lower modes was not measured: this was one full run.

## Review
Verify rerun: from the main checkout after the merge (11 patches reproduce the pin), 2026-10-08: PASS, 18/18 in
20m 14s; race_hud 0.059x, fp_hud 0.0576 this run — the moved-more-than-0.03 flags are all downward, toward the
reference.
Spot-read: patch 0011 (342 lines) follows the Metal reference closely; the off switch goes through
portablekit::env("NO_TEXMAP") so both backends read one name; mode 0 proven byte-identical with a
reversed-patch binary.
Merged: the merge commit after 8f12fb6 into batch/m2.
Notes: the docs/metal-backend.md corrections are legitimate (statements the patch falsified). Mode 1 on screen
stays an open follow-up shared with Metal (task 036: the projected plane is off screen in the suite's frames).
The column re-measure stays parked at step 3's exit, per task 056's review.

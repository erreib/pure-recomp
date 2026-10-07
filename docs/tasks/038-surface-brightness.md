# 038: Surfaces 1.5 times too bright on Sebenco Climb and Sinucit (fidelity difference 3)

Milestone: M8 | Branch: task/038-surface-brightness | Status: OPEN

## Goal
Sebenco Climb's long concrete wall and Sinucit's overhang are about 1.5 times brighter than on the PSP: wall pixels
(113, 125, 126) in the port against (70, 81, 83) in PPSSPP, on draws that are unlit, fogged, vertex-coloured CLUT4
textures. Both backends draw the same pixels, turning the port's fog or lighting off changes nothing, and the mip
levels have the same mean colour, so the cause is upstream of the backends: the framework's GE state or vertex
decode, or a GE rule neither backend applies. This task finds it by bisecting one draw against PPSSPP's GE dump of
the same frame, and fixes it where it is (a vendor patch to the GE state or the decode, or a backend rule), or
reports the rule with evidence if the fix is larger than a task.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 3: the frame, the draws 197, 198 and 201 of the task's dump, the pixel
  values, what was ruled out), docs/ppsspp.md and ref/README.md (burst K's command for the Sebenco Climb frame with
  `--gedump`, how a `.ppdmp` is read: `tools/ppsspp/ppdmp.py`), docs/ge-backend.md 7 (ge_replay `--cut N --out` for
  a port draw's picture), docs/metal-backend.md ("How a draw is drawn": colour, texture function, vertex colour)
- vendor/portablekit/host/gpu/ge_state.cpp (vertex decode: colour formats 5650/5551/4444/8888 and the colour's
  unpacking; the material colour; TEXFUNC's colour-double bit (RGB x2) and TCC; the fog colour; the ambient),
  host/gpu/shaders/ge.frag (what the Vulkan fragment shader multiplies), src/gpu/metal_shaders.h (the same in MSL)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: the texture function with colour doubling, the vertex
  colour formats, fog, the material/ambient rules for unlit draws)
- tools/ppsspp/ppdmp.py (the dump reader: a draw's state and its vertex data), tools/imgdiff.py

## Deliverable
1. The bisection: PPSSPP's GE dump of the Sebenco Climb first race frame (make it with burst K's command and
   `--gedump`; the audit's was lost with its worktree) and a port recording of the same frame (`PURE_GE_RECORD` on
   the route, one frame). For the wall's draws, side by side: the GE state PPSSPP's dump holds (TEXFUNC bits, vertex
   type's colour format, the vertex colours decoded, the material colour, fog, ambient) and the port's `DrawCall`
   (`gerec_dump.py`), field by field; the first field that differs, or, if none differs, the first rule the shader
   applies that PPSSPP's documentation says differently. Write the table in docs/fidelity.md under difference 3.
2. The fix, where it is: a vendor patch (0016 `tools/patches.sh export 0016-<cause>`) if the state or the decode is
   wrong, or a backend change in `src/gpu/` if the Metal shader applies a rule wrongly (then say what the Vulkan
   path does, which has the same pixels). The wall's pixels within tol 16 of PPSSPP's afterwards.
3. The check across the game: `tools/frame_regress.sh` (headless Metal, 18 scenes) with the fractions before and
   after, and the Sebenco Climb and Sinucit first race frames against their references (the audit's reference table
   has them; add the port route for Sebenco Climb to `config/pad_scripts/` if it needs one, or capture through the
   sweep's shots at the matching flip, and say how).
4. docs/fidelity.md (difference 3's row: the cause, the result), patches/README.md if a patch, docs/metal-backend.md if
   a backend rule.

## Acceptance criteria
- [ ] The cause is named with the field or rule and the evidence table.
- [ ] After the fix, the Sebenco Climb frame's fraction against PPSSPP drops from about 0.32 to under 0.10, Sinucit's
      from 0.12 to under 0.06, and no suite scene rises by more than 0.003.
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` reported (it may change if the fix is in the state).

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh`

## May touch
- vendor/portablekit/host/gpu/ge_state.cpp, texture_decode.cpp (via `tools/patches.sh export 0016-<cause>`), patches/,
  src/gpu/, config/pad_scripts/ (a Sebenco Climb capture route), tools/ppsspp/routes/ (a dump route), docs/fidelity.md
  (difference 3), docs/metal-backend.md, patches/README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/hle/, host/shell/, src/host/, src/profile/, src/tools/, tools/frame_regress.sh,
  ref/*.png (new references are allowed only through the documented capture commands, listed in ref/README.md)

## Estimated turns
60

## Escalate when
The field-by-field comparison shows no difference and no documented rule explains the factor (report the table and
the three candidate rules you considered), or the fix would change the vertex decode for every draw (report the
scope and the suite's deltas with the change applied in a throwaway build).

## Result
Status: PARTIAL. The cause is found, and it is not in the port: there is nothing to fix in the GE state, the
vertex decode or a backend. So acceptance criterion 1 is met. Criteria 2 and 3 cannot be met by a code change. The
substituted replay below shows what criterion 2 asks for, and no code changed, so nothing could move the Vulkan path.

**The cause.** The wall is drawn exactly as on the PSP. The brightness comes 580 draws later, from the game's weather
mist (FxScreenMist.cpp). The mist is two full-screen additive layers of a soft CLUT8 texture. The game computes their
alphas and texture coordinates on the CPU from its own state: each layer's phase moves with the camera's motion, and
the layer's texture offset is drawn again from the game's random generator each time the phase wraps. The port and
PPSSPP reached the first race frame with the mist in different phases. On Sebenco Climb the layer alphas (GE 0x58)
are 0x49 and 0x02 in the port against 0x1C and 0x30 in PPSSPP, and their texture coordinates differ too. The sum is
the same, 75 against 76: the weather's intensity matches and only the phase differs. Sinucit has the same mist, with
0x30 and 0x02 against 0x12 and 0x20 (sum 50 in both).

**The bisection.**
- PPSSPP's GE dump of the reference frame: burst K's command plus `--gedump 7670`. Its PNG is byte-identical to the
  audit's `sebenco_climb_hud.png`, and Sinucit's run (`--gedump 7662`) to `sinucit_hud.png`. Both pairs are in `ref/`.
- The port's recording: new routes `config/pad_scripts/beta_sebenco_climb.txt` and `beta_sinucit.txt`, then
  `PURE_GE_RECORD` at flip 6018 (6016). The capture scores 0.3207 at tol 32, as the audit measured.
- `ppdmp.py cover` names the wall's draws (381 and 384) and the track's beside it (392 and 465). The port numbers
  them the same.
- Field by field, every vertex and every texel of those draws is the same in both (the table is in
  docs/fidelity.md, "Difference 3: the weather mist").
- `--replay --cut N` puts the port's wall pixel at (65,75,75) from draw 382 through draw 960. Draw #961, the first
  mist layer, raises it by 56 levels. In PPSSPP the mist adds about 12.
- The first field that differs is the mist's material alpha.

| Check (Sebenco Climb unless named, fraction at tol 32) | Before | After (no code change) | Port recording with PPSSPP's mist alphas and texture coordinates put in, replayed into Metal |
|---|---|---|---|
| Sebenco Climb frame against `ref/sebenco_climb_hud.png` | 0.3207 | 0.3207 | 0.0613 (target under 0.10) |
| wall pixel (420,150), PPSSPP (77,88,87) | (127,137,137) | the same | (79,89,89), within tol 16 |
| Sinucit frame against `ref/sinucit_hud.png` | 0.1163 | 0.1163 | 0.0445 (target under 0.06) |

In the port's own runs, delaying the route on MAIN MENU changes the mist by itself. Delays of 0, 2, 30, 60, 90 and
120 flips give alphas 0x49/0x02, 0x4C/0x00, 0x46/0x06, 0x2C/0x20, 0x3B/0x10 and 0x46/0x05. The fractions are 0.321,
0.329, 0.167, 0.069, 0.069 and 0.117. A run held to real time (`PURE_PACED_FROM=5600`) is identical to the unpaced
one.

**The suite, before and after** (headless Metal; before = batch/m2 at 8d3bc3e, after = the Verify run at 10225f2).
All 18 scenes are the same to four places, and none rises:

| Scene | lang | title | profile | main_menu | race_hud | single_player .. team_select (5) | tt_track_select | tt_hud | fp_track_select | fp_hud | tournament_select | zone_track_select | zone_hud | zone_change |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Before | 0.0002 | 0.0002 | 0.0000 | 0.0106 | 0.0374 | 0.0000 each | 0.0000 | 0.0617 | 0.0000 | 0.0620 | 0.0000 | 0.0000 | 0.0348 | 0.0649 |
| After | 0.0002 | 0.0002 | 0.0000 | 0.0106 | 0.0374 | 0.0000 each | 0.0000 | 0.0617 | 0.0000 | 0.0620 | 0.0000 | 0.0000 | 0.0348 | 0.0649 |

The Vulkan suite (`--shell vulkan --backend vulkan`) was not run. No source, vendor or patch file changed, so its
pictures cannot have moved, and its windowed runs would have held the machine for seven minutes while tasks 036 and
039 ran their own games.

Changed:
- config/pad_scripts/beta_sebenco_climb.txt, beta_sinucit.txt (new): the capture routes.
- docs/fidelity.md: difference 3's row, a line under "Not differences", and the section "Difference 3: the weather
  mist" (the frames and commands, the field-by-field table, the code reading, the substitution and delay tables).
- This file.
- No vendor patch. Nothing in `ge_state.cpp` or `src/gpu/`. docs/metal-backend.md and patches/README.md unchanged.
- Not committed (git-ignored): `ref/sebenco_climb_hud.{png,ppdmp}` and `ref/sinucit_hud.{png,ppdmp}` in this
  worktree. The main checkout's `ref/` lacks them; copy them there or make them with the commands in docs/fidelity.md.

Verify output (last 20 lines; `tools/verify_task.sh 038` at 10225f2, 2026-10-07 01:06, after ten refusals while other
workers' games ran; the commit after it adds this Result only):
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0374   0.10   32    0.0379 -0.0005  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0617   0.12   32    0.0617 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0620   0.11   32    0.0620 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0348   0.09   32    0.0348 +0.0000  PASS
zone_change   5679    0.0649   0.10   32    0.0649 +0.0000  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 25s)
verify 038: PASS
```

Open questions:
- How should the suite compare weather tracks (Sebenco Climb, Sinucit, and any other track with FxWeather)? A
  first-race-frame row compares two mist states as well as two renderers. One option is a port route that reaches
  PPSSPP's mist state, but that tunes the route to a random state. Another is a mist-substituted replay as above.
  A third is to compare the frame with the two mist draws left out on both sides.
- What carries the menus' length into the mist was not isolated: the random generator's state, which FxWeather's
  constructor also draws two oscillator phases from, or the drift term in the camera-motion helper. Pacing to real
  time does not move it, so it is counted in frames.
- The game placed the track textures elsewhere in VRAM (0x041E81C0 against 0x041EF7C0) and the mist's CLUT 0x200
  bytes further on in RAM than in PPSSPP. The bytes are the same. This is probably the asset load order (difference
  6's load timing) and was not followed up.
- The comparison readers were scratch scripts: a full `DrawCall` parser on gerec_dump.py, a register reader on
  ppdmp.py, and a .gerec patcher that substitutes one draw's material colour and texture coordinates. A tool for
  these would make the next bisection quicker, but `tools/` was outside this task's May touch.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

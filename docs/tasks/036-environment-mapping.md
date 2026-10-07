# 036: Environment and projection texture mapping (fidelity difference 1)

Milestone: M8 | Branch: task/036-environment-mapping | Status: MERGED 2026-10-07 (934ccdd)

## Goal
The most visible difference in docs/fidelity.md: reflective surfaces (the ship's hull and canopy, always on screen;
glass buildings; shiny roofs) show their reflection texture stretched over the model instead of a reflection. The GE
has three texture-coordinate sources: the vertex's UVs (TEXMAPMODE 0), a matrix applied to a chosen vertex attribute
(TEXMAPMODE 1, projection mapping, 40 draws on Vineta K), and environment mapping from the normals and two of the
lights (TEXMAPMODE 2, 46 to 125 draws a race frame; TEXSHADELS names the lights). The framework's GE state ignores the
mode and the lights, so every backend draws mode 0. This task carries the state (a vendor patch, since `ge_state` is
the framework's) and makes the Metal backend compute the coordinates by the GE's rules.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 1 and its evidence; the reference table: which scenes show the ship),
  docs/metal-backend.md (the vertex path: through mode, transformed, the uniforms, `metal_shaders.h`), docs/ge-backend.md
  sections 1 and 7 (`DrawCall`, ge_replay for Metal against Vulkan: Vulkan will not have this, so the race A/B moves)
- vendor/portablekit/host/gpu/ge_state.hpp and .cpp (`TextureState`, `DrawCall::texture_matrix`, how commands become
  state; the ignored-command list the audit counted: TEXMAPMODE 0xC0, TEXSHADELS 0xC1, and TEXPROJMAP's source),
  host/gpu/shaders/ge.vert (what the Vulkan path does with UVs today)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only; the GE's texture mapping modes: mode 1 applies the
  texture matrix to position, UV, normalized normal or normal as TEXPROJMAP says; mode 2 takes the dot products of
  the normalized normal with the two shade lights' positions (directional lights: their direction), mapped to [0, 1])
- src/gpu/metal_backend.mm (`fill_lighting`, the vertex uniforms, `expand`), src/gpu/metal_shaders.h (`ge_vertex`),
  patches/README.md (the row format), tools/gerec/ (ge_replay `--cut` and recordings for a draw-level check)

## Deliverable
1. Patch 0013 (`tools/patches.sh export 0013-texture-mapping-modes`): `TextureState` (or `DrawCall`) carries
   `map_mode` (0, 1, 2), `proj_source` (TEXPROJMAP: 0 position, 1 UV, 2 normalized normal, 3 normal) and the two
   shade-light indices; `ge_state.cpp` sets them from the commands and no longer lists them as ignored. The Vulkan
   backend is unchanged in behaviour (it keeps mode 0; a comment says so); `tools/frame_regress.sh --shell vulkan
   --backend vulkan` must stay 18/18 at its column. The record format gains the fields at the end (the reader skips
   what it does not know; bump `kVersion` only if a field is in the middle).
2. The Metal backend: `ge_vertex` computes texture coordinates by `map_mode`: 1 applies the 4x4 texture matrix to
   the chosen source (the GE's 3-component input with the matrix's translation; UVs with w 1); 2 takes the
   normalized normal in model or view space as the GE does (check the docs and PPSSPP's description, not its code) dotted
   with the two shade lights' directions (position for a directional light), mapped to [0, 1] each; 0 as today. The
   texture scale and offset apply after, as for mode 0. Lighting's light table is already in the uniforms.
3. A draw-level check: a short recording of a race frame (`PURE_GE_RECORD` through the sweep's route, 1 frame, as
   docs/ge-backend.md 7 does) replayed with `--cut` at an environment-mapped draw of the ship, the picture before and
   after in docs/metal-backend.md, against PPSSPP's reference of the same scene (`ref/race_hud` or `zone_hud`: the
   ship's canopy region, `tools/imgdiff.py --region`).
4. docs/metal-backend.md: the mapping modes; docs/fidelity.md: difference 1's row updated with the result (the
   scenes' fractions before and after); patches/README.md row; README.md if a switch is added (`PURE_NO_TEXMAP` to
   draw mode 0, for A/B).

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (headless Metal, 18 scenes) passes, and the four race scenes (`race_hud`, `tt_hud`,
      `fp_hud`, `zone_hud`) each score lower than their measured values by at least 0.005, with the ship's canopy
      region within tol 32 on at least 95% of its pixels against the reference (report the region and numbers).
- [ ] No scene scores higher than its measured value by more than 0.003 (the frontend has no mapped draws).
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18 unchanged; `tools/patches.sh check` 13 patches.
- [ ] `tools/hud_check.sh` 61 of 61.

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh && python3 tools/imgdiff.py out/regress/shots/race_hud.png ref/vineta_k_start.png --max-frac 0.032 --tol 32`

## May touch
- vendor/portablekit/host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp, vulkan_renderer.cpp (a comment or
  the field forwarded unchanged), via `tools/patches.sh export 0013-texture-mapping-modes`; patches/; src/gpu/;
  tools/gerec/gerec_dump.py (the new fields, if it parses Draw records in full); docs/metal-backend.md,
  docs/fidelity.md (difference 1's row), README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/hle/, host/shell/, src/host/, src/profile/, src/tools/, tools/frame_regress.sh,
  tools/campaign_sweep.py, config/, ref/, patches/0001-0012

## Estimated turns
70

## Escalate when
The GE's mode 2 rule cannot be settled from the documentation (report the two candidate rules and the pictures each
gives against the reference; do not read PPSSPP's source into the repo), or the record format cannot take the fields
without breaking `ge_replay` on existing recordings (report; re-recording is acceptable, say so).

## Result
Status: DONE

What was done:
- **Patch 0013** (`0013-texture-mapping-modes`): the GE state carries `DrawCall::texture_map` (`TextureMapState`:
  `map_mode`, `proj_source`, `shade_light_u`, `shade_light_v`) from TEXMAPMODE 0xC0 (bits 0..1 and 8..9) and
  TEXSHADELS 0xC1 (bits 0..1 and 8..9), so both left the ignored list (63 commands now, from 65). A Draw record ends
  with the four as u32. A Draw that ends before them reads as map mode 0, and `kVersion` stays 1. The main checkout's
  `race_1x.gerec` of 2026-10-06 still parses in `gerec_dump.py` and replays Vulkan against Metal as before (frame
  6016, 2 pixels over tol 24). The Vulkan renderer is unchanged; comments in `vulkan_renderer.cpp` and
  `ge_state.hpp` say it draws mode 0.
- **Metal**: `map_texture` in `ge_vertex`.
  - Mode 1: the texture matrix times (position, or (u, v, 0), or the normalized normal, or the normal; with w 1).
    s and t are divided by q per pixel.
  - Mode 2: s and t are (N.L' + 1) / 2 for the two TEXSHADELS lights, in world space. N is the world matrix times
    the normal, with the dot product divided by |N|. L' is normalize(position) for a directional light and
    normalize(position - world position) otherwise. For a diffuse-and-specular light it is normalize(L' + V), where
    V is the view matrix's third column, normalized.
  - The lighting block is now filled for environment-mapped draws, which are unlit in this game.
  - `PURE_NO_TEXMAP=1` draws mode 0. With it, the 18 captures are pixel-identical to the build before the task.
- **Sources for the rules**: PPSSPP's hardware notes (the ge-vertex-pipeline page and the lighting page's "Shade
  mapping" section). No PPSSPP code was read. The register layout comes from the PSP SDK's
  `sceGuTexMapMode`/`sceGuTexProjMapMode`. PPSSPP's dumps confirm it: on Vineta K, 96 draws have 0xC0 = 2 with
  0xC1 = 0x100, and 40 have 0xC0 = 1 (position source).
- **Where this differs from the brief**: modes 1 and 2 do **not** apply the texture scale and offset afterwards.
  - The notes say shade mapping does not depend on them, and they name mode 0 as the scale-and-offset mode.
  - The suite cannot tell the two rules apart. A throwaway build that applied them in mode 2 gave all 18 captures
    pixel for pixel.
  - In the port's race frame, 12 environment-mapped draws into the billboard target carry a v scale of -1, as do all
    40 texture-matrix draws.
- **Draw-level check**: I recorded race frame 6016 headless through Metal (the record backend, 1 frame, the suite's
  route).
  - Draws #357 to #359 are the ship's environment-mapped hull and canopy. #360 to #362 are the livery over them.
    #359 alone is the canopy.
  - `--cut 360`, with the modes against `PURE_NO_TEXMAP=1`: in the canopy region 1312 of 1680 pixels change, 1073 of
    them by more than 32 (mean 51.7 levels). Without the modes the hull is near-black with streaks; with them it has
    a grey reflection shading and a highlight on the canopy.
  - The full replay is pixel-identical to the suite's `race_hud` shot.
- `gerec_dump.py` reads the new fields and lists mapped draws as `envmap U,V` or `texmatrix SOURCE`.
  `PURE_METAL_LOG` lines carry the same tags.

The scenes, headless Metal at tol 32. "Before" is `PURE_NO_TEXMAP=1`, which is pixel-identical to the build before the task. The
fractions were the same in three runs.

| Scene | Before | After | Canopy region | Region before | Region after |
|---|---|---|---|---|---|
| race_hud (vs ref/vineta_k_start.png) | 0.0374 | 0.0262 | (225,177) 30x56, draw #359's footprint | 0.2690 (452 of 1680) | 0.0125 (21): 98.8% within tol 32 |
| tt_hud | 0.0617 | 0.0229 | (225,177) 30x56 | 0.2988 (502) | 0.0333 (56): 96.7% |
| fp_hud | 0.0620 | 0.0232 | (225,177) 30x56 | 0.2994 (503) | 0.0333 (56): 96.7% |
| zone_hud | 0.0348 | 0.0122 | (212,183) 66x45, the Zone ship's dome | 0.3566 (1059 of 2970) | 0.0141 (42): 98.6% |
| zone_change | 0.0649 | 0.0353 | | | |

The 13 frontend scenes are unchanged pixel for pixel.

Acceptance:
- Suite 18/18. Against the measured column: race_hud -0.0117, tt_hud -0.0388, fp_hud -0.0388, zone_hud -0.0226, each
  at least 0.005 lower. Each canopy region is at least 95% within tol 32.
- No scene scores higher than its measured value; the largest delta is +0.0000.
- `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18, every scene within 0.0005 of its vulkan column
  (19m 49s). `tools/patches.sh check`: 13 patches.
- `tools/hud_check.sh` (Metal shell): 61 of 61.

Changed: patches/0013-texture-mapping-modes.patch (vendor host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp,
and a comment in vulkan_renderer.cpp), patches/README.md, src/gpu/metal_backend.mm, src/gpu/metal_shaders.h,
tools/gerec/gerec_dump.py, docs/metal-backend.md ("Texture mapping modes" with the draw-level check and the numbers,
"Verify numbers / Task 036", the switch, the uniforms, the Vulkan differences), docs/fidelity.md (difference 1's row),
README.md (`PURE_NO_TEXMAP`, the `PURE_METAL_LOG` tags).

Verify output (last 20 lines; `tools/verify_task.sh 036` at 8b28258, 2026-10-07):
```
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0262   0.10   32    0.0379 -0.0117  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0229   0.12   32    0.0617 -0.0388  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0232   0.11   32    0.0620 -0.0388  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0348 -0.0226  PASS
zone_change   5679    0.0353   0.10   32    0.0649 -0.0296  PASS

moved more than 0.03 from the metal measured value: tt_hud fp_hud (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 24s)
PASS fraction 0.026180 (3418/130560 pixels differ by more than 32, limit 0.032) at 480x272
verify 036: PASS
```

Open questions:
1. **Scale and offset in modes 1 and 2.** I followed the hardware notes, not the brief, and the suite cannot tell the
   two apart. A capture where it would show: PPSSPP's Vineta K draws #123 to #125. That is an AI ship with v scale
   -1 and clamp, from a team the port's grid did not have in that frame. With the scale applied it would sample only
   the first row of its environment texture.
2. **Mode 1 has no picture check.** Vineta K's 40 texture-matrix draws (four passes projecting onto a horizontal
   plane) are clipped or culled in frame 6016, as they are in PPSSPP's dump. A frame where that plane is on screen
   would check it.
3. **Reversed normals (0x51).** They flip N in mode 2 as they do in lighting. The notes do not say whether they
   should, and the game sets none.
4. **The suite's metal column is stale.** It still holds the pre-task values; tt_hud and fp_hud print "moved more than
   0.03". Re-baselining (docs/verification.md) needs `tools/frame_regress.sh`, which is outside May touch. The new
   values are race_hud 0.0262, tt_hud 0.0229, fp_hud 0.0232, zone_hud 0.0122 and zone_change 0.0353.
5. **The Metal-against-Vulkan race replay now differs.** On a recording made since patch 0013 the two backends differ
   by the mapped draws: frame 6016 has 2387 pixels over tol 24 (0.0183), just under metal_check.sh's 0.02. With
   `PURE_NO_TEXMAP=1` the difference is 0 pixels. `tools/gerec/metal_check.sh` should set it once it records again;
   that file is outside May touch. Its existing recordings pass as before.
6. **The lighting's specular uses a different viewer.** Its half vector takes the viewer along world +z (task 024's
   port of ge.vert). The notes give V as the view matrix's third column, which mode 2 now uses. I did not change it
   because lighting is outside this task, and the race uses no specular.
7. **docs/ge-backend.md section 6** describes the Draw record and is outside May touch. The format's reference header
   in `ge_record_format.hpp` is updated.

## Review
Verify rerun from the main checkout on the merged build, 2026-10-07: thirteen patches reproduce vendor at 8b0c3fe;
the headless suite 18/18 with the race scenes at the new values exactly (race_hud 0.0262, tt_hud 0.0229, fp_hud
0.0232, zone_hud 0.0122, zone_change 0.0353; the frontend unchanged) and `race_hud` against `ref/vineta_k_start.png`
0.0262 under the 0.032 limit. The suite's Metal column was re-baselined to those values (28fab19) and the race A/B in
`tools/gerec/metal_check.sh` runs with `PURE_NO_TEXMAP=1`, since the Vulkan path keeps mode 0. `verify_task.sh 036`
itself exited 2 in a retry loop while the save-list worker held the machine; the same checks were run directly with
the suite's `--allow-parallel`.
Spot-read: patch 0013 (`TextureMapState` from TEXMAPMODE and TEXSHADELS, the Draw record's fields appended, the
Vulkan path's comment), `map_texture` in the MSL (mode 1 through the texture matrix with the chosen source and a
per-pixel divide, mode 2 from the world-space normal and the two shade lights by the hardware notes), the lighting
block filled for mapped draws, `PURE_NO_TEXMAP`.
Merged: 934ccdd into batch/m2.
Notes: the worker's departure from the brief (no scale and offset in modes 1 and 2, as the hardware notes say) is
accepted; the suite cannot tell the two apart and the notes are the reference. Open questions kept as follow-ups in
docs/status.md: a mode 1 picture check (Vineta K's projected plane is off screen in the suite's frame), reversed
normals in mode 2, the lighting's specular viewer (world +z in task 024's port against the view matrix's third
column), and docs/ge-backend.md section 6's Draw record description (updated here by hand? no: left to the next
seam doc edit).

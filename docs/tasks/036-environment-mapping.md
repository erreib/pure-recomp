# 036: Environment and projection texture mapping (fidelity difference 1)

Milestone: M8 | Branch: task/036-environment-mapping | Status: OPEN

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

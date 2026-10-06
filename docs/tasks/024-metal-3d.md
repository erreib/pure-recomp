# 024: The Metal GE backend, 3D: lighting, fog, sprites, culling

Milestone: M6 | Branch: task/024-metal-3d | Status: OPEN

## Goal
Task 023's Metal backend draws transformed (3D) geometry with its vertex colour only. This task makes 3D draws right:
the GE's lighting (four lights, material colours, ambient, specular power), fog, transformed sprites expanded in
screen space as the GE does, culling confirmed on the race, and anything else in `DrawCall` that a 3D draw carries
and the backend ignores today. The reference is the Vulkan backend through ge_replay (task 022), backend against
backend on recordings that have no bloom and no stencil work, since those are task 025's. The race frame against
PPSSPP is measured and reported, not yet a pass condition.

## Read first
- CLAUDE.md, docs/metal-backend.md (all of it: how a draw is drawn, the pipeline key, "What is not done yet",
  "Where it differs"), docs/ge-backend.md sections 1, 2, 6 and 7 (ge_replay: `--a/--b`, `--first-diff`,
  `--frames`), docs/ge-effects.md (the race's bloom chain and shadow volumes, which this task leaves alone)
- src/gpu/metal_backend.mm, src/gpu/metal_shaders.h (what exists), src/tools/ge_replay.cpp (the tool's options)
- vendor/portablekit/host/gpu/ge_state.hpp (`LightingState`, `LightState`, `FogState`, `DrawCall::lighting_enabled`,
  `material_color`, `has_vertex_color`, `environment_version`, `material_version`), host/gpu/shaders/ge.vert and
  ge.frag (the lighting and fog the Vulkan backend computes: port them), vulkan_renderer.cpp (`submit`: how sprites
  are expanded for transformed draws, how lit draws without a vertex colour are coloured, the cull decision)
- tools/gerec/replay_check.sh (how recordings are made and replayed), config/pad_scripts/single_race.txt (the route
  through CLASS, LEAGUE, TRACK and TEAM to the race; the TEAM screen shows a lit, rotating ship model)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: the GE's lighting model, sprite rule and fog) if a
  detail is not in ge.vert

## Deliverable
1. Lighting in `metal_shaders.h` and the uniforms that feed it: the GE model as `ge.vert` computes it (per-vertex;
   light kinds directional, point, spot; diffuse, specular with the material's power, ambient; the material
   update bits choosing between the vertex colour and the material colours; `reverse_normals`), for draws with
   `lighting_enabled`. Unlit draws keep their vertex or material colour as today.
2. Fog as `ge.vert`/`ge.frag` do (`FogState`: end, scale, colour), applied where the GE enables it.
3. Transformed sprites expanded in screen space after projection (the GE's rule: the second vertex's depth and
   colour; the rectangle axis-aligned on screen), with the Vulkan backend's result as the reference.
4. Culling confirmed on the race (the frontend culls nothing): `cull_clockwise` against Metal's winding in window
   coordinates, checked by `--first-diff` against Vulkan; fix if wrong.
5. Whatever else `--first-diff` against Vulkan turns up in a lit, fog-free, stencil-free frame (a texture
   coordinate rule, a depth-range case, a colour clamp): fix it if it is a 3D rule, record it in
   docs/metal-backend.md if it is 025's.
6. `tools/gerec/metal_check.sh TEAM_FRAME`: records `out/gerec/team.gerec` when missing (the `single_race.txt` route
   with the record backend at the TEAM screen frame you choose, 2 frames, Vulkan inner; write the chosen frame into the
   script as its default and say in docs/metal-backend.md how you chose it: a frame where the ship model is lit and
   no bloom or stencil draw is in the list, checked with `PURE_METAL_LOG` or `gerec_dump.py`), then runs
   `PureNative --replay out/gerec/team.gerec --a vulkan --b metal --tol 24 --max-frac 0.02` and, for the record,
   `--replay out/gerec/race_warm.gerec --a vulkan --b metal --frames 6016 --tol 24 --first-diff` (reported, not a
   pass condition: the first differing draw should be one of the bloom chain or a stencil draw, 025's).
7. docs/metal-backend.md: lighting and fog rows in "How a draw is drawn", the sprite rule, the culling check, the
   numbers (team frame fraction, race frame 6016 fraction against Vulkan and against PPSSPP via
   `tools/frame_regress.sh --backend metal --only race_hud`, the first differing draw), and "What is not done yet"
   reduced to 025 and 026. README.md if a switch is added.

## Acceptance criteria
- [ ] `metal_check.sh`: the team recording replayed into vulkan and metal passes at tol 24, max-frac 0.02 (the
      remaining pixels are edges from 2x against 1x).
- [ ] The race frame 6016 bisection's first differing draw against Vulkan is a bloom-chain or stencil draw (task
      025's), not a lit or fogged one; the fraction against Vulkan and against PPSSPP is recorded.
- [ ] `tools/frame_regress.sh --backend metal --only lang,title,profile` still passes with the task 023 fractions
      (0.0002, 0.0002, 0.0000), and the Vulkan suite still passes 5/5 unchanged.

## Verify
`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal --only lang,title,profile`

## May touch
- src/gpu/ (the backend and its shaders), tools/gerec/metal_check.sh (new), docs/metal-backend.md, README.md

## Must not touch
- vendor/, patches/, src/profile/, src/hle/, src/host/, src/tools/ (ge_replay: if it lacks an option you need,
  report it), tools/frame_regress.sh, tools/gerec/replay_check.sh, config/, ref/, CMakeLists.txt

## Estimated turns
70

## Escalate when
No frontend frame with a lit model is free of bloom and stencil draws (report the frames you checked and what they
contain; the acceptance then needs a different reference), or a difference against Vulkan traces to the Vulkan
backend being wrong against the GE's documented rule (report both, do not match a Vulkan bug), or ge_replay needs a
change. Do not start on the stencil, the bloom chain, read-backs or write-backs (025).

## Result
**Status: PARTIAL.** All seven deliverables are done and the Verify line passes, but the brief's escalation
condition occurred: no frontend frame has a lit model (none has a lit draw at all), so lighting and fog are checked
against a different reference, the race at internal scale 1 up to its first stencil draw. That substitution, and
recording the check at internal scale 1, need the reviewer's acceptance.

**What was found.** The route run on Metal with `PURE_METAL_LOG=1` to frame 5760 (151590 draws): frames 1-5707 (boot
to the loading screen) have no lit, fogged, stencil or bloom draw; depth-tested draws only at boot (5-123) and on the
loading screen (5702-5706). TEAM SELECTION (5503-5701, 65-69 draws a frame once it has come in) draws its "rotating ship" as ten
textured quads (pre-drawn 256x128 CLUT8 outline pictures), all draws orthographic and linear-filtered. The first lit
draws are the race's (5708 on: 220-261 lit, 519 stencil, 5 bloom draws a frame). The previous worker's
`team_range.gerec` (5540-5699) shows the same: no lit draw in 160 frames.

**Results.**
- `tools/gerec/metal_check.sh` (default TEAM frame 5650) passes: team frames 5650-5651 recorded at internal scale 1
  replay into vulkan and metal identically (0 of 130560 pixels at tol 0). Recorded at 2x they score 0.0519 at tol 24
  (6773 px, all glyph edges: the minified, filtered text moves 0.4 texel under the 2x-to-1x reduction), so the
  brief's 0.02 could not pass at 2x by construction; the script records team.gerec (and race_1x.gerec) with
  `PURE_INTERNAL_SCALE=1` and re-records a file that holds other frames or another scale.
- Race frame 6016, `--first-diff --tol 24`: at 1x (race_1x.gerec) the first differing draw is 394 of 906, the
  stencil-gated darkening quad that applies the shadow volumes (025's); draws 1-393 (58 lit, 360 fogged, 353 culled)
  match Vulkan to 0 px over tol 1 (36 px one level off). At 2x (race_warm.gerec, the brief's command) it is draw 40:
  11 px of an alpha-test edge on a fogged strip that writes the stencil, moved by the 2x-to-1x reduction; bisected
  past 5% of the pixels it is 394 again. Whole frame against Vulkan 0.3246 (1x), 0.3768 (2x); against PPSSPP
  (`frame_regress.sh --backend metal --only race_hud`) 0.2978 (task 023: 0.2977), dominated by that quad darkening the
  whole screen without the stencil, and by the missing bloom.
- Sensitivity, Metal alone against Vulkan at draw 393: NO_LIGHTING 1936 px over tol 24, NO_FOG 555, NO_CULL 68, the
  winding reversed (throwaway build) 63574 and a first difference at draw 41; as built 0. Culling is right.
- Transformed sprites: the GE's screen-space rule; on all 26 (TEAM) and 28 (race) recorded transformed sprite draws
  it gives exactly Vulkan's object-space rectangles (0.0000 px), so no Vulkan deviation shows in this game's frames.
- `frame_regress.sh --backend metal --only lang,title,profile`: 0.0002, 0.0002, 0.0000 (task 023's). Vulkan suite
  5/5 at 0.0544, 0.0302, 0.0543, 0.0331, 0.0672, captures pixel-identical to the main checkout's run of 07:30.

**The WIP (a013197).** Kept whole: the shader port of ge.vert's lighting and ge.frag's fog and separate specular,
the uniform blocks and their layouts, `fill_lighting`, the screen-space transformed-sprite expansion, the
`lighting_bound_` reset in `begin_pass` (already in the WIP: it built and ran as committed, and is exact against
Vulkan as above). Changed: added the framework's `PURE_NO_LIGHTING`, `PURE_NO_FOG`, `PURE_NO_CULL` (read as Vulkan
reads them; used for the sensitivity runs), brought the file header, culling and `expand` comments and the
registration description up to date. No change to the lighting, fog or sprite code was needed.

**Changed:** `src/gpu/metal_backend.mm`, `src/gpu/metal_shaders.h` (the WIP), `tools/gerec/metal_check.sh` (new),
`docs/metal-backend.md` (lighting, fog and transformed-sprite rows, culling confirmed, "The 3D check" with the
survey, the 1x rationale and the numbers, "What is not done yet" down to 025 and 026 plus what `DrawCall` lacks),
`README.md` (metal_check.sh row, the Metal switch rows), this file.

**Verify output (last 20 lines)** (`tools/verify_task.sh 024`, at c5f5527; later commits are docs only):
```
  blend off: source 2 destination 3 equation 0, fixed 0x000000/0x000000
  alpha test on: function 6 reference 0x7F mask 0xFF
  stencil on: function 1 reference 0x04 mask 0xFF, ops fail 0 depth fail 0 pass 2
  clear mode off
  depth test on function 6, write on, write masks colour 0x000000 alpha 0x00

metal_check: PASS (6 s)
frame regression 2026-10-06 07:26, commit c5f5527, backend metal (PURE_GE_BACKEND: recorded, not enforced)
extra environment: none
run frontend: 2130 flips ...
run frontend: run_boot exit 0, frame 2130 reached: yes, 72 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a0ae6699800a8e309/out/regress/frontend.log

scene       frame  fraction  limit  tol  measured   delta  result
lang          690    0.0002   0.07   24     0.054  -0.054  PASS
title        1750    0.0002   0.05   24     0.030  -0.030  PASS
profile      2100    0.0000   0.07   24     0.054  -0.054  PASS

moved more than 0.03 from the measured value: lang profile (something changed; docs/verification.md)
frame regression: PASS, 3/3 scenes pass (1m 12s)
verify 024: PASS
```
(The "moved more than 0.03" line compares against Vulkan's measured values; the Metal fractions are task 023's.)

**Open questions.**
1. Accept the race at 1x, draws 1-393 of frame 6016, as the lighting and fog reference in place of the lit TEAM
   frame that does not exist? It covers ambient, emissive, two directional diffuse lights, the material update bits
   with and without a vertex colour, and four fog settings. Point and spot lights, specular, powered diffuse,
   reversed normals and the separate specular are ported from ge.vert but no recording exercises them.
2. Accept the check's recordings at internal scale 1? On a fresh checkout the Verify line records team.gerec (about
   3 min) and race_1x.gerec (3.5 min) on its first run; race_warm.gerec is replay_check.sh's.
3. The branch is based on 26ebe69 and does not contain main's patch 0011; `tools/worktree_init.sh` applied all
   eleven patches, so every build and number here is with 0011, as main builds now. A rebase onto main was refused
   by the session's permissions; main's two later commits touch only docs/ and patches/, no file of this branch.
4. For 025: the throwaway tools that cut a recording after draw N and diff each backend's picture (scratch, in
   `out/024/tools/` of the worktree) were what made this bisection readable; a `--cut N` with `--out` in ge_replay
   would do the same in-tree.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

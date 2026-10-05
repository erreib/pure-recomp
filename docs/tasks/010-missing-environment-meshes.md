# 010: Why the track surface, barriers, arches, pillars and sky are not drawn

Milestone: M3 | Branch: task/010-missing-environment-meshes | Status: OPEN

## Goal
Task 007 showed the port's physics match PPSSPP, but on Vineta K the port draws crowds, billboards, the far skyline,
ships and HUD and leaves out the track surface, the barriers, the stadium arches (only their cyan light strips show),
the pillar bodies and the sky (`out/007/side_t05-t20.png`, `out/007/side_grid.png`). Find which draws of the frame
produce those pixels in PPSSPP, what our port does with the same draws, and fix the renderer or the GE state
(vendor patch 0005) or, if the draws never reach the renderer, say where they are lost.

## Read first
- CLAUDE.md, docs/status.md (Blockers: "Environment meshes not drawn"), docs/ge-effects.md (the frame's structure and
  the draw numbering of the PPSSPP dump), docs/research.md section "GE usage" (int8/int16/float vertices with
  per-chunk scale, VEXX node types, sea/sky cube/fog cube)
- tools/ppsspp/ppdmp.py (parses ref/vineta_k_start.ppdmp; can also replay our `PURE_TRACE_GE_LIST` output)
- vendor/portablekit/host/gpu/ge_state.cpp (vertex type decoding, PRIM handling, bezier/spline tessellation at
  ~1137-1221, the unhandled-command default at ~956), host/gpu/shaders/ge.vert (the clip-space z remap at ~291-297,
  the viewport mapping), host/gpu/vulkan_renderer.cpp (culling, depth test and depth range setup, scissor/region)
- out/race-nofb.log in the main checkout: the "unhandled GE command" list for the race (0x15/0x16 REGION, 0x1c CPE=1,
  0x20 DTE, 0x24 STE, 0x26 PCE, 0x27 CTE, 0x28 LOE, 0x2c-0x33 MW0-7, 0x36 PSUB=0x1010, 0x37 PPRIM, 0x38 PFACE,
  0x50 LMODE=1, 0xa1-0xa4 TBP1-4)

## Deliverable
1. From ref/vineta_k_start.ppdmp: the list of draws that cover the track surface, the near barrier and the sky (the
   large environment meshes), with their PRIM type, vertex type word decoded (position/texture/colour/normal formats,
   weights, morph, index format, through), vertex count, cull state, depth test/range, texture. The simplest way to
   identify them: render the dump in PPSSPP's GE debugger step by step (docs/ppsspp.md), or reason from vertex
   counts and textures (the track and barriers are the largest meshes).
2. The same draws in our port's GE list for the equivalent frame (`PURE_TRACE_GE_LIST`, replayed with ppdmp.py), and
   what the renderer does with them: skipped (why), drawn but clipped or culled (the z remap? the depth range? cull
   winding?), or drawn with a vertex format decoded wrongly. Check in this order: vertex type bits the decoder does
   not support (weights/morph/index/float16), depth range/viewport (VSZ/VOZ, MINZ/MAXZ 0xd8/0xd9) against the shader's
   remap, culling and FFACE, patches (PSUB/PPRIM/PFACE are set).
3. The smallest fix, as `patches/0005-<slug>.patch` via `tools/patches.sh export`, with a README row; or, if it is
   not a renderer fault, the exact point where the draws are lost.

## Acceptance criteria
- [ ] The Result names the draw numbers (PPSSPP dump) and the cause with file:line.
- [ ] After the fix, the port's first full-HUD race frame (route `~/dev/pure-recomp/out/race/route.txt`, captures
      with `--shots --every 10` around 6250-6400 to find it; `PURE_NO_FB_TEXTURES=1`) compared with
      ref/vineta_k_start.png at tol 32 has a fraction below 0.45 (it is 0.685 at r6400 today, a different moment, and
      0.946 for task 006's pair), and the track surface and barrier are visibly present in the capture.
- [ ] `tools/patches.sh check` passes; the frontend route's title capture still matches ref/title.png within 0.05.

## Verify
`tools/patches.sh check && python3 tools/imgdiff.py out/010/race-hud.png ref/vineta_k_start.png --tol 32 --max-frac 0.45 && python3 tools/imgdiff.py out/010/title.png ref/title.png --tol 24 --max-frac 0.05`

## May touch
- vendor/portablekit/host/gpu/ via `tools/patches.sh export 0005-<slug>` only, patches/, docs/ge-effects.md (a section
  on the environment draws), tools/ppsspp/ppdmp.py (improvements), out/010/

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/run_boot.py, tools/imgdiff.py, config/, patches/0001-0004
  (0004 may land from task 009 meanwhile; rebase on batch/m2 if `tools/patches.sh check` complains about the series)

## Estimated turns
60

## Escalate when
The draws are not in our port's GE list at all (the game never issues them: a CPU-side difference), or the fix
needs the renderer's vertex pipeline restructured beyond one decode path or one pipeline-state field.

## Result
(worker fills)

## Review
(Fable fills)

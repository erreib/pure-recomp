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

Status: DONE

Changed:
- `patches/0005-alpha-test-never-always.patch` (new; vendor `host/gpu/shaders/ge.frag`, `host/gpu/vulkan_renderer.cpp`)
  and its row in `patches/README.md`. Written on top of 0001-0003; 0004 (task 009) did not exist in this branch.
- `tools/ppsspp/ppdmp.py`: `cover` (coverage-only rasteriser: which draw is visible where, per-draw pixel counts,
  false-colour PNG, `--highlight`), `--vt` on `draws` and `gelist` (decoded vertex type, cull/FFACE, depth clamp,
  MINZ-MAXZ), world/view/projection matrices tracked from INIT and the register stream.
- `docs/ge-effects.md`: section "The environment draws and the alpha test (task 010)", and the commands under
  "Reproducing".
- Captures in `out/010/` (not committed): `race-hud.png`, `title.png`, `cover_all.png`, `cover_always.png`,
  `cover_hl1.png`, `nocull/`, `nodepth/`, `base/` (before), `fix/` (after), `hud*/`, `gelist.log`.

Draws (PPSSPP dump `ref/vineta_k_start.ppdmp`, numbers from `ppdmp.py cover`, last opaque writer of each pixel):

| Draws | What | Pixels | PRIM x vertices | Vertex type | Texture | Cull, depth |
|---|---|---|---|---|---|---|
| 175, 178 (174, 177 farther) | track surface | 20563, 13090 | tristrip x274, x272 | 0x00013d: uv s8, col 8888, nrm s8, pos s16; no weights, morph, index, through | 0x0417e380, 0x0417fb80 CLUT4 64x64 swz, 4 mips | cull 1, FFACE 0; z GT + write; clamp 1; MINZ-MAXZ 1001-64946 |
| 176 | track edges and near barriers, both sides | 17890 | tristrip x270 | 0x00013d | 0x0417ef80 CLUT4 64x64 | same |
| 165, 490 | barrier top, light band on the right barrier | 1627, 953 | tristrip x209, x43 | 0x00013f: uv f32, col 8888, nrm s8, pos s16 | 0x041f6680, 0x041a8900 CLUT4 64x64 | same |
| 486, 496, 497, 499, 510, 511, 513 | stadium arches | 28033 together | tristrip x97-x337 | 0x00013d / 0x00013f | CLUT4 in VRAM | same |
| 598-602 | sky cube (602 in view) | 23868 (602) | tristrip x81, x81, x81, x163, x81 | 0x00011d: uv s8, col 8888, pos s16 | RAM CLUT8 256x256 | cull 0; z GT; viewport z -473/+473; MINZ-MAXZ 0-946 |

All of them have ALPHATESTENABLE 0x22 = 1 with ALPHATEST 0xDB = 0x000001: function 1 = ALWAYS, ref 0. In the dump
268 of 871 draws (31651 of 72733 vertices) are set up that way and they own 113566 of 130560 pixels (87%,
`out/010/cover_always.png`); the rest is what the port already drew (crowds with GREATER 0x7F, ships, shadow
volumes, billboards).

Our port, same draws: `PURE_TRACE_GE_LIST=470000:4000` traced frames 6361-6372; frame 6364 (`ppdmp.py gelist --all
--vt`) has 866 draws, 301 with the test on and ALWAYS; the track run is its draws 270-274 (x177, x274, x270, x158,
x272, vertex type 0x00013d, the dump's 174-178 in the same order), the sky cube 590-594 (x81 x81 x81 x163 x81,
0x00011d, MINZ-MAXZ 0-946), all ALWAYS ref 0. The draws reach the renderer with the same GE state.

What the renderer did, in the brief's order: vertex types are plain (ge_state.cpp:389 decodes them); viewport z
-31973/32973 gives Vulkan depth 0.991..0.015 (vulkan_renderer.cpp:6180-6186), the same for the crowds that drew, and
the track's z/w stays in [-1, 1] (draw 176: -0.97..0.99), so the ge.vert:291-297 remap clips nothing; MINZ/MAXZ are
stored but never applied (draws more, not less); `PURE_NO_DEPTH=1` and `PURE_NO_CULL=1` runs still had no track
(`out/010/nodepth/r6400.png`, `out/010/nocull/r6400.png`); no BEZIER/SPLINE in the frame. Cause: the alpha test.

- `vendor/portablekit/host/gpu/shaders/ge.frag:72`: `if (alpha_function == 1) passed = false; // never`, and
  function 0 passed. The GE numbers alpha-test functions like depth-test ones (0 NEVER, 1 ALWAYS; the renderer's own
  depth mapping at vulkan_renderer.cpp:335-342 has them right).
- `vendor/portablekit/host/gpu/vulkan_renderer.cpp:6057`: the discard variant was compiled in for any function but 0,
  so ALWAYS draws got it; `:6082` pushed 0 for "no test", `:6090` 0 for clears.
  (Line numbers of the pin plus 0001-0003.) Every fragment of every ALWAYS draw was discarded and the white clear
  showed through.

Fix (patch 0005): the shader tests by the GE numbering (0 discards, 1 passes), the push carries 1 (ALWAYS) for draws
without the test and for clears, and the pipeline leaves the discard out for ALWAYS instead of NEVER. Four lines plus
comments; one pipeline-state field and one shader comparison.

Numbers (imgdiff against ref/vineta_k_start.png, tol 32, `PURE_NO_FB_TEXTURES=1`, route `out/race/route.txt`):

| Capture | Before | After |
|---|---|---|
| r6250 (READY ring) | 0.698 | 0.362 |
| r6400 | 0.685 | 0.348 |
| first full-HUD frame, 6016 (`out/010/race-hud.png`) | - | 0.349 |
| title vs ref/title.png (tol 24) | 0.0302 (task 006) | 0.0302 (3943 px, unchanged) |

Every after-capture from 6016 to 6400 is between 0.343 and 0.425. The HUD fades in over 6011-6016 in the capture
run (timer, POS and LAP reach full brightness at 6016); in another run it finished about 4 frames later. Track
surface, barriers, arches, pillars and sky are visible in race-hud.png.

Verify output:
```
ok: 4 patch(es) reproduce vendor/portablekit at 8b0c3fe
PASS fraction 0.348974 (45562/130560 pixels differ by more than 32, limit 0.45) at 480x272 (resized from 960x544 and 480x272)
PASS fraction 0.030201 (3943/130560 pixels differ by more than 24, limit 0.05) at 480x272 (resized from 960x544 and 480x272)
```

Open questions:
- Ordering with 0004: 0005 was exported over 0001-0003. If task 009's 0004 lands first and touches the same
  `submit()` lines (pipeline key, push constants), `tools/patches.sh check` will fail; re-export 0005 on top of 0004
  (the change is the four lines above).
- The brief names MINZ/MAXZ as 0xD8/0xD9; they are 0xD6/0xD7 (0xD8-0xDA are the colour test). The renderer ignores
  them and the depth-clamp enable 0x1C (CPE=1 here: the PSP then does not clip at the far plane, Vulkan does). Neither
  matters for this frame (all z/w within [-1, 1]); Vulkan `depthClamp` would be the one-field fix if far geometry ever
  goes missing.
- The ship shadows are solid dark-blue blocks: draws 339-356 are zfail INCR/DECR stencil volumes with MASKRGB
  0xFFFFFF, and stencil and write masks are ignored (task 009's area).
- VRAM texture addresses differ between our port and PPSSPP by 0x1DC0 (0x0417d5c0 vs 0x0417e380 for the track), so
  the game's VRAM allocation differs somewhere upstream of the GE; harmless here, not investigated.
- `tools/verify_task.sh` (named in CLAUDE.md) does not exist in `tools/`; I ran the Verify line by hand.
- No off switch for the fix (the vendor AGENTS.md asks for one for new behaviour); the old behaviour is a numbering
  bug, so none was added.

## Review
(Fable fills)

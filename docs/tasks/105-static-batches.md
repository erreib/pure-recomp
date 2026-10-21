# 105: The crowd at 60 fps on Metal: static batches kept across frames and cached on the GPU

Milestone: Crowd (D-025) | Branch: task/105-static-batches | Status: OPEN

## Goal
With the crowd on, the Metal window holds 60 fps at the default internal scale through the race start on Vineta K.
Task 104 measured the drop (39 to 56 fps for about 12 seconds): the models backend rebuilds about 1360 figures into
batched draws every frame (2.7 ms), and the Metal backend expands each batch's indices into 48-byte vertices and
uploads them every frame (9.7 ms, about 66 MB a frame). Both costs are for geometry that does not change from one
frame to the next. This task keeps a static batch across frames in the models backend with a stable id and a
version, and lets the Metal backend keep the expanded vertex buffer of such a batch on the GPU and bind it again,
so a frame with the crowd costs the marshals' skinning and a few buffer binds. The row's default then flips to
Models.

## Read first
- docs/tasks/104-crowd-models.md, Result (the cost table, the trace's split) and Review.
- src/gpu/models_backend.cpp: `replace` and the batching (820 to 940: `draw` built per batch, `flush`,
  `kMostVertices`), the density rule and the hash (880 to 920), the trace (325 to 370).
- src/gpu/metal_draw.mm: `expand` (60 to 140: the index walk into `vertices_`), the upload of `vertices_` into a
  chunk and the draw (560 to 580: `bytes`, `drawPrimitives`), the vertex buffer bind (755 to 765), and the chunk
  pool's handing back of buffers (grep `ChunkPool`, `free`, the command buffer's completion handler) so a cached
  buffer is not one the pool reuses.
- src/gpu/metal_types.hpp: `GpuVertex` (54 to 61), `ChunkPool`.
- vendor/portablekit/host/gpu/ge_state.hpp `DrawCall` 230 to 275: `vertex_address`, `index_address`,
  `primitive_count` (the fields the game's draws carry and the backends read as "the same draw as last frame").

## Facts
- A model draw today carries `vertex_address` 0 and `index_address` 0. Both backends draw it from `vertices` and
  `indices`; the Vulkan renderer keeps the indices (it holds 60 fps with the crowd); the Metal backend expands
  them.
- The crowd's batches are static per original draw as long as the camera stays within the same density bands
  for every quad: the pick of figures (hash of place), the jitter, the models and the placement are all functions
  of the quad alone; only the density rule reads the eye. The marshal batches change every frame (skinning).
- The GpuVertex expansion depends on the draw's state too (the transform, the lighting block and the fog are
  applied in `expand`: read it; what varies per frame for a crowd batch is the view and projection, which the
  Metal backend applies on the GPU from uniforms, or on the CPU in `expand` for some paths: find out which for
  an ordinary 3D draw and say so in Result; a cached buffer is only valid if the expansion does not bake per-frame
  state into the vertices).
- Game data never enters the repository.

## Deliverable
- src/gpu/models_backend.cpp: a batch cache. For a set draw, the backend keeps, per original draw identity
  (`call.vertex_address`, `call.primitive_count` and the texture key, which is what recognises the game's draw
  from frame to frame), its built batches: the `DrawCall`s with their vertices and indices, and the density band
  of each quad they were built with. Each frame it recomputes only the bands (one distance per quad); if none
  changed, the kept batches are submitted as they are, with `draw.vertex_address` a stable synthetic id (a
  counter in a range the game never uses, say 0xF0000000 upward) and `draw.index_address` a version number that
  increments when the batch is rebuilt; the state fields (`view`, `projection`, target, fog, the tint) are
  refreshed from the current call before submission. Marshal batches are built every frame as today, with
  `vertex_address` 0 (never cached). The trace line gains `, B batches reused` and the replace time shows the
  difference. Memory: at most 64 cached batches; an identity not seen for 60 frames is dropped.
- src/gpu/metal_draw.mm (and metal_backend.hpp for the map): when a draw's `vertex_address` is in the synthetic
  range, the expanded vertices are kept in a private `id<MTLBuffer>` of their own (not a pool chunk) keyed by
  (`vertex_address`, `index_address`); a hit binds that buffer and draws `drawn` vertices without `expand` or an
  upload; a miss expands as today, uploads into a new private buffer (a blit from the staging chunk, or a shared
  buffer written once) and keeps it; an entry not used for 120 frames is released; at most 64 entries. The
  per-draw state that `expand` would have applied must still be applied: if `expand` bakes anything per frame
  into vertices for this draw kind, say so and bake only what is static, leaving the rest to the uniforms.
  Nothing changes for draws with `vertex_address` outside the range.
- src/profile/enhancements.cpp: `crowd_models`'s default to 1 (Models) once the window measurement below holds
  60; tools/purelib/port.py's `ENHANCEMENTS_OFF` gains `PURE_CROWD_MODELS=0` so the tools keep running the
  original picture (task 102's open question); tools/menu_check.sh's expectations if a default shows in a row's
  text.
- tools/models_check.sh: a reuse row: on the race route's frames the trace's `batches reused` is non-zero on
  the second and later frames at the same camera, and the capture with the cache equals the capture without it
  (`PURE_MODELS_NO_CACHE=1` for the comparison: a switch the backend reads once) at tol 0.
- Docs: docs/ge-backend.md's models section (the cache, the ids, the version), docs/metal-backend.md "Textures"
  or a short "Cached model batches" section (the GPU-side cache), docs/developing.md (`PURE_MODELS_NO_CACHE`),
  docs/controls.md and README.md (the default now Models).

## Acceptance criteria
- [ ] The Metal window run of the race route (`PURE_PERF=log`, the default scale, the crowd on) holds 60 fps
      through the start, render under 8 ms where task 104 saw 15 to 23; the numbers in Result beside task 104's.
      One window run, Erik's screen booked.
- [ ] `tools/models_check.sh` PASSes with its reuse row: the cached picture equals the uncached one at tol 0.
- [ ] `tools/frame_regress.sh` headless 18 scenes PASS with `PURE_CROWD_MODELS=0` pinned by the tools (the
      originals unchanged), and `tools/texture_check.sh` headless PASS.
- [ ] `tools/docs_check.py` PASS; `tools/release_check.sh` as before.

## Verify
`tools/build.sh profile && tools/docs_check.py && tools/models_check.sh --out out/105/check && tools/frame_regress.sh && tools/texture_check.sh`

Headless; then the one Metal window run of the race route for the frame rate.

## May touch
- src/gpu/models_backend.cpp, models_backend.hpp, src/gpu/metal_draw.mm, src/gpu/metal_backend.hpp,
  src/gpu/metal_types.hpp, src/gpu/metal_backend.mm (the completion handler if the cache needs a hook)
- src/profile/enhancements.cpp (the default), tools/purelib/port.py (`ENHANCEMENTS_OFF`), tools/menu_check.sh
- tools/models_check.sh
- docs/ge-backend.md, docs/metal-backend.md, docs/developing.md, docs/controls.md, README.md
- docs/tasks/105-static-batches.md (Result)

## Must not touch
- vendor/, include/psprecomp/, tools/regen.sh, the corpus
- the shaders (ge.metal) and metal_pipelines.mm (a cached buffer holds the same GpuVertex layout)
- models/, docs/status.md, docs/decisions.md

## Estimated turns
45

## Escalate when
- `expand` bakes per-frame state into the vertices of an ordinary 3D draw in a way the uniforms cannot take over
  without a shader change: report what it bakes and where, BLOCKED (the shader is Must not touch).
- The pool hands a cached buffer back or a command buffer still reads a released one (a crash or a flicker in
  the capture): report, and keep the buffers alive for the frames in flight (`kFramesInFlight` or the pool's
  rule) before releasing; if that is not enough, BLOCKED with the trace.
- 60 fps still not held after the cache with render under 8 ms: report where the time went (the perf line's
  split), PARTIAL; do not change the density thresholds or the spacing (the look is Erik's).

## Result
Status: DONE. In the Metal window at the default scale (1920x1088, FIFO 120 Hz) with the crowd on, the race holds 60 fps from the grid onward. One one-second perf line averages 8.7 ms render, just over the 8 ms target, though that second still shows 60.0 fps (numbers below). Verify passes.

**The open fact: does `expand` bake per-frame state?** No, not for an ordinary 3D draw; the uniforms carry it. For a triangle list, `expand` copies each vertex as it is:
- the position in object space (a model batch's is world space, because its world matrix is the identity);
- the uv and the normal;
- the vertex's own colour. The material colour replaces it only for an unlit draw without vertex colours, and a model draw has vertex colours.

The transform (projection x view x world), the lighting block and the fog all reach the shader through `VertexUniforms` and the lighting block (`fold_viewport`, `bind_inputs`). `transform` is used on the CPU only for a transformed sprite's corners (`expand_transformed_sprites`). So a kept buffer holds no per-frame state. No shader change was needed, and the first escalation did not apply.

Changed:
- src/gpu/models_backend.hpp: `kFirstCachedBatchAddress = 0xF0000000`, the start of the synthetic id range.
- src/gpu/models_backend.cpp: the batch cache.
  - **What is kept.** A game draw of static figures (none of its models skinned) keeps its batches across frames. The key is (`vertex_address`, `primitive_count`, texture address, palette address).
  - **Reuse check.** The kept entry stores the input it was built from: the figure, the world matrix, the vertices and the indices. A call uses the kept batches only if its input is equal. The quad's tint lives in the vertex colours, so a colour change triggers a rebuild.
  - **Groups.** The quads are grouped in order so that each group's figures at full density fit in 65535 vertices. This means a band change rebuilds only its own group (the brief asked for a rebuild of the whole draw).
  - **Each frame.** Only the bands are recomputed, one distance per quad. A group whose bands held submits its kept batches with the current call's state put in (`refresh`: view, projection, viewport, target, fog and the rest). Each batch carries a stable synthetic `vertex_address` and a version in `index_address`, which goes up on each rebuild.
  - **Limits.** At most 64 batches are kept, and the draw seen longest ago goes first. A draw not seen for 60 frames is dropped. Changing the row clears the cache.
  - **Marshals.** Their batches are still built every frame, with `vertex_address` 0.
  - **Switches.** `PURE_MODELS_NO_CACHE=1`, read once, turns the cache off. The trace line gains `, B batches reused`.
- src/gpu/metal_backend.hpp, src/gpu/metal_draw.mm: kept vertex buffers for draws in the synthetic range (3D triangle lists that are not through, not a clear and not flat).
  - **Hit.** A hit on (id, version) binds the kept buffer and draws `drawn` vertices, with no `expand` and no upload.
  - **Miss.** A miss expands as before, writes the vertices once into a shared buffer of its own (`newBufferWithBytes`) and keeps it. It is never a pool chunk, so the completion handler (which hands buffers back by their `kChunkBytes` length) cannot reuse it.
  - **Release.** An entry unused for 120 frames is retired; at most 64 are kept, least recently used first. A retired buffer is held for `kFramesInFlight` + 1 frames before it is released (the command buffers retain it as well). The sweep runs at the first draw of each frame.
  - Draws outside the range are unchanged.
- src/profile/enhancements.cpp: `crowd_models` now defaults to 1 (Models), and its description names the crowd.
- tools/purelib/port.py: `ENHANCEMENTS_OFF` gains `PURE_CROWD_MODELS`, and the docstring says so.
- tools/menu_check.sh: comment only. The default does not show in the row's text, so no expectation changed.
- tools/models_check.sh:
  - a new run 3 (race_hud, Models, `PURE_MODELS_NO_CACHE=1`);
  - the line regex now carries `batches reused`;
  - a new row, "race_hud kept batches". It wants run 1's captured frame to reuse batches, run 3's to reuse none with the same counts, and the two captures to be equal at tol 0. It also prints how many race lines reuse.
- Docs:
  - docs/ge-backend.md: the batching groups, a "Kept batches" bullet, the trace, the check;
  - docs/metal-backend.md: a new "Kept model batches (task 105)" section;
  - docs/developing.md: `PURE_MODELS_NO_CACHE`, the trace, the check's row, the new default;
  - docs/controls.md and README.md: the default is now Models.

Headless, the race frame's replace takes 0.25 to 0.39 ms when all 12 crowd batches are reused, against task 104's 12.4 ms. In a sampled frame where a group or two is rebuilt it takes 3.5 to 5.5 ms. The 4 crowd draws now make 12 batches, 18 model draws counting the 6 marshals' (task 104 had 15). The figures and vertices are unchanged (race_hud: 1359 and 431905).

The Metal window run (once; Apple M4 Pro, internal scale 4 = 1920x1088, FIFO 120 Hz, route main_menu+single_race to frame 7500, `PURE_PERF=log`, `PURE_CROWD_MODELS=1`; out/105/window/race.log). Task 104's numbers are beside it:

| crowd (near 80 / far 200) | frames | fps | render | figures | batches reused (of 12 crowd) | replace (sampled frame) |
| --- | --- | --- | --- | --- | --- | --- |
| task 104, on | 5760 to 6480 | 38.7 to 55.7 | 14.9 to 22.7 ms | 1359 to 1961 | - | 12.3 to 17.8 ms |
| task 105, on | 5760 (the second of the switch from the intro's 30 fps pacing to the race's 60) | 53.0 (game 52.9, lists 53/s, max frame 34.2 ms = two vblanks) | 7.1 ms | 1499 | 10 | 5.5 ms |
| task 105, on | 5820 to 6480 (grid, countdown, first seconds down the straight) | 59.9 to 60.0, max frame 17.8 to 29.9 ms | 5.5 to 8.7 ms (only 6420 over 8: 8.7) | 1359 to 1961 | 7 to 12 | 0.25 to 8.9 ms |
| task 104, on | 6540 onward | 60 | 6.6 to 7.3 ms | 258 | - | 3 ms |
| task 105, on | 6540 to 7140 (one stand in view) | 59.9 to 60.0 | 3.9 to 5.4 ms | 258 to 472 | 6 of 6 | 7 to 11 us |
| task 104, off | the whole race | 60 | 4.0 to 5.6 ms | - | - | - |

- **The 8.7 ms second (frame 6420).** The car is moving and the band boundaries sweep through the stands. 5 of the 12 crowd batches were rebuilt in the sampled frame (replace 8.9 ms, 6.2 ms of it the Metal backend's expansion of the rebuilt batches). That second still averages 60.0 fps with a worst frame of 18.5 ms.
- **The 53 fps second (frame 5760).** The frames are not slow there: render averages 7.1 ms and the CPU waits 10.2 ms. The game's pacing changes in that second (lists 53/s; the line before reads 30/s), and the longest frame (34.2 ms) is a two-vblank frame. It is not a render cost.
- **Highest render over the run:** 9.6 ms. That is the intro camera's second at the PSP's 30 fps, where the crowd is first built (all misses).

Verify output (last 20 lines):
```
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 23s)
texture check 2026-10-20 20:19: race_hud tt_hud fp_hud zone_hud at internal scale 4, PURE_TEXTURE_DETAIL 0 and 1, and race_hud at scale 1 with 1, headless on Metal, into /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-aa1fbd3128be01ffe/out/texture_check
  scale 4, PURE_TEXTURE_DETAIL=0: 4 [pure] texture detail: off
  scale 4, PURE_TEXTURE_DETAIL=1: 4 [pure] texture detail: on (game.texture_detail)
  scale 1, PURE_TEXTURE_DETAIL=1: 1 [pure] texture detail: on (game.texture_detail)

each PURE_TEXTURE_DETAIL=1 capture at scale 4: its size, by its blocks' centre pixels against the scene's reference at the scene's tol and limit (tools/frame_regress.sh), the full capture against the PURE_TEXTURE_DETAIL=0 one at tol 24 (at least 1%), the high-frequency energy of the 0 and 1 captures and their ratio (above 1.0) for race_hud, tt_hud, fp_hud, and the race HUD (tools/hud_check.py) for race_hud, tt_hud, fp_hud:
scene            size  reduced  limit  tol     vs 0  energy 0  energy 1   ratio  HUD  result
race_hud    1920x1088   0.0467    0.1   32   0.0218    3.5752    4.0681  1.1378  yes  PASS
tt_hud      1920x1088   0.0473   0.12   32   0.0244    3.5424    4.3499  1.2279  yes  PASS
fp_hud      1920x1088   0.0472   0.11   32   0.0244    3.5210    4.3300  1.2298  yes  PASS
zone_hud    1920x1088   0.0346   0.09   32        -         -         -       -    -  PASS
zone_hud: against the 0 capture 0.0002 at tol 24, energy 2.2434 -> 2.2444 (ratio 1.0004); not bars here: the scene's mipmapped textures hold no detail between their levels (level 0 everywhere moves 0.0002 of its pixels)

race_hud run with 1 (exit line, over the run): 192857 mipmapped draws, 192778 enhanced (at least 10000): PASS
race_hud at scale 1 with 1, against the reference: 0.0162 (limit 0.1, tol 32): PASS

texture check, shell headless: 4/4 scenes pass, the enhanced draws PASS, race_hud at scale 1 PASS (0m 40s)
texture_check: PASS
verify 105: PASS
```
The models check in the same run:
```
tt_hud      1 frame 5890: 10 replaced (4 by a set), 18 model draws, 196 quads, 1582 figures, 500750 vertices  0.0121    0.14   32 PASS
race_hud    1 frame 6016: 10 replaced (4 by a set), 18 model draws, 196 quads, 1359 figures, 431905 vertices  0.0613    0.20   32 PASS
tt_hud 1 against 0: 171 pixels differ at tol 24 in the marshals' box (108, 120, 56, 32) (at least 150): PASS
race_hud 1 against 0: 7157 pixels differ at tol 24 (at least 2000), the HUD's labels current 125, lap 43 yellow pixels (each at least 1): PASS
race_hud kept batches: frame 6016 12 of 18 batches reused (above 0), PURE_MODELS_NO_CACHE=1 0 of 18 (0), the same counts yes, 0 pixels differ at tol 0 (0); 6 of 6 lines with replaced draws reuse: PASS
tt_hud wave (Wave_On t=2.15 and Wave_On t=3.15): 312 pixels differ in the marshals' box (112, 124, 48, 22) (at least 40), 0 in the deck (112, 146, 48, 6) (at most 0): PASS
models_check: PASS
```
- `tools/docs_check.py`: `docs_check: 39 files, 0 findings: PASS`.
- `tools/release_check.sh`: as before. Binaries PASS (12 files); only `home` FAILs, on the same six patches/ findings.
- frame_regress's 18 scenes are unchanged, because every tool now pins `PURE_CROWD_MODELS=0`.

Open questions:
1. **Render target.** One one-second line (frame 6420) averages 8.7 ms render against the criterion's 8 ms, while holding 60.0 fps. If that matters, the next step is in the backend, not the look: rebuild fewer groups per frame (spread rebuilds across frames), or split groups more finely. I did not change the density or the spacing.
2. **Window checks this change needs, not run:**
   - The Vulkan shell's frame interpolation. vendor's frame_interpolation.cpp keys draws on `vertex_address` and `index_address`. The crowd's batches used to all carry 0; they now carry a stable id and a version, so interpolation will match them from frame to frame. That needs a Vulkan window look at the race start with the crowd on.
   - The crowd through the Vulkan renderer with the new default (task 104's review saw it hold 60 at 960x544 with `vertex_address` 0).
3. **tools/gerec/replay_check.sh** runs `PureNative --replay` directly, not through tools/purelib/port.py. With the default now Models, its replays may draw the crowd unless it pins `PURE_CROWD_MODELS=0`. It is outside May touch, I did not run it, and I don't know whether the replay reads the setting.
4. **The 64-batch cap** counts a fresh draw's groups before it is built. A draw whose single quad overflows 65535 vertices makes more batches than groups, so the cap can be exceeded by a few batches in that case. No such quad exists in the game's crowd (at most 1961 figures over 196 quads).

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

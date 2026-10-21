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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

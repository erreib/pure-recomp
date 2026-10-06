# 021: The GE backend seam: interface, null and record backends, Vulkan adapter

Milestone: M6 | Branch: task/021-ge-backend-seam | Status: OPEN

## Goal
Introduce `portablekit::gpu::GeBackend` (docs/ge-backend.md section 1) as vendor patch 0009, adapt the existing
Vulkan renderer to it without changing its output, and add the `null` and `record` backends. Selection by
`PURE_GE_BACKEND=vulkan|null|record` (default vulkan). The regression suite must give the same fractions before and
after.

## Read first
- CLAUDE.md, docs/ge-backend.md (the contract), docs/decisions.md D-003, docs/ge-effects.md,
  vendor/portablekit/host/gpu/vulkan_renderer.hpp (the public interface), host/hle/hle_media.cpp (every
  `renderer.`/`renderer->` call: the seam's call sites), host/gpu/ge_state.hpp (DrawCall, BlockTransfer),
  patches/0003-0008 (behaviour the adapter must keep), ~/dev/bouncer-recomp/src/gs/null_backend.cpp and
  patches/0020-gs-backend-recording.patch there (the shape of null and record backends; read-only)

## Deliverable
1. `host/gpu/ge_backend.hpp`: the interface from docs/ge-backend.md, `BackendConfig`, `PresentedImage` (an opaque
   handle the shell understands per API: for Vulkan the existing image/view the present path already uses), a
   registry (`register_backend(name, factory)`, `make_backend(name)`), and the selection by `<prefix>_GE_BACKEND`.
2. `VulkanGeBackend`: forwards to the existing renderer's draw/transfer/read-back/write-back/upload/capture/stats
   methods. The shell (the rest of VulkanRenderer) calls the backend through the interface for those operations.
   Keep the change mechanical; no behaviour change.
3. `null_backend.cpp`: accepts everything, presents a black image, counts draws; the game must run through the
   frontend route headless with `PURE_GE_BACKEND=null` (`PURE_NO_RENDER` unset) at > 200 fps.
4. `record_backend.cpp`: wraps the selected inner backend (`PURE_GE_RECORD_INNER`, default vulkan); writes
   `PURE_GE_RECORD=<file>` from frame `PURE_GE_RECORD_AT` for `PURE_GE_RECORD_FRAMES` frames: a versioned stream of
   DrawCall/BlockTransfer/upload/read-back/write-back events with their guest-memory inputs (vertices, indices,
   textures, CLUTs, the ring of VRAM words a draw reads) and the presented image per frame (BMP). A `gerec_dump`
   tool (C++ in the vendor tools or Python in tools/gerec/) lists a recording's events.
5. Patch 0009 via `tools/patches.sh export`, README rows, a section in docs/ge-backend.md "What landed".

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (task 020) passes with the same fractions (+/- 0.005) as before the patch.
- [ ] `PURE_GE_BACKEND=null` frontend route runs headless to frame 2000 and reports draws submitted.
- [ ] A 3-frame recording of the race at frame 6016 (`PURE_GE_RECORD_AT=6014 PURE_GE_RECORD_FRAMES=3`) is written and
      `gerec_dump` lists its events with counts that match `[render] frame ... (N draws)`.

## Verify
`tools/patches.sh check && tools/frame_regress.sh && PURE_GE_BACKEND=null python3 tools/run_boot.py --frames 2000 --seconds 120 --env PURE_NO_RENDER= out/021/null.log && grep -q 'draws' out/021/null.log`

## May touch
- vendor/portablekit/host/gpu/ and host/hle/hle_media.cpp via `tools/patches.sh export 0009-<slug>`, patches/,
  tools/gerec/ (new), docs/ge-backend.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/run_boot.py, tools/imgdiff.py, config/, patches/0001-0008

## Estimated turns
70

## Escalate when
The Vulkan adapter cannot keep the output identical without restructuring the renderer's frame loop (report what the
loop assumes), or the shell cannot run without a window for the null backend (report the dependency).

## Result
(worker fills)

## Review
(Fable fills)

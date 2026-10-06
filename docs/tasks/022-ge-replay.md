# 022: ge_replay: feed a .gerec recording to any GE backend and compare the pictures

Milestone: M6 | Branch: task/022-ge-replay | Status: OPEN

## Goal
The record backend (task 021, patch 0009) writes what the shell asked a GE backend to do, with the guest memory each
call read and the picture each frame presented. This task adds the other half of the A/B method: a replay that feeds
a recording to a backend outside the game and compares what it presents with the recorded images, or with a second
backend, draw by draw. It is how the Metal backend (tasks 023 to 025) will be brought up and checked against Vulkan
without running the game each time.

## Read first
- CLAUDE.md, docs/ge-backend.md (sections 1, 4 and 6: the contract, the method, what landed), docs/decisions.md D-003
- vendor/portablekit/host/gpu/ge_backend.hpp (the interface), ge_record_format.hpp (the format, the Reader),
  record_backend.cpp (how each call was recorded: what comes before and after it), null_backend.cpp
- vendor/portablekit/host/hle/hle_media.cpp: `present_frame` (the order of calls at a flip, which the replay must
  mirror: upload_frame, write_back_frame, present_image, the shell's `VulkanRenderer::present`, capture_frame,
  begin_frame) and `ensure_backend` (how a backend and the Vulkan shell are made)
- vendor/portablekit/host/main.cpp (the end: `PORTABLEKIT_HOST_MAIN_NAME`), cmake/PortableKit.cmake
  (`portablekit_add_game`: `HOST_MAIN_NAME`, `SOURCES`), CMakeLists.txt (ours)
- vendor/portablekit/include/psprecomp/guest_memory.hpp (`GuestMemory(size)`, `raw_pointer`, the VRAM window)
- tools/gerec/gerec_dump.py (a reader of the same format, in Python), tools/imgdiff.py (the comparison the suite
  uses: per-channel tolerance, fraction of differing pixels, both pictures resized to 480x272)
- docs/tasks/021-ge-backend-seam.md (Result: the recording command, open question 7 on record order)

## Deliverable
1. **Our own entry point.** `src/host/pure_main.cpp` defines `main()`. When `argv[1]` is `--replay` it runs the
   replay below and exits with its code; otherwise it calls the framework's main, compiled as `portablekit_main`
   through `HOST_MAIN_NAME portablekit_main` in our `portablekit_add_game` call (CMakeLists.txt). The game must start
   exactly as before when `--replay` is absent (`tools/run_boot.py` and the suite do not change).
2. **The replay**, `src/tools/ge_replay.cpp`, in the same executable (there is no host library to link a separate tool
   against; the host sources are compiled into the game's executable):
   ```
   build/arm64/bin/PureNative --replay FILE.gerec [--backend NAME] [--out DIR] [--compare] [--tol T] [--max-frac F]
                                                 [--frames A[-B]] [--a NAME --b NAME [--first-diff]] [--quiet]
   ```
   - It reads the file, makes the backend (`gpu::make_backend`, default `null`), initialises it (for `vulkan` it
     first makes a `VulkanRenderer`, initialises it as `ensure_backend` does, and passes it as `vulkan_shell`; `null`
     and later `metal` need none), and owns a `psprecomp::GuestMemory` (32 MiB) that stands for the game's.
   - It walks the records in order, as the shell made the calls: Memory records are written into guest memory before
     the call that reads them; Words records are written too (a backend compares those words to tell whether the CPU
     wrote under a target); DisplayList → `begin_display_list()`; Draw → `submit()`; Transfer → `block_transfer()`,
     then the replay copies the rows itself as `hle_media.cpp`'s `block_transfer` does (the Memory records that follow
     the Transfer hold the source rows as the copy read them); ReadBack → `read_back_framebuffer()`; WriteBackFrame
     → `write_back_frame()`; WriteBackDepth → `write_back_depth()` with the recorded arguments; Upload →
     `upload_frame()`; FrameEnd → `present_image(display address)`, for the Vulkan backend the shell's `present()`
     (its frame ends there), then `capture_frame()` into a temporary or `--out DIR/frame_N.bmp`, then
     `begin_frame()`. Unknown record kinds are skipped by size.
   - `--compare` compares each replayed frame's capture with the recorded image of that frame as `tools/imgdiff.py`
     does (both resized to 480x272 nearest-neighbour, a pixel differs when any channel differs by more than `--tol`,
     default 0; the frame passes when the fraction of differing pixels is at most `--max-frac`, default 0). Implement
     the comparison in C++ in the replay (read both BMPs; no Python at run time), with the same definition as
     imgdiff.py so numbers agree.
   - `--a NAME --b NAME` replays into two backends at once and compares their captures per frame the same way.
     `--first-diff` then bisects the first failing frame: replays that frame's prefix of N draws into both (the frame's
     records up to and including its Nth Draw, then present as above) and finds the smallest N at which the pictures
     differ, printing that draw's index in the frame and its state (primitive, vertex count, target, texture address
     and format, blend, alpha test, stencil, clear mode). Replaying a prefix means replaying the file from its Begin
     to that point each time (memory state must be rebuilt), so expect log2(draws) full replays of the frame.
   - Output per frame: `[replay] frame N: D draws, R records, X ms` and, when comparing, `diff F (tol T) PASS|FAIL`;
     at the end a summary line and the exit code: 0 when every compared frame passed (or nothing was compared), 1
     otherwise, 2 for a bad file or an unusable backend. `--quiet` keeps only the summary and failures.
3. `tools/gerec/replay_check.sh`: records the race frames when `out/gerec/race.gerec` is missing (the command from
   task 021's Result: `main_menu.txt` + `single_race.txt` on an empty stick, `PURE_GE_BACKEND=record
   PURE_GE_RECORD=out/gerec/race.gerec PURE_GE_RECORD_AT=6014 PURE_GE_RECORD_FRAMES=3`, through `tools/run_boot.py`
   as `tools/frame_regress.sh` runs its race scene), then replays it into `vulkan` with `--compare`, then into `null`
   with `--out out/gerec/null` (which must write three black frames and exit 0). Also records
   `out/gerec/frontend.gerec` (`frontend.txt`, `AT=690 FRAMES=2`) and `out/gerec/title.gerec` (`AT=1750 FRAMES=2`)
   for task 023 when they are missing.
4. `docs/ge-backend.md`: section 7, "ge_replay": the command, what the replay guarantees (order, memory, words), what
   it cannot replay (anything the shell did outside the backend), the numbers from the Verify run (ms a frame per
   backend). `README.md`: a Layout row for `src/host/pure_main.cpp`, `src/tools/ge_replay.cpp`, `tools/gerec/`.

## Acceptance criteria
- [ ] `tools/run_boot.py --frames 300 out/022/boot.log` behaves as before (the game boots; the entry point change is
      invisible).
- [ ] The race recording replayed into `vulkan` with `--compare --tol 0 --max-frac 0` passes all three frames (the
      images were recorded from the Vulkan backend, so an exact match is expected; if a frame cannot be exact, say
      which pixels differ and why in Result, and the acceptance is `--tol 4 --max-frac 0.001`).
- [ ] The same recording replayed into `null` writes `out/gerec/null/frame_6014.bmp` to `frame_6016.bmp` and exits 0.
- [ ] `--a vulkan --b null --first-diff` on the race recording reports frame 6014 failing and names draw 1 (the first
      draw differs, since null draws nothing) with its state.

## Verify
`tools/build.sh profile && tools/gerec/replay_check.sh`

## May touch
- CMakeLists.txt (the `portablekit_add_game` call only: `HOST_MAIN_NAME`, `SOURCES`), src/host/ (new), src/tools/
  (new), tools/gerec/replay_check.sh (new), docs/ge-backend.md (a new section 7 only), README.md

## Must not touch
- vendor/, patches/, src/profile/, src/hle/, tools/run_boot.py, tools/imgdiff.py, tools/frame_regress.sh,
  tools/campaign_sweep.py, config/, tools/gerec/gerec_dump.py

## Estimated turns
60

## Escalate when
The Vulkan backend cannot be made outside the game's `ensure_backend` (report what the renderer needs that the replay
cannot give it), or a replayed Vulkan frame differs from its recorded image in a way the records cannot explain
(report the first differing draw from `--first-diff` against a second Vulkan replay, and the Memory records around
it). Do not change the record backend or the format (vendor); if the recording lacks something the replay needs,
report what and stop with PARTIAL.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

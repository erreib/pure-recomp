# 022: ge_replay: feed a .gerec recording to any GE backend and compare the pictures

Milestone: M6 | Branch: task/022-ge-replay | Status: MERGED 2026-10-06 (eabdacc)

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
Status: PARTIAL. All four deliverables are done, the Verify line passes, and acceptance criteria 1, 3 and 4 hold as
written. Criterion 2 holds only on a recording with warm-up frames. The race recording the brief names (AT=6014
FRAMES=3) misses criterion 2 on its first frame, even at the fallback `--tol 4 --max-frac 0.001`. The reason is that
the recording lacks something the replay needs: the pixels the bloom targets held before frame 6014. Those pixels
exist only on the GPU, and the format cannot carry them. The brief says to report this and stop with PARTIAL, so I did
not change the format or the record backend. Instead, `replay_check.sh` makes a second race recording,
`race_warm.gerec` (AT=6008 FRAMES=9). On it, frames 6014-6016 pass at tol 4, and also at tol 1.

Changed:
- `src/host/pure_main.cpp` (new): our `main()`. `--replay` goes to the replay; everything else goes to
  `portablekit_main`.
- `src/tools/ge_replay.hpp`, `src/tools/ge_replay.cpp` (new, about 1000 lines): the replay, the BMP reader and the
  comparison (imgdiff.py's rule), `--a`/`--b`, `--first-diff`, `--frames`, `--quiet`.
- `CMakeLists.txt`: `HOST_MAIN_NAME portablekit_main`, and the two new sources in `SOURCES`. Only the
  `portablekit_add_game` call changed.
- `tools/gerec/replay_check.sh` (new).
- `docs/ge-backend.md`: new section 7.
- `README.md`: Layout rows for `src/host/pure_main.cpp`, `src/tools/ge_replay.cpp` and `tools/gerec/replay_check.sh`.
- This file.
- Commits: `c59a6de`, then the Result commit.

Results:
- Criterion 1, boot: `tools/run_boot.py --frames 300 out/022/boot.log` gives exit 0 after 15.9 s, `[pure] exit at
  frame 300`, 588993 functions. `PureNative --help` prints the framework's usage, as before.
- Criterion 3, null: `--backend null --out out/gerec/null` writes `frame_6014.bmp` to `frame_6016.bmp`. All three are
  black at 480x272, and the exit code is 0.
- Criterion 4, `--a vulkan --b null --first-diff --frames 6014`:
  - Frame 6014 fails with diff 1.000000.
  - The search takes 10 steps of about 50 ms each and names `draw 1 of 906 (record 8 in gerec_dump.py's listing)`.
  - That draw is a sprite with 2 vertices, through mode, into target 0x04088000 (8888, stride 512).
  - Its state: clear mode, flags 7 (colour, alpha/stencil and depth all on); texture 0x08E5DAA0 clut4, swizzled;
    blend on, 2/3; alpha test off; stencil off. It clears the back buffer to white (vertex colour 0x04FFFFFF).
  - The exit code is 1.
- Criterion 2, Vulkan against the recorded images. Which pixels differ, and why:
  - On `race.gerec`, at tol 0:
    - frame 6014: 19058 px (0.036493), up to 16 levels;
    - frame 6015: 13297 px (0.025461), up to 3 levels;
    - frame 6016: 1021 px (0.001955), up to 1 level.
  - At tol 4, frame 6014 still has 1.97% of its pixels over (FAIL), while 6015 and 6016 have 0 (PASS).
  - Every differing pixel lies in 960x544 rows 521-540 (PSP rows 260-270), across the whole width.
  - The cause is the bloom chain. Draws #868-#873 blur additively into the bloom targets 0x04110000 and 0x04132000.
    The blurs reach beyond what the frame clears: the clears (#869, #871) cover 240x136, and the blurs draw to x 245
    and y 141. So the bottom rows of the bloom carry pixels from frame to frame.
  - In the game those rows hold thousands of frames of history. A replay starts with no targets, and a new Vulkan
    target is undefined until it is drawn.
  - The evidence:
    - `--a vulkan --b vulkan` gives identical pictures, and they are identical to a single replay.
    - A recording that starts at 6008 shows the same decay from its own first frame: 19160, 13627, 1186, 32 px. After
      that, 14 to 23 px stay 1 level off: rounding fixed points that depend on where the accumulation started.
    - `frontend.gerec` and `title.gerec` replay exactly at tol 0 from a cold start.
    - My C++ numbers equal imgdiff.py's on the same files (0.036493, 0.025461, 0.001955).
  - So no draw is replayed wrong, and `--first-diff` against a second Vulkan replay has no difference to bisect.

Verify output (`tools/verify_task.sh 022`, exit 0, from an empty `out/gerec`, so all four recordings were made; last
20 lines):
```
  blend on: source 2 destination 3 equation 0, fixed 0x000000/0x000000
  alpha test off: function 1 reference 0x00 mask 0xFF
  stencil off: function 1 reference 0xFF mask 0xFF, ops fail 0 depth fail 0 pass 0
  clear mode on: flags 7 (colour on, alpha/stencil on, depth on)
  depth test on function 6, write on, write masks colour 0x000000 alpha 0x00

== 5. frontend.gerec into vulkan, against the recorded images
[replay] out/gerec/frontend.gerec: frames 690-691 recorded from vulkan (format 1, 98 records), replayed into vulkan at 2x
[replay] frame 690: 11 draws, 51 records, 27.2 ms, diff 0.000000 (tol 0, 0/522240 px at 960x544) PASS
[replay] frame 691: 11 draws, 43 records, 5.1 ms, diff 0.000000 (tol 0, 0/522240 px at 960x544) PASS
[replay] summary: 2 frames replayed into vulkan (16.1 ms a frame), 2 compared, 2 passed, worst diff 0.000000 (frame 690); exit 0

== 5. title.gerec into vulkan, against the recorded images
[replay] out/gerec/title.gerec: frames 1750-1751 recorded from vulkan (format 1, 175 records), replayed into vulkan at 2x
[replay] frame 1750: 28 draws, 94 records, 26.1 ms, diff 0.000000 (tol 0, 0/522240 px at 960x544) PASS
[replay] frame 1751: 28 draws, 77 records, 5.0 ms, diff 0.000000 (tol 0, 0/522240 px at 960x544) PASS
[replay] summary: 2 frames replayed into vulkan (15.5 ms a frame), 2 compared, 2 passed, worst diff 0.000000 (frame 1750); exit 0

replay_check: PASS (480 s)
verify 022: PASS
```
Earlier in the same run:
- Recording times: race 197 s, race_warm 197 s, frontend 24 s, title 59 s.
- Every recording passed `gerec_dump --summary`. The race draw counts are 906/905/906, as in task 021.
- Cold race replay: as in criterion 2 above.
- `race_warm` frames 6014-6016 at tol 4: 0 px, PASS.
- null: three black frames.
- Time a frame: Vulkan 47 ms for the first frame (it makes the targets and pipelines), then 5.5 to 13 ms; null 0.6 to
  2.2 ms.

Open questions:
1. Exact replays from a recording's first frame would need the format to carry target contents. One way is a record,
   at Begin, of each live target's colour, depth and stencil at the internal scale, read back by the inner backend.
   Each backend would then need a way to seed a target from those pixels. That is a vendor change (format version 2
   and a `GeBackend` method), so I left it for a decision. Until then:
   - Compare a backend with its own recording only after warm-up frames (`race_warm.gerec`).
   - Or compare two backends with each other through `--a`/`--b`, which start equally empty. That covers 024's Metal
     against Vulkan.
2. `race_warm.gerec` is 63.6 MB, with six warm-up frames. By the measured decay, three would do (AT=6011: 32 px at 1
   level by its fourth frame) and would save about 40 MB. I did not record that variant, so the script keeps the one I
   measured.
3. The brief says to resize both pictures to 480x272 "as imgdiff.py does". imgdiff.py actually resizes only when the
   sizes differ. I followed imgdiff.py, so the numbers agree with it. Vulkan against its own 960x544 images is
   therefore compared at 960x544, and Vulkan against null at 480x272.
4. A Vulkan replay saves the shell's pipeline cache to the user data directory, as the game does, because it is the
   same renderer. If replays should leave the player's files alone, `PURE_DATA_DIR` could point them elsewhere.
5. `replay_check.sh` makes all four recordings first, then runs the replays. The brief listed the frontend and title
   recordings last; only the order differs.

## Review
Verify rerun: PASS from the main checkout, 2026-10-06 (`tools/verify_task.sh 022`, 283 s with `race.gerec` already
present): cold `race.gerec` into vulkan 0.0365 / 0.0255 / 0.0020 at tol 0 (reported, the bloom rows' history);
`race_warm.gerec` frames 6014-6016 into vulkan 0.000000 x3 PASS; null writes three black frames; `--a vulkan --b null
--first-diff` bisects frame 6014 to draw 1 in ten steps; frontend and title recordings replay exactly at tol 0.
Spot-read: `src/host/pure_main.cpp` (dispatch only), the CMake change (`HOST_MAIN_NAME`, two sources), `Lane::open`
(the Vulkan shell made as `ensure_backend` does, the recording's internal scale applied), `apply` (Memory and Words
written before the call; a Transfer's rows copied after the backend's read-back, deferred to the next non-Memory
record, as the HLE orders it), `Lane::flip` (present_image, the shell's present, capture, begin_frame).
Merged: eabdacc into batch/m2 (docs/ge-backend.md: section 7 placed before section 8 by hand).
Notes: PARTIAL accepted as done. The miss on criterion 2 is the recording's, not the replay's: a .gerec starts with
empty targets and the bloom targets carry rows from earlier frames, so a backend against its own recording is exact
only after warm-up frames (`race_warm.gerec`, six of them; three would do). The tool's purpose, backend against
backend, starts both lanes equally empty and is unaffected. Seeding targets from a Begin record (format version 2 and
a `GeBackend` method) is deferred until a Metal-against-PPSSPP comparison needs an exact cold start; recorded here.

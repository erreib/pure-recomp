# 033: Frame-time dips in play: a per-frame trace with the cause of each long frame, and pipeline pre-warming

Milestone: M7 (polish) | Branch: task/033-frame-time-dips | Status: OPEN (dispatch after task 032's cells are done)

## Goal
Erik's first race on the app had frame-rate dips "here and there", while the scripted race holds 59.7 to 60.1 fps
over its one-second `[perf]` lines. One-second averages hide single long frames. This task gives the Metal path a
per-frame trace that names what each long frame spent its time on, measures a race with weapons in use, and removes
the causes that can be removed ahead of time: render pipelines compiled on first use, and anything else the trace
shows. Faithful dips of the original (the PSP dropped frames in tunnels at 222 MHz) are not the target: the port
runs the game's code in a fraction of a frame, so a long frame here is the host's.

## Read first
- CLAUDE.md, docs/status.md (Follow-ups: the frame-rate row), docs/metal-backend.md (the pipeline key and its two
  caches, the texture cache, `commit` and the in-flight ring, the stencil copy, the depth write-back's wait, the
  stats the backend prints), docs/ge-backend.md 8.5 (the shell's present), docs/timing.md (the game's own frame
  limiter: Single Race free-runs at 60)
- src/gpu/metal_backend.mm (`render_pipeline`, `depth_state`, `decoded_texture`, `resolve_stencil_alpha`,
  `store_depth`, `commit`, `present_image`, `Stats`), src/host/metal_shell.mm (`draw`, the wait for the previous
  present, vsync), src/gpu/metal_device.mm
- vendor/portablekit/host/perf/frame_stats.hpp and .cpp (`PURE_PERF=log`: what the framework measures per second and
  where `add_render_time`/`end_frame` are called), host/hle/hle_media.cpp `present_frame`
- tools/campaign_sweep.py (the Vineta K follower uses pickups: `pad b` is "use pickup"; a sweep cell is the
  workload), tools/measure_fps.py if present, tools/hud_check.sh (a race route run with shots)

## Deliverable
1. `PURE_METAL_TRACE=<file>`: one line per flip from the backend, CSV: flip number, wall time of the flip, CPU
   milliseconds spent in `submit` for the frame, milliseconds waited for the GPU (and where: SIGNAL depth read,
   capture, in-flight ring, stencil copy), the number of render pipelines and depth-stencil states created this
   frame, textures decoded this frame (count and bytes), stencil copies, draws, and the shell's time from
   `present_image` to the drawable's present when the shell is the Metal one (a column the shell fills through a
   small hook in `metal_device.hpp`, or a second file `PURE_METAL_SHELL_TRACE` if a hook is awkward; say which).
   Off by default; no cost when off beyond the counters that exist.
2. `tools/frame_times.py TRACE [--long MS] [--fps N]`: a summary (frames, mean and 99th percentile frame time, the
   count over `--long`, default 20 ms, and the longest ten with their columns), a histogram of frame times, and
   for the long frames which column dominates. Also `--plot OUT.png` through tools/png.py if cheap (optional).
3. The measurement: the Vineta K Single Race cell (`tools/campaign_sweep.py single_race vineta_k --no-damage
   --env PURE_METAL_TRACE=out/033/race.csv`, three laps with pickups used) under the Metal shell, and the same
   under the Vulkan shell and backend for comparison (`--env PURE_SHELL=vulkan --env PURE_GE_BACKEND=vulkan`, which
   has no trace: `PURE_PERF=log` only). Report the long-frame count and causes before any change.
4. Pipeline pre-warming: at `initialize`, create the render pipelines and depth-stencil states for the keys a
   reference run used, from a list the backend can write (`PURE_METAL_PIPELINES_OUT=<file>` at shutdown: every key
   seen, as text) and read (`config/metal_pipelines.txt`, committed, made from a frontend-plus-race run with
   weapons); a key not in the list is still made on first use. Measure the pre-warm's cost at start (milliseconds)
   and the long-frame count after it.
5. Whatever else the trace shows as a repeated cause and can be fixed inside the backend or the shell without
   changing what is drawn (a decode that could be cached by address before its content hash, a wait that can be
   deferred a frame, a copy that can be skipped): fix it, show the before and after, and leave what changes the
   picture alone (report it instead). `tools/frame_regress.sh` and `tools/hud_check.sh` must stay as they are.
6. docs/metal-backend.md: a "Frame times" section with the method, the before and after tables, the pre-warm list
   and how to refresh it; README.md: the switches and the tool.

## Acceptance criteria
- [ ] The trace and the tool exist; the Vineta K cell's trace under the Metal shell is summarised in Result, before
      and after.
- [ ] After the changes, the race's frames beyond the first 10 seconds have no frame over 25 ms caused by pipeline
      creation, and the count of frames over 20 ms is reported with each remaining cause named.
- [ ] `tools/frame_regress.sh` 5/5 at the Metal column, `tools/hud_check.sh` 61 of 61, and `tools/frame_regress.sh
      --shell vulkan --backend vulkan` 5/5 unchanged.
- [ ] The pre-warm adds under 300 ms to start-up (measured), or is made asynchronous.

## Verify
`tools/build.sh profile && PURE_METAL_TRACE=out/033/race.csv python3 tools/campaign_sweep.py single_race vineta_k --no-damage && python3 tools/frame_times.py out/033/race.csv --long 20 --fps 60 --check-no-pipeline-stalls-after 600 && tools/frame_regress.sh --only race_hud`

(`--check-no-pipeline-stalls-after N` exits 1 when a frame after flip N exceeds 25 ms with a pipeline created in it.)

## May touch
- src/gpu/metal_backend.mm, src/gpu/metal_device.hpp and .mm, src/host/metal_shell.mm, config/metal_pipelines.txt
  (new), tools/frame_times.py (new), docs/metal-backend.md, README.md

## Must not touch
- vendor/, patches/, src/gpu/metal_shaders.h (unless a function constant is needed for pre-warming: say so),
  src/profile/, src/hle/, src/tools/, tools/campaign_sweep.py, tools/frame_regress.sh, tools/hud_check.*, ref/

## Estimated turns
60

## Escalate when
The long frames come from outside the backend and the shell (the HLE, the kernel's pacing, the audio thread: report
the trace columns that show it and stop), or a fix would change what is drawn (report it as a follow-up).

## Result

Status: PARTIAL. Deliverables 1 to 6 are in and every acceptance criterion holds (below). PARTIAL for two things only the
reviewer can settle: (1) the brief's escalation condition occurred: most of the race's remaining long frames are the
game's own 30 fps stretches, outside the backend and the shell (the columns that show it are below; not pursued, no
HLE or kernel change); (2) the Verify line as written cannot run: `tools/campaign_sweep.py` has no `--env` (task 034's
argument list) and is under "Must not touch", so `tools/verify_task.sh 033` exits 2 at argparse. The same line with
`PURE_METAL_TRACE` in the environment (the sweep passes its environment to the game) passes; the brief's Verify could
read `... && PURE_METAL_TRACE=out/033/race.csv python3 tools/campaign_sweep.py single_race vineta_k --no-damage && ...`.

Changed (branch `task/033-frame-time-dips`, rebased on `batch/m2` 752088d, 8 commits):
- `src/gpu/metal_backend.mm`: `PURE_METAL_TRACE=FILE`, a CSV row per flip (frame time; CPU in submit, of it pipeline
  creation and texture hashing/decoding; present and guest-memory calls; GPU waits by where: SIGNAL depth read, frame
  write-back, guest read-backs, captures and hand-over, in-flight ring; pipelines, depth-stencil states and textures
  made with bytes; stencil copies, draws, passes, copies; the shell's columns; the rest as `other_ms`). The pre-warm:
  `config/metal_pipelines.txt` read at `initialize` (depth-stencil states made at once, render pipelines with
  `newRenderPipelineStateWithDescriptor:completionHandler:`; a draw waits only for one still compiling; an unlisted
  key is made on first use); `PURE_METAL_PIPELINES=FILE|0`; `PURE_METAL_PIPELINES_OUT=FILE` writes every key used at
  exit. Pipeline and depth-state creation moved into `pipeline_descriptor()`/`make_depth_state()` unchanged.
- `src/gpu/metal_device.hpp`, `.mm`: the hook (the brief's option, not a second file): `trace_flip`,
  `trace_shell_present`, `trace_presented`, `take_shell_presents`, `take_presented`; its state is never destroyed,
  since the backend's shutdown runs during exit after a later-made static is gone (a windowed run lost its key list so).
- `src/host/metal_shell.mm`: reports each present's CPU time, `nextDrawable` wait, window occlusion and the drawable's
  `presentedTime` to the trace; presents each game picture held to real time at the PSP vblank after the one its frame
  began from (`presentDrawable:atTime:` at the HLE's moment plus 1001/60000 s); `PURE_METAL_PACE=0` presents at once.
- `config/metal_pipelines.txt` (new): 26 render pipelines, 28 depth-stencil states, from a headless and a windowed
  run of the cell, merged.
- `tools/frame_times.py` (new): summary, histograms, longest frames, causes, `--from/--to`, `--plot` (tools/png.py),
  `--check-no-pipeline-stalls-after N` (a render pipeline made in a frame over 25 ms, or 5 ms of pipeline work; a
  depth-stencil state alone does not count: microseconds, and one landing in a two-vblank frame is not its cause).
- `docs/metal-backend.md` ("Frame times": trace, method, runs, causes, the stretches, changes, after, the pre-warm list
  and its refresh, not changed, the Vulkan path; switch and file rows; the shell's Present row), `README.md` (the four
  switches, the tool). `src/gpu/metal_shaders.h` untouched (no function constant needed).

Verify output. As written (`tools/verify_task.sh 033`, last lines):
```
campaign_sweep.py: error: unrecognized arguments: --env PURE_METAL_TRACE=out/033/race.csv
verify 033: FAIL (exit 2)
```
With the trace in the environment (same steps, run as `verify_task.sh` runs them), last 20 lines:
```
  outside              140  excess mean  14.32 ms  flips 125, 5704, 5705, 6251, 6790, 6794, 6795, 6798, 6905, 7340, 7445, 7452, ...
  draws                 19  excess mean  10.98 ms  flips 6796, 6801, 7341, 7342, 7353, 9155, 10967, 12095, 12758, 12770, 13957, 13990, ...
  wait depth             7  excess mean  16.95 ms  flips 8554, 10383, 10384, 10968, 14298, 14962, 16359
  backend                2  excess mean   8.77 ms  flips 6797, 17490
  wait frame             1  excess mean  43.16 ms  flips 4
  texture                1  excess mean   5.62 ms  flips 6792
  with a render pipeline or depth-stencil state made: 0

check: PASS: no frame after flip 600 over 25 ms with a pipeline made in it (17040 frames checked)
frame regression 2026-10-06 18:00, commit 5b48bb1+changes, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a969cf4a254064338/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0374   0.10   32    0.0379 -0.0005  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 5s)
verify 033: PASS
```
(The headless cell passed at flip 17640, three laps; its race window 6250-17330: 11081 frames, 162 over 20 ms: 90 in
four two-vblank stretches, 64 host contention, 7 SIGNAL depth waits, 1 other; no pipeline made.)

Measurements (Vineta K Single Race cell, `--no-damage`, follower pressing Square every 120 flips; race window flip 6250
to 300 flips before the results screen; M4 Pro, built-in display at 120 Hz; the machine busy with other work):

| Run | Shell, window | Shader cache | Pre-warm | Pictures | Frames | Over 20 ms | Over 25 ms | 99th pct | Pipelines made in the race |
|---|---|---|---|---|---|---|---|---|---|
| A before | Metal, occluded from flip 7185 | warm | off | at once | 10821 | 236 | 227 | 33.4 ms | 0 (4 depth states) |
| B before | headless | warm | off | | 10861 | 244 | 188 | 33.3 ms | 0 (4) |
| C before | Metal, never shown | cold | off | at once | 11361 | 124 | 119 | 31.0 ms | 0 (4) |
| D after | Metal, occluded from 7769 | cold | on | at once | 11741 | 113 | 106 | 19.6 ms | 0 |
| E after | Metal, shown | warm | on | at once | 10641 | 61 | 52 | 18.6 ms | 0 |
| F after | Metal, shown | warm | on | at the PSP vblank | 11061 | 73 | 72 | 18.9 ms | 0 |
| Vulkan | Vulkan shell and backend (`[slow-frame]` at 20 ms) | | | | 6250-17540 | 61 | | | |

Long frames by cause (over 20 ms):

| Cause | A | B | C | D | E | F | Columns that show it |
|---|---|---|---|---|---|---|---|
| the game's two-vblank stretches | 211 in 11 | 116 in 8 | 108 in 6 | 94 in 3 | 48 in 2 | 71 in 3 | runs of mostly 13 to 39 frames of 31 to 35 ms; `other_ms` 28 to 32, every backend and shell column at its median; `[perf]` "game" 35 to 49 fps at speed 100% |
| host contention | 14 | 125 | 10 | 13 | 9 | 2 | `other_ms` or `submit_ms` grown with no more draws, `texture_ms` up to 34 ms with nothing decoded |
| SIGNAL depth wait | 7 | 3 | 6 | 4 | 4 | 0 | `wait_depth_ms` 13 to 40 (median 0.6) |
| window occluded | 4 | 0 | 0 | 2 | 0 | 0 | `drawable_ms` 104 to 973 |
| pipeline creation | 0 | 0 | 0 | 0 | 0 | 0 | |

Pipeline creation: no render pipeline was made inside any race. On a cold shader cache (a machine's first run, as
Erik's first race; made with a throwaway build that gave the shader source an unused varying with a per-run number,
not committed) they came before it: C's race load (flip 5708) took 134.7 ms making 18 pipelines (122.9 ms), flip 5745
27.6 ms making 3, boot flips 3 and 5 about 26 ms; with the pre-warm (D) 15.0, 7.2 and 10.1 ms, flip 3 waiting 11 ms
for the pre-warm's first pipeline. `--check-no-pipeline-stalls-after 600` fails on C (5708, 5745) and passes on every
run with the pre-warm. The pre-warm's cost at start: 0.85 ms (cold) and 2.1 to 2.6 ms (warm) on the calling thread;
all 26 pipelines were made 46 to 73 ms later on a cold cache, 2.6 ms on a warm one, by flip 4 at the latest.

On screen (presented times, window shown): E showed 476 pictures for 25 ms and 470 for 8.3 ms out of 10641, in pairs
through most of the race (flip intervals 16.68 ms, standard deviation 1.4 ms, against a 120 Hz refresh): a stutter
the flip times hide. Presenting at the PSP vblank (F): 47 and 28 of 11059, 98.6% of pictures shown 16.7 ms, latency
from present to screen 21.5 to 27.0 ms mean, `nextDrawable` never waiting. A minimum present duration of two refreshes
was tried first: 19 and 0, but 34.0 ms mean latency and `nextDrawable` holding the game 4 to 22 ms in 1217 frames; not
kept.

The two-vblank stretches (the escalation): a headless run with `PURE_TRACE_PACING` beside the trace shows the main
thread in ordinary race frames calling no vblank wait (the pad read paces it) and, through the stretch at flips
9261-9276, calling `sceDisplayWaitVblankStart` twice a frame: the end-of-frame routine's locked path (docs/timing.md
step 5, `+0x116c` 0 or the countdown at `+0x117c`). The stretches recur at about the same flips across runs (7082-7105
in D and E; 16252-16290 in D, 16259-16283 in F), on the Vulkan path too (12510-12527, 14494-14516), so something in the
race sets the lock. 2 to 11 stretches a race, 0.4 to 1.3 s each at 30 fps: likely the "dips here and there" Erik saw,
with the 120 Hz judder.

Acceptance:
- the trace and the tool exist; the cell's Metal-shell trace is summarised above, before (A, C) and after (D, E, F).
- no frame after flip 600 over 25 ms with a pipeline made in it (`--check-no-pipeline-stalls-after 600` PASS on D, E,
  F and the Verify run; FAIL on C before the pre-warm); the frames over 20 ms are counted with their causes above.
- `tools/frame_regress.sh --shell metal --backend metal`: 5/5 (lang 0.0002, title 0.0002, profile 0.0002 (the blinking
  cursor after LOAD, as task 027 noted), main_menu 0.0106, race_hud 0.0374), 7m 8s; headless default: 5/5 (0.0002,
  0.0002, 0.0000, 0.0106, 0.0374), 10 s; `--shell vulkan --backend vulkan`: 5/5 unchanged (0.0544, 0.0302, 0.0543,
  0.0331, 0.0672), 7m 7s; `tools/hud_check.sh`: 61 of 61 shots have the HUD (Metal shell, 226 s).
- the pre-warm adds 0.85 to 2.6 ms to start-up on the calling thread and is asynchronous.

Open questions:
1. The two-vblank stretches (escalated, outside this task's area): what sets the frame object's lock during the race,
   and whether the PSP drops to 30 fps at the same places (PPSSPP at the same track position, a watch on `+0x116c` and
   `+0x117c`). If the game sets it from a timing it measures, the HLE's answer is the place to look.
2. The Verify line: the sweep takes no `--env`; the environment form above is the one that runs.
3. The app: `tools/bundle.sh` does not copy `config/metal_pipelines.txt` into `Contents/Resources`, where the backend
   looks; until it does, the app makes pipelines on first use (only its first race after an install pays, about 135 ms
   at the race load on a cold cache).
4. The vblank-timed present adds 5.5 ms of latency on average for the even pictures; `PURE_METAL_PACE=0` turns it off.
   Erik may want to judge it by playing; it applies only while the game is held to real time with vsync on.
5. The pipeline list covers the Vineta K cell only; other tracks, Zone and weapons the follower never fired may add
   keys (the exit line counts "not in the list"; the refresh is in docs/metal-backend.md "The pre-warm list").
6. The SIGNAL depth write-back's GPU wait spikes to 13 to 40 ms a few times a race; reading it a frame late would move
   the lens flare's occlusion, so it is left. The measurements ran on a busy machine with the window sometimes
   occluded; runs E and F (window shown) are the player's view.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

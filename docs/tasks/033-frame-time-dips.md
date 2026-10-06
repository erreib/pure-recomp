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
`tools/build.sh profile && python3 tools/campaign_sweep.py single_race vineta_k --no-damage --env PURE_METAL_TRACE=out/033/race.csv && python3 tools/frame_times.py out/033/race.csv --long 20 --fps 60 --check-no-pipeline-stalls-after 600 && tools/frame_regress.sh --only race_hud`

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

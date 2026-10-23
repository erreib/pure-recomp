# 505: The renderer's CPU work off the guest thread, measured first

Milestone: weak machines (GitHub issue 1) | Branch: task/505-render-thread from batch/m2 | Status: OPEN (the plan;
stage 1 is the brief below, stages 2 to 4 are briefed from its findings)

## Goal
GitHub issue 1 (2026-10-22, nicolasbeuzeboc): 0.2.0 at 1x on an i7-6600U (2016, two cores, 15 W) with Intel HD 520
runs "in slow motion, very low framerate with choppy sound". When the host cannot finish a frame in time the
kernel slows the game's clock rather than dropping frames, and the sound is made on that clock, so a machine short
of one frame's CPU gets exactly that picture. Everything runs on one thread: the recompiled game, the HLE, the
shell's per-flip work, the GE's display-list parse and the Vulkan renderer's recording. Erik (2026-10-22): plan to
take the renderer off the guest thread and ask the reporter to retest.

## What the rig measured (2026-10-22, the planning session)
`PURE_TRACE_RENDER=1 tools/stutter_check.sh --shell vulkan --out out/505/stutter` at 60 Hz (the window judged not on
screen, MAILBOX, so the stutter verdict is void; the per-frame CPU figures stand). Medians of the 203 paced seconds,
per game frame:

| Where | ms | Thread after stage 3 |
|---|---|---|
| guest: the recompiled game, the HLE, the shell's event pump and overlay | 5.2 | guest |
| GE list parse (state commands, the walk; `[render-split]` parse) | 2.05 | guest |
| vertex decode | 0.45 | guest |
| the backend's draw bookkeeping (`host`) | 1.27 | render |
| texture lookup and decode | 0.37 | render, the guest-memory read stays |
| Vulkan command recording | 0.25 | render |
| present (the composite and the queue present) | 0.31 | render |
| wait (vsync and the pacer: idle) | 7.0 | |
| GPU, RTX 3080 at 960x544 | 2.3 | |

So the guest thread spends 9.7 ms of an 8600K core on a 16.7 ms frame. A 15 W 2016 core at roughly 0.6 to 0.75 of
it would spend 13 to 16 ms, which is at the edge before any GPU wait; the HD 520 may be the limit by itself, which
only the reporter's numbers can say.

## Why not the PSP's own GE concurrency
The game's frame (docs/timing.md, "What the routine does, in order" and "Frame structure") builds one list,
enqueues it, and at the end of the same frame waits for it in `FUN_088eda8c` (`sceGeListSync`, then
`sceGeDrawSync`) before the swap. A GE thread that keeps the PSP's semantics, the list run asynchronously and the
syncs blocking, overlaps only the time between the kick and the sync, which this frame shape makes small. Letting
the sync return before the list is drawn would overlap the next frame's game work, but it is a guess about which
memory the game reuses, and PPSSPP dropped its threaded-GPU mode over hazards of that kind. Stage 1 measures the
window before anything is built on it.

What the guest never sees is the backend's work behind the parse: draw bookkeeping, texture decode and upload,
recording, submit and present. Moving that is the same program as today at every point the guest can observe,
provided every read of guest memory stays on the guest thread and every result the guest reads drains the queue
first.

## The plan
1. **Measure (this brief, the rig, no build change beyond traces).** The overlap window, the sync points and a
   CPU profile; below.
2. **Single-thread wins (a brief from stage 1's profile).** 2 ms of parse for about 460 draws is 4.4 us a draw;
   if the profile shows a per-draw cost such as the whole GE state copied into each `DrawCall`, it is cheaper to fix
   than to thread, helps the Mac too, and shrinks what stage 3 must carry.
3. **The render thread (a vendor patch, the main work).** A queue between the HLE's draw sink and the Vulkan
   backend: the guest thread parses and decodes as today and pushes owned work items (the draw's state, its
   decoded vertices, the texture's bytes or its hash when already resident); a render thread drains them into the
   existing recording and submit, and presents at the flip. Drained in full, in order, before: a block transfer
   from a drawn target, `read_back_framebuffer`, `write_back_depth` (the signal path in `run_ge_list`),
   `write_back_frame` (already a frame late with two frames in flight), a capture, a settings
   change that rebuilds the swapchain, the menu's own drawing, and shutdown. `<PREFIX>_RENDER_THREAD=0` keeps the
   one-thread path for comparison (AGENTS.md: an off switch). Expected: about 2.2 ms a frame off the guest thread
   on the rig (23%), more with stage 2's wins.
4. **The list walk off the thread (only if stage 1 finds a window).** If the game kicks parts of the list before
   the frame's sync (`sceGeListUpdateStallAddr` mid-frame), the parse can follow the stall address on the render
   thread while the game builds the rest; the syncs keep blocking.
5. **The retest.** A test build from batch/m2 (a GitHub pre-release, Erik's step), and the reporter's overlay
   numbers before and after.

The Metal backend (src/gpu/metal_*) has the same seam and the Mac has the headroom; it follows only if wanted.

## Stage 1: Read first
- vendor/portablekit/host/hle/hle_media.cpp: `run_ge_list` and `register_ge` (the list runs to its stall inside
  the enqueue and `sceGeListUpdateStallAddr` calls; the syncs do not wait).
- vendor/portablekit/host/gpu/ge_backend.hpp (the seam and its frame order) and vulkan_ge_backend.cpp.
- vendor/portablekit/host/perf/frame_stats.cpp, `[render-split]` and the `Split` and `Stall` kinds.
- docs/timing.md, "What the routine does, in order" and "Frame structure".

## Stage 1: Deliverable
A findings section appended here, with figures from a Single Race of Vineta K in the window (the stutter route, the
window shown) and, if the profiler allows, the same headless where the backend needs no window:
1. **The census, per game frame:** enqueues, `sceGeListUpdateStallAddr` calls, list syncs and draw syncs; block
   transfers, framebuffer read-backs, depth write-backs and their source (signal or transfer); signals and finish
   callbacks. `PURE_TRACE_SYNC` and `PURE_TRACE_GE` first; a counter in the profile's E6 wrap if they do not say.
2. **The window:** the guest time from each kick of the frame's list to the frame's `sceGeDrawSync`, median and
   90th percentile.
3. **The profile:** the top functions under parse and the backend's `host` time (a sampling profiler on the
   Release build with symbols: Visual Studio's, Windows Performance Recorder, or Very Sleepy), and what each costs a
   draw.
4. **A slow-core baseline (with Erik's yes, as it changes the power plan for the run):** the same race with the
   processor's maximum state capped near 50%, `powercfg` restored after; the guest, render and wait figures, and
   speed.
5. Stage 2's and stage 3's briefs, or a finding that changes the plan.

## Stage 1: May touch
docs/tasks/505-render-thread.md, out/505/ (never committed). A trace print under a `PURE_TRACE_*` switch through
`tools/patches.sh` only if the census cannot be read from the existing traces, reverted before the end unless
the findings say it should stay.

## Stage 1: Must not touch
`vendor/portablekit/include/psprecomp/`, the code generator, the kernel scheduler, `tools/regen.sh`, `main`.

## Stage 1: Verify
`tools/patches.sh check && python3 tools/docs_check.py`; the findings carry the commands that produced each figure.

## Stage 1: Escalate
The census shows the guest reading GE results that are not in the list above (a readback path the queue would
have to drain on and does not know of); or the profile puts most of parse in code under `include/psprecomp/`.

## A weak CPU on the rig (2026-10-22, Erik's run)
The race with the CPU pinned to two logical cores (`start /affinity 3`) and the power plan's maximum processor state
at 60% (turbo off, about 2.2 GHz), the RTX 3080 drawing, Display rate Original, `PURE_PERF=log PURE_TRACE_STALLS=1`
(`out/weak/run.log`). Erik: "pretty close to normal performance". Medians of 53 race seconds:

| | fps | speed | guest | render | wait | seconds under 95% |
|---|---|---|---|---|---|---|
| capped | 58.4 | 97% | 7.9 ms | 8.4 ms | 0.8 ms | 17 of 53 (88 to 94%) |
| uncapped (above) | 59.9 | 100% | 5.2 ms | 4.5 ms | 7.0 ms | |

A CPU at about half the rig's speed with two cores runs the race at 88 to 100%: just short of a frame, not ten
times short. So issue 1's sub-10 fps is not the CPU's cost; the suspect is the Intel GPU or its driver path, which
this run does not test (the rig's UHD 630 is off in the BIOS, and the renderer always picks a discrete GPU). Next
for the issue: the other PortableKit ports on the reporter's laptop, his stall log, and the rig's integrated GPU
enabled with a switch to choose it. The render thread stays worth doing for the machines this run imitates, where
3 to 4 ms a frame is the difference between 90% and 100%, but it is not issue 1's fix.

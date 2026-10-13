# 078: The race's effect slowdowns on the Vulkan renderer

Milestone: Windows fidelity (Erik, 2026-10-12: still not on par with the Metal build; the slowdowns cluster where
the screen fills with effects) | Branch: task/078-vulkan-effect-slowdowns | Status: MERGED (bef8bda, 2026-10-12)

## Goal
Task 077 removed the depth-readback drain and the race now passes `tools/stutter_check.sh` (8 of 222 seconds over
25 ms), but Erik still feels slowdowns in play, worst with many effects on screen, and the probes agree. Two
measured classes remain, and after this task each is either fixed on the rig or explained in the Result with its
measurement:

**A. Guest-time clusters at effect-heavy moments.** Frames of 26 to 91 ms of *guest* time (the emulated game, not
the renderer) in clusters around contact explosions: flips 14715/14718, 16842/16847 in out/078-probe on the rig,
9009 to 9014 and 15878 to 15891 in the run before (out/stutter_check/vulkan-vulkan). The Mac's gates measured a
race at 60 fps with 0 frames over 25 ms (tasks 073 and 075), so this is not the game's own cost on every machine.

**B. Deterministic first-use present hitches.** Three a race, 100 to 160 ms each, at the same flips run after run
(7023, 7623 or 10863, 10533 or 11463): `PURE_TRACE_RENDER`'s split puts the whole spike in `present` (0.14 to 0.17
ms a frame baseline; 1.98 to 3.19 averaged in the spike seconds), i.e. one `vkQueueSubmit`/`vkQueuePresentKHR`
call stalls. The renderer's pipeline prewarm (`prewarm_pipelines`, pipeline_keys.bin) already made the pipelines —
creation is not the stall. The cost is first *use*: the NVIDIA driver's late work on a pipeline's first execution,
or patch 0018's 1x effect targets created lazily at an effect's first draw, or a first big VRAM
allocation/residency. The Mac session independently suggested a Vulkan pre-warm matching the Metal one; the right
shape depends on which of those it is.

Characterize each class first, as task 077 did (its premise was wrong and the characterization caught it): commit
the finding before designing.

## Read first
- CLAUDE.md, docs/tasks/077-vulkan-readback-stutter.md (the whole file: the probe method, the Result, the Review:
  stutter_check judges frames on involuntary time), docs/status.md (the 077 row; E3/E4/E5 rows), docs/windows.md
  ("Updating the rig": the 2026-10-12 findings), patches/README.md (0018-vulkan-effects-at-1x,
  0022-vulkan-async-readback as models), docs/upstream.md
- The probe logs on this rig: out/078-probe/single_race-vineta_k.log (PURE_TRACE_RENDER on; the spike flips above),
  out/stutter_check/vulkan-vulkan/race/single_race-vineta_k.log (the run before; same spikes, other flips for A)
- vendor/portablekit/host/perf/frame_stats.hpp (the Split kinds, `PURE_TRACE_RENDER`, `PURE_TRACE_STALLS`,
  `PURE_TRACE_STALLS_MS`; what `guest` covers in a `[slow-frame]` line — read the .cpp's accounting before
  trusting any attribution)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `prewarm_pipelines` and the Prewarm struct (what the existing
  prewarm covers and what it cannot), the present/submit path (where the 100 to 160 ms sits), the 1x effect
  targets of patch 0018 (when they are created; `[render] target` lines if any), texture upload and `Stall::Upload`
- src/profile/ the E6 smooth-flashes wrap (a `sceGeDrawSync` wrap runs every list sync; effects multiply list
  syncs — a candidate for A), src/profile/pure_profile.cpp
- README.md's switches table: `PURE_TRACE_SYNC`, `PURE_TRACE_GE`, `PURE_TRACE_CALLS`, `PSPRECOMP_NO_INTERPRETER`,
  `PSPRECOMP_INTERPRETER_WATCH`, `PURE_NO_PIPELINE_PREWARM` — the instruments for A and B
- tools/stutter_check.sh (the gate; its bounds stay), tools/campaign_sweep.py, tools/patches.sh,
  docs/verification.md

## Deliverable
Characterizations first (committed), then the smallest fixes that hold. Vendor changes as patch
`0022-vulkan-first-use-warm` (or a truer slug) through `tools/patches.sh export`; a fix in src/profile/ is repo
code and needs no patch. Commits per proven stage.
- **A characterized:** one probe run instrumented to attribute the guest spikes — candidates in order of cheapness:
  the E6 wrap's cost per list sync (count syncs in a spike frame vs a calm one, `PURE_TRACE_SYNC`); an interpreter
  fallback on an effect-only path (`PSPRECOMP_NO_INTERPRETER=1` for one run: a halt names the function;
  `PSPRECOMP_INTERPRETER_WATCH` to confirm); guest-attributed texture/CLUT work. Commit what you find, then fix it
  if it is ours (the wrap, a decode on the wrong thread), or report it with numbers if it is the game's own work
  that the Mac absorbs differently (say how the Mac absorbs it, if you can see it from the code).
- **B characterized:** bracket the present/submit with its own timer for one run (the patch may carry a small
  `[render] present over N ms` line behind `PURE_TRACE_STALLS`) and log the 1x effect targets' creation flips; one
  run with `PURE_NO_PIPELINE_PREWARM=1` and one with the NVIDIA shader cache cleared
  (`%LOCALAPPDATA%\NVIDIA\DXCache`, say what you did) to see what moves the spikes. Commit the finding.
- **B fixed by warming what actually stalls**, per the finding: eager 1x effect targets at race load; or a warm
  pass that *executes* each prewarmed pipeline once into an offscreen target at startup (the prewarm thread's
  pipelines drawn, not just made), bounded in time and behind the existing `PURE_NO_PIPELINE_PREWARM`; or what the
  finding names instead. The spikes at the named flips must be gone (under 25 ms involuntary) in two consecutive
  probe runs.
- **The gate**: `tools/stutter_check.sh` stays as is and PASSes; its Result figures land in the task file. If both
  classes are fixed, say in the Result what the new worst second is, so the Mac session can judge tightening the
  bound later. Do not tighten it yourself.
- **Docs**: patches/README.md rows (upstream column), docs/windows.md (one line in the 2026-10-12 findings
  paragraph naming what the effects slowdown was), docs/verification.md if a new trace switch is added, README.md
  for any new switch. `python3 tools/docs_check.py` and `tools/patches.sh check` pass.

## Acceptance criteria
- [ ] A's characterization committed with numbers (which call, how many per spike frame, ms each); the fix or the
      explanation follows it
- [ ] B's characterization committed with numbers (what the present call waits on; what the targets' creation
      flips are; what the two A/B runs moved)
- [ ] two consecutive probe runs with no frame over 25 ms involuntary at B's flips (7023/7623/10533-class), and
      the A clusters gone or explained
- [ ] `tools/stutter_check.sh` PASS with the figures in the Result
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` PASS 7/7 (the pins on: no pixel moves)
- [ ] `tools/flash_check.sh --shell vulkan` PASS
- [ ] `tools/patches.sh check` and `python3 tools/docs_check.py` pass; nothing committed under vendor/

## Verify
`tools/stutter_check.sh && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/flash_check.sh --shell vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/vulkan_renderer.hpp,
  vendor/portablekit/host/perf/frame_stats.cpp, vendor/portablekit/host/perf/frame_stats.hpp: only through
  `tools/patches.sh export 0022-...`; commit patches/, never vendor/
- patches/0022-*.patch (new), patches/README.md
- src/profile/ (only if A's finding lands there; the smallest change)
- docs/windows.md, docs/verification.md, README.md, docs/tasks/078-vulkan-effect-slowdowns.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, tools/ (stutter_check's bounds are the planning session's),
  vendor/portablekit/host/kernel/, vendor/portablekit/host/gpu/shaders/ unless B's fix needs a trivial hook there
  (then say so in the Result), src/gpu/ (the Metal backend is the reference, not the patient), ref/,
  docs/decisions.md, docs/status.md, any vendor file not listed, anything not listed above

## Estimated turns
60

## Escalate when
- A's guest time turns out to be the kernel scheduler's or the code generator's (out of bounds here)
- an interpreter fallback is found (name the function and BLOCK: the corpus is not this task's to regenerate)
- B's stall survives both eager targets and an executed warm pass (report what the driver is doing with evidence)
- any suite scene moves with the pins on

## Findings

### B: the "first-use present hitches" are the sweep's own window captures (2026-10-12, from the existing logs)
Read from out/078-probe and out/stutter_check/vulkan-vulkan/race in the 077 worktree, no new run:
- Every B flip is a `[script] frame N: shot slowM` line followed by `[render] window 960x544 -> .../slowM.bmp`:
  7023 (slow7013), 7623 (slow7613), 10533 (slow10521) in 078-probe; 7023 (slow7015), 10863 (slow10851), 11463
  (slow11451) in the run before. tools/campaign_sweep.py takes up to three `slow` shots a race, 600 flips apart,
  when the ship drops under 30 km/h (line 1182: "what slowed the ship down"), so they repeat at nearly the same
  flips run after run. That, not a driver's first use, is why they are deterministic.
- Every other window capture costs the same, whatever was drawn before: `ref` (6920: 137.2 ms; 6910 in the other
  run: 150.8 ms), the menu shot (5410: 116.1 / 127.5 ms) and all fourteen `fNNNNN` shots of the results screen every
  30 flips from 17850 (115 to 165 ms each, both runs). 14 of 14 re-shots of a screen already drawn can not be a
  first use.
- The time is `render` in the `[slow-frame]` split (109.4 of 121.2 ms at 7023), and `[render-split]`'s `present`
  (2.25 ms a frame in the second with the shot vs 0.19 a second later at 16843: 110 ms over 50 frames) because
  VulkanRenderer::Impl::write_capture runs at the end of submit_and_present: it fence-waits the frame, then
  write_bmp() reads the mapped capture buffer byte by byte. That buffer is allocated with
  `find_memory_type(HOST_VISIBLE | HOST_COHERENT)`, the first such type, on NVIDIA the uncached (write-combined)
  one, so each of the ~1.5 M byte loads is an uncached read; then a 1.5 MiB BMP is written synchronously.
- A player never captures the window (only `<prefix>_INPUT_SCRIPT`'s `shot` does), so B is a measurement artifact
  of the probe, not a slowdown in play. The prewarm, the 1x effect targets (patch 0018) and the shader cache are
  not involved; the `PURE_NO_PIPELINE_PREWARM=1` and cleared-DXCache runs the brief proposes would only move a
  first use, which this is not, so they were not run.

### A: the guest-time clusters are the guest thread blocked writing stdout to the sweep's pseudoconsole
Two instrumented stutter_check runs (out/078/probe1, out/078/probe2 in this worktree; instruments not committed: the
`[pure] ship frame` write in src/profile/test_hooks.cpp timed, a `[probe078] ship line write N ms` line when over
1 ms (probe1) or 10 ms (probe2), and frame_stats' end_frame timing its own prints, reported on the next
`[slow-frame]` line):
- "Guest" in a `[slow-frame]` line is frame minus render minus wait (frame_stats.cpp end_frame), so it includes
  every stdout write the emulation thread makes. On Windows the sweep runs the game under a ConPTY
  (tools/purelib/port.py, task 055) and the MSVC runtime writes each `<<` of a line to the console unbuffered.
- probe2 (threshold 10 ms): the A spikes are the ship line's write. 13364: guest 293.6 ms, ship-line write 255.5;
  13358: 169.6 / 147.0; 14439: 183.3 / 167.1; 9621: 154.4 / 107.4; 7493: 91.8 / 64.3; 16826: 55.0 / 31.3. Where the
  write explains less (14898: guest 149.0, write 20.6) the rest is the next write, the instrument's own
  `[probe078]` line, which is untimed (the log shows nothing else in that frame). Calm frames: guest 10 to 14 ms.
- probe1 (threshold 1 ms) is the dose-response: one extra line after each slow write turned the race from 8 of 222
  seconds over 25 ms into 122 of 256, 7467 ship-line writes over 1 ms summing 25.4 s, the worst one line 540 ms.
  More console output, more guest time: the cost is the console, not the game.
- The spikes move run to run (16842 / 14715 in 078-probe, 9009 / 15878 in the run before, 13364 / 9621 / 14439
  here): they follow when the sweep's reader falls behind, not the race's effects. No `[interpreter]` line in any
  of the logs (its first fallback is announced unconditionally on stderr, which the ConPTY merges), so no
  interpreter fallback; the E6 wrap runs once a frame (FUN_088eda8c is sceGeDrawSync's only caller) and is two
  loads and a store.
- The Mac's runs go through a pty, a kernel buffer the writer does not wait on, which is why its gates see none.
  A player starts PureNative without the sweep's ship lines and without a ConPTY reader, so A, like B, is the
  probe's; the fix belongs to the harness (an asynchronous log writer in the host, or the sweep's reader), both
  outside this brief's May touch.

## Result

### Status
PARTIAL. Both classes are characterized and committed, and both turn out to be the probe's own, not a player's: B
(the present hitches) is the sweep's window captures, now about 4 ms instead of 110 to 160 (patch 0022). A (the
guest-time clusters) is the game thread blocked writing stdout to the sweep's ConPTY; the fix belongs to the harness
or the host's logging, both outside May touch, so A is explained, not fixed. The Verify line stops at flash_check,
which FAILs the same way without patch 0022 (see below), so the FAIL is not this task's.

### Changed
- patches/0023-vulkan-cached-window-capture.patch (new; vendor/portablekit/host/gpu/vulkan_renderer.cpp: the
  window capture's buffer comes from a HOST_CACHED | HOST_COHERENT type when there is one), patches/README.md (row
  and section)
- docs/windows.md (one line in the 2026-10-12 findings), docs/tasks/078-vulkan-effect-slowdowns.md (Findings, Result)
- Nothing under src/profile/ is committed: the A instruments (a timed ship-line write, frame_stats timing its own
  prints) were temporary and are reverted. No new switch, so README.md and docs/verification.md are unchanged.

### Figures
- B, the stutter_check run of the Verify line: the shot flips 10713 / 11313 / 12683 take 31.1 / 29.0 / 26.3 ms (render
  17.7 / 14.8 / 13.5), down from 118 to 160 ms. The capture itself is about 4 ms (fence 1.5 to 3.3, read and write
  1.6 to 2.5, probe2). The rest of those frames is the frame's own ~14 ms plus the three stdout lines the shot prints
  (`[script]`, `[render] window`), which are A's cost. So the "under 25 ms at B's flips in two consecutive runs"
  criterion is not met to the letter: 26 to 32 ms in probe2 and the Verify run, the excess being A, and only in
  probes. stutter_check leaves the capture flips out only when they are a multiple of 10 (the `ref` shot at 6920);
  the `slow` shots are counted, which is why 077's worst second was a shot (10863, 175.4 ms).
- A: in probe2 the timed ship-line write accounts for the spikes (13364: 255.5 of 293.6 ms guest; 14439: 167.1 of
  183.3; 9621: 107.4 of 154.4); probe1, which printed one more line per slow write, had 122 of 256 seconds over 25 ms
  (vs 8 of 222) and a single line taking 540 ms. No interpreter fallback in any log; the E6 wrap runs once a frame.
- stutter_check: PASS, 11 of 211 seconds over 25 ms (5.2%), readback 0.00 ms a frame; the new worst second is
  flip 11253 at 39.2 ms (it was 10863 at 175.4 ms, a shot). The bound was not touched. The remaining slow frames are
  A's console writes and the live-file flips, both the sweep's, so a tighter bound would measure the harness.
- frame_regress --shell vulkan --backend vulkan: PASS 18/18 (8m 57s).
- flash_check --shell vulkan: FAIL, three times: twice with patch 0022 and once with it reversed and rebuilt
  (out/078/flash-no0022.log): `fade 2 flips off, 2 on; the fade with the option off is 2 flips (at least 50)`. With the
  option off, the race-start fade is 2 flips here where task 077 measured 58. That is a regression already on
  batch/m2 (or in the rig's state), independent of this task. It was not chased (outside the brief).
- patches.sh check: ok, 22 patches. docs_check: PASS.

### Verify output
The Verify line exits at flash_check. Last 20 lines (out/078/verify.log; patches and docs re-run after):
```
race: PASS, paced from flip 6100; 211 seconds, 11731 frames
(a) seconds with a frame over 25 ms: 11 of 211 (5.2%); apart, the live-file flips (a multiple of 10) over it: 1010, worst 90.2 ms
(b) readback: 0.00 ms a frame
worst second: #95 after the paced flip, frame avg 17.3 max 39.2 ms, flip 11253 39.2 ms
stutter_check: PASS (11 of 211 seconds over 25 ms, readback 0.00 ms a frame)
...
tt_hud       5890    0.0470   0.12   32     0.049 -0.0020  PASS
fp_hud       5890    0.0582   0.11   32     0.048 +0.0102  PASS
zone_hud     5260    0.0482   0.09   32     0.045 +0.0032  PASS
zone_change   5679    0.0479   0.10   32     0.052 -0.0041  PASS
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (8m 57s)
  hud_check: 1 of 1 shots have the HUD
  hud_check: 1 of 1 shots have the HUD
PURE_SMOOTH_FLASHES=0: flips 5600-6100: 164 at two vblanks, longest run 105; 105 before the race's first one-vblank flip (5705); the fade: flips 5706-5707, 2 flips, 0.07 s; the race clock starts at flip 6254, 549 flips and 10.13 s from the fade's first
PURE_SMOOTH_FLASHES=1: flips 5600-6100: 107 at two vblanks, longest run 105; 105 before the race's first one-vblank flip (5705); from the fade's first flip (5706) to 6100: 2 at two vblanks (5706-5707); the fade's 0.07 s span flips 5706-5707, 2 flips; the race clock starts at flip 6311, 606 flips and 10.11 s from the fade's first; '[pure] smooth flashes: on (game.smooth_flashes)' after flip 5700
flash_check: FAIL (fade 2 flips off, 2 on; the fade with the option off is 2 flips (at least 50))
ok: 22 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 33 files, 0 findings: PASS
```

### Open questions
1. A is the harness's to fix: the sweep's ConPTY reader (tools/purelib/port.py, conpty.py) or an asynchronous log
   writer in the host so a blocked console never stalls the game thread. Either one would also take the leftover
   ~10 ms off the shot flips. Which one, and in which task?
2. Erik's "slowdowns with effects in play": neither probe class happens without the sweep. If he still feels them,
   the next probe is a played race without the sweep (`PURE_PERF=log PURE_TRACE_STALLS=1` with stdout to a file),
   and its `[slow-frame]` lines.
3. flash_check's fade is 2 flips with Flashes off on batch/m2 (it was 58 in task 077). That is a regression to find
   on the branch's history: E4/E6 or the rig.
4. The brief's PURE_NO_PIPELINE_PREWARM and cleared-DXCache runs were not made: B is not a first use, so they would
   test a cause that the logs rule out.

## Review

Merged bef8bda (2026-10-12). Both characterizations hold up and both overturn a premise, which is the second task in
a row where characterizing first earned its place:
- **B (the present hitches) was the sweep's window captures**, not a first use; the brief's prewarm designs and the
  PURE_NO_PIPELINE_PREWARM / DXCache runs were rightly dropped as testing a ruled-out cause. Patch
  0023-vulkan-cached-window-capture is small and right (the capture buffer from a HOST_CACHED type), and it
  benefits every windowed capture the tools take: the shot flips fell from 118-160 ms to 26-31, the remainder being
  A's stdout cost.
- **A (the guest clusters) is the game thread blocked writing stdout into the tools' pseudoconsole** (a single line
  up to 540 ms under instrumentation): the harness's, not the game's — the release build has no console, so a
  player never pays it. The locking in tools/purelib/port.py is not the cause (the reader drains the pipe outside
  the parse path), so the blockage is conhost's own processing; the fix is a host-side asynchronous or file logger
  (a vendor follow-up, recorded in status) rather than a tools change.
- **The Verify's flash_check FAIL was the fade detector's split artifact, not a regression**: the run's trace shows
  the fade intact at flips 5709-5765 (57 two-vblank flips) with a single one-vblank flip at 5708 splitting the
  detector's first-run rule. The review changed the rule to the longest run (tools/flash_check.sh; the 57-flip
  bound untouched), re-judged the worker's three failing logs as PASS with the canonical line, and reran the check
  fresh on the merged build. For the Mac session: the detector change is behaviour-neutral where runs are clean.
- **What the task did not close, by design:** Erik's felt in-play slowdowns match neither class (both are
  harness-only), so the play-side candidates are next — the 100 Hz FIFO presentation cadence (60 fps on a 100 Hz
  display alternates one- and two-vblank holds under Vsync On; the Esc menu's Vsync row has Off (mailbox)), or
  whatever the Performance overlay shows during his race. That is Erik's test to run, recorded in status.

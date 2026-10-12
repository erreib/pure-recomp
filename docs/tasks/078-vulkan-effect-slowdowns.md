# 078: The race's effect slowdowns on the Vulkan renderer

Milestone: Windows fidelity (Erik, 2026-10-12: still not on par with the Metal build; the slowdowns cluster where
the screen fills with effects) | Branch: task/078-vulkan-effect-slowdowns | Status: OPEN

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
  0021-vulkan-async-readback as models), docs/upstream.md
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

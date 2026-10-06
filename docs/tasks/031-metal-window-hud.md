# 031: The Metal window drops the race HUD: one command queue for the backend and the shell

Milestone: M7 | Branch: task/031-metal-window-hud | Status: OPEN

## Goal
Under the default path (`PURE_SHELL=metal PURE_GE_BACKEND=metal`, task 028) the window often shows a race frame
without the HUD: 10 of 59 probe shots had it, against 61 of 61 on the Vulkan window and 61 of 61 in the backend's own
headless captures (task 028's Result, "The race HUD on the Metal window"). The shell samples the backend's target from
a command queue of its own; the backend commits the frame's last command buffer at `present_image` without waiting,
and in a race the depth write-back at the SIGNAL commits and waits mid-frame, so the 3D part is done when the shell
samples and the draws after it, the HUD, may not have run. Task 027 noted the reliance (its open question 4). Fix it
by putting the backend and the shell on one command queue of one device, so Metal orders their command buffers, and
prove it with the probe.

## Read first
- CLAUDE.md, docs/tasks/028-metal-by-default.md (Result: the probe, the numbers, the likely cause, the fixes
  considered), docs/tasks/027-metal-shell.md (Result, open question 4), docs/metal-backend.md ("Frames, captures and
  the window", "The Metal shell"), docs/ge-backend.md 8.5
- src/gpu/metal_backend.mm (`initialize`: the device and queue; `commit`; `present_image`; `store_depth`'s mid-frame
  commit and wait), src/host/metal_shell.mm (`initialize`: its device and queue; `draw`: where it samples the
  backend's texture and presents)
- The probe: /Users/erreib/dev/pure-recomp/out/028-wip/hud/ (`run.sh`, `hud.py`: shots every 25 flips from 6200 to
  7700 of the race route under the three paths, the yellow CURRENT and LAP labels looked for; copy it into tools/
  as `tools/hud_check.sh` + `tools/hud_check.py`, cleaned up, as this task's Verify)
- Apple's Metal documentation on command buffer ordering within a queue (read only): command buffers committed to
  one queue execute in commit order; across queues, only `MTLSharedEvent` or a wait orders them

## Deliverable
1. One device and one command queue shared by `MetalGeBackend` and `MetalShell`: a small header in src/gpu
   (`metal_device.hpp`/`.mm`: `pure::metal::device()` and `pure::metal::queue()`, made once with
   `MTLCreateSystemDefaultDevice`, in our sources only; the vendor's `BackendConfig` and `ShellConfig` do not change).
   Both use it; the shell's `draw` command buffers are then ordered after the backend's `present_image` commit on the
   same queue. The backend's `in_flight_` bookkeeping and the shell's wait for its previous present keep working.
   Document the ordering rule in docs/metal-backend.md ("The Metal shell") and why a shared event was not needed.
2. `tools/hud_check.sh [--shell vulkan|metal|headless]` from the probe: runs the race route with a shot every 25
   flips from 6200 to 7700 (window shots in a window, the backend's captures headless), counts the shots with the HUD
   (`tools/hud_check.py`: the CURRENT and LAP labels' yellow columns as the probe found them), prints
   `hud_check: N of M shots have the HUD` and exits 0 when N equals M. Keep the probe's thresholds; put the
   shot and label regions in the script's header.
3. docs/verification.md: the HUD check beside the suite (it guards what race_hud at 6016, before the race clock
   starts, does not). tools/campaign_sweep.py: remove task 028's Vulkan pin (the sweep then runs the default path),
   and run `tools/campaign_sweep.py single_race vineta_k` to show the sweep reads its shots under the Metal shell
   (PASS, the `ref` shot's shield bar read as full).
4. README.md: the hud_check row; the campaign sweep row without the pin note.

## Acceptance criteria
- [ ] `tools/hud_check.sh` (Metal shell, the default): every shot has the HUD (61 of 61, or the probe's count).
- [ ] `tools/hud_check.sh --shell vulkan` and `--shell headless` still give all shots.
- [ ] `tools/frame_regress.sh` (Metal default) passes 5/5 at the Metal measured column, and `tools/frame_regress.sh
      --shell vulkan --backend vulkan` 5/5 at the Vulkan column; `tools/frame_regress.sh --shell metal --backend metal
      --only race_hud` three times in a row within 0.005 of 0.0379.
- [ ] `tools/campaign_sweep.py single_race vineta_k` PASSes on the default path with the sweep's `ref` shot reading
      the shield bar as full.
- [ ] The race runs at 60 fps under the Metal shell as before (task 025's number; `PURE_PERF=log` or the shell's
      frame-rate line), and no GPU wait is added per frame beyond task 025's SIGNAL wait.

## Verify
`tools/build.sh profile && tools/hud_check.sh && tools/frame_regress.sh --only race_hud && python3 tools/campaign_sweep.py single_race vineta_k && grep -c PASS out/sweep/summary.txt`

## May touch
- src/gpu/metal_backend.mm, src/gpu/metal_device.hpp and .mm (new), src/host/metal_shell.mm, CMakeLists.txt (the new
  source), tools/hud_check.sh and tools/hud_check.py (new), tools/campaign_sweep.py (the pin only), docs/metal-backend.md,
  docs/verification.md, README.md

## Must not touch
- vendor/, patches/, src/gpu/metal_shaders.h, src/host/pure_main.cpp, src/tools/, tools/run_boot.py,
  tools/frame_regress.sh, config/, ref/

## Estimated turns
40

## Escalate when
A shared queue does not fix the count (report the probe's numbers with the shared queue, and with a
`waitUntilCompleted` before the hand-over as a second experiment, so the cause is known), or the race's frame rate
drops under 55 fps with the fix (report the numbers).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

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
Status: DONE. The backend and the shell now share one device and one command queue. The Metal window shows the race
HUD in 61 of 61 shots (11 of 61 before the change, in the same check). The Verify line passes
(`tools/verify_task.sh 031`, exit 0).

Changed:
- `src/gpu/metal_device.hpp`, `src/gpu/metal_device.mm` (new): `pure::metal::device()` and `pure::metal::queue()`.
  Both are function-local statics, made once on first use with `MTLCreateSystemDefaultDevice` and `newCommandQueue`.
  Both are nil without a Metal device. The header's comment states the ordering rule.
- `src/gpu/metal_backend.mm`: `initialize` takes `device_` and `queue_` from them instead of making its own. Header
  comment updated. Nothing else changed: `commit`, `in_flight_`, `present_image` and `store_depth` are as they were.
- `src/host/metal_shell.mm`: `initialize` takes `device_` and `queue_` from them instead of making its own. Header
  comments updated. `draw`, `wait_idle` and the captures are unchanged.
- `CMakeLists.txt`: `src/gpu/metal_device.mm` added to the sources and to the Objective-C++/ARC property list, with a
  comment.
- `tools/hud_check.sh`, `tools/hud_check.py` (new), from task 028's probe:
  - The shell is chosen with `--shell metal|vulkan|headless`; the default is metal. The backend follows the shell
    (metal, vulkan, and metal for headless) unless `--backend` names one. `--out` defaults to `out/hud/<shell>`.
    `--env` is also accepted.
  - The route, the shot schedule and the label regions are in the scripts' headers. The probe's thresholds are kept
    (red > 180, green > 130, blue < 90).
  - It prints `hud_check: N of M shots have the HUD` and exits 0 when all 61 shots were taken and show the HUD.
- `tools/campaign_sweep.py`: the Vulkan pin is gone (`setdefault` of `PURE_SHELL` and `PURE_GE_BACKEND`), and the
  docstring now says the sweep runs the default path.
- `docs/metal-backend.md`:
  - "The Metal shell" has a new "One command queue" subsection: the ordering rule, why no shared event was needed,
    the before and after counts, and the frame rate.
  - Updated to match: the shell table's Window row, the Frames bullet, and the Files table (the new row; "the four
    `.mm`").
- `docs/verification.md`:
  - A new section, "The race HUD check", sits beside the suite. It covers the route, the regions, the shells, and a
    table of the counts before and after.
  - The suite intro now names the HUD check.
  - The race_hud bullet now gives the Metal spread as 0.0344 to 0.0384.
- `README.md`: a hud_check row; the campaign sweep row no longer has the pin note.
- Commits: babd9f1, a2785e7, c0d66dd, c2432b9, a0f5e4e, efc9c38, and the Result commit.

Acceptance:
1. `tools/hud_check.sh` on the Metal shell (the default): 61 of 61, twice.
   - The Verify run, in `out/hud/metal`.
   - A run with `--env PURE_PERF=log`, in `out/031/hud-after-metal-perf`.
   - On the unchanged build (`out/031/hud-before-metal`) the same check gave 11 of 61.
2. `--shell vulkan`: 61 of 61 (`out/031/hud-after-vulkan`). `--shell headless`: 61 of 61 (`out/031/hud-after-headless`).
3. The suite on both paths:
   - `tools/frame_regress.sh` (Metal default, `out/031/regress-metal`, 7m 9s): 5/5 with no "moved" note. lang 0.0002,
     title 0.0002, profile 0.0000, main_menu 0.0106, race_hud 0.0384 (+0.0005).
   - `--shell vulkan --backend vulkan` (`out/031/regress-vulkan`, 7m 11s): 5/5 at 0.0544, 0.0302, 0.0543, 0.0331 and
     0.0667 (race_hud -0.0003).
   - `--shell metal --backend metal --only race_hud`, three times in a row:
     - Scores: 0.0381, 0.0373 and 0.0344 (deltas +0.0002, -0.0006, -0.0035), all within 0.005 of 0.0379. The Verify
       run's race_hud scored 0.0374.
     - All five captures show the HUD: the CURRENT and LAP labels have 500 and 172 yellow pixels in each.
     - A diff of the 0.0344 capture against the 0.0381 one (`out/031/race_hud-3-vs-1.png`) differs only at the AI
       ships on the grid.
4. `tools/campaign_sweep.py single_race vineta_k` on the default path: PASS.
   - The log shows `[shell] metal` and `[metal] drawing ... pictures shown by the shell`.
   - The `ref` shot read the shield bar as 100%.
   - Result: flip 17850; laps 64.1, 59.5 and 63.4 s; 40 contacts; 19.4 shield left. The summary's `grep -c PASS`
     prints 1.
5. Frame rate and waits:
   - With `PURE_PERF=log`, the race's 24 one-second `[perf]` lines (flips 6250 to 7710 of the check's route) read 59.7
     to 60.1 fps, with render at 3.1 ms a frame on average.
   - The backend waited for the GPU 2009 times in 7710 flips, 2003 of them at the SIGNAL. That is the same count as
     the unchanged build's 2009 (1322 ms before, 1274 ms after). No wait was added in either file.

Verify output (last 20 lines; `tools/verify_task.sh 031`, exit 0):
```
[sweep] single_race-vineta_k: shot f17500: TOTAL label variance 2906, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17530: TOTAL label variance 1272, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17560: TOTAL label variance 136, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17590: TOTAL label variance 4046, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17620: TOTAL label variance 4412, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17650: TOTAL label variance 4225, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17680: TOTAL label variance 3088, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17710: TOTAL label variance 4353, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17740: TOTAL label variance 4093, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17770: TOTAL label variance 4284, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17800: TOTAL label variance 2956, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17830: TOTAL label variance 3315, steady True (1 in a row)
[sweep] single_race-vineta_k: PASS at flip 17850, 3 laps, race time 194.4 s, 399 s: results screen at flip 17840 (3 laps: 64.1, 59.5, 63.4 s; 194.2 s at the shot); 40 contacts (11, 13, 16 a lap); shield 19.4 at the end, 81 taken
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| single_race | vineta_k | PASS | 17850 | 3 | 194.4 | 399 | 2026-10-06 11:08 | results screen at flip 17840 (3 laps: 64.1, 59.5, 63.4 s; 194.2 s at the shot); 40 contacts (11, 13, 16 a lap); shield 19.4 at the end, 81 taken |
1
verify 031: PASS
```
Above them in `out/031/verify.txt`:
- `hud_check: 61 of 61 shots have the HUD` (233 s, frame 7710 reached).
- The suite line `race_hud 6016 0.0374 0.10 32 0.0379 -0.0005 PASS`.
- `frame regression: PASS, 1/1 scenes pass, shell metal, backend metal (3m 19s)`.

Open questions:
1. HUD counts per path (`tools/hud_check.sh`, 61 shots from flip 6200 to 7700):

   | Path | Before (two queues) | After (one queue) |
   |---|---|---|
   | Metal shell, Metal backend (default) | 11 of 61 (this task, unchanged build); 12 of 61 (task 028's probe) | 61 of 61 (twice) |
   | Vulkan shell, Vulkan backend | 61 of 61 (task 028's probe) | 61 of 61 |
   | headless, Metal backend | 61 of 61 (task 028's probe) | 61 of 61 |

2. On the cause:
   - Task 028's Result guessed that the SIGNAL's mid-frame commit and wait was part of it. It was not. Rescored with
     the same thresholds, task 028's `window_metal_nodepth` shots (`PURE_NO_DEPTH_READBACK=1`, one command buffer a
     frame) have the HUD in 3 of 61.
   - The missing ordering between the two queues was the cause, and one queue fixes it.
   - I did not run the escalation's second experiment (a `waitUntilCompleted` before the hand-over), because the
     shared queue fixed the count.
3. One Metal race_hud run scored 0.0344, below the earlier 0.0366 to 0.0383. Its capture has the HUD, and it differs
   from the 0.0381 run only at the AI ships. I widened the spread in docs/verification.md to 0.0344 to 0.0384 and left
   the measured column at 0.0379. Re-baselining is Fable's call.
4. A mid-race scene in the suite (task 028's open question 1): `tools/hud_check.sh` now guards the race, but the suite
   still does not. Adding a scene would mean changing `tools/frame_regress.sh`, which this brief lists under "Must not
   touch".
5. ge_replay's Metal backend also uses the shared device and queue now. When a replay runs Metal on both sides
   (`--a metal --b metal`), the two instances share one queue. That is still ordered and correct. The other two-backend
   pairs are unaffected.
6. Not in "May touch": docs/ge-backend.md 8.5 describes the shell seam and says nothing about queues, so it needs no
   change.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

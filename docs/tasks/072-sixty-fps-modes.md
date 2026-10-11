# 072: Time Trial, Free Play and Zone free-running (E4)

Milestone: E4 (Erik, 2026-10-11; D-017) | Branch: task/072-sixty-fps-modes | Status: OPEN

## Goal
Time Trial, Free Play and Zone run at 30 fps on the PSP: their race managers set the frame object's lock byte
(`+0x116c`) to 0 right after the race backend's constructor set it to 1, and the end-of-frame routine `FUN_0886511c`
then waits two vblanks a frame (docs/timing.md step 5). The game's simulation integrates a measured dt
(`FUN_08804390`, from `sceKernelGetSystemTimeWide`, capped at 0.067 s), and the planning session's audit (D-017;
out/e4/ on the Mac: the decompiles, the sweep cells, compare.py) found nothing in those modes that advances per
frame: with the byte forced to 1 a paced Time Trial ran at 59.95 flips a race-clock second with the same standing
start, the same game-clock rate and a ghost that samples by time; Zone's zone timer and shield drain followed the
race clock. After this task the port stores 1 to that byte each frame while the race backend lives, behind an
Esc-menu row that is on by default, and the checks run with it off so every measured scene stays where it was.

## Read first
- CLAUDE.md, docs/decisions.md (D-016 and D-017: the decision this task carries out, with the audit's figures),
  docs/timing.md (step 5, "The two lock fields", "E6: the flash lock cleared", "The game's clock in a race"),
  docs/history/fidelity.md ("What writes the two fields"), README.md (the switches table: `PURE_SMOOTH_FLASHES`,
  `PURE_TRACE_CALLS`, `PURE_WATCH_SHIP`, `PURE_WATCH_WORDS`; the tools table: `tools/flash_check.sh`)
- src/profile/enhancements.cpp and .hpp (E6: the option table, the `sceGeDrawSync` wrap this task extends),
  src/profile/pure_profile.cpp (`register_pure_hle`: the order; the Flashes comment at `.options`)
- tools/flash_check.sh (the shape of the new check: two runs, the `[call]` lines' `t=`, `TWO_VBLANK_US` imported
  from fidelity_audit, hud_check on a shot, `--race` through campaign_sweep), tools/purelib/port.py
  (`original_pacing`, `SCRATCH_SETTINGS`), tools/run_boot.py (where `original_pacing` is called after `--env`),
  tools/campaign_sweep.py (its usage; the `time_trial` mode: route config/pad_scripts/time_trial.txt, the race from
  about flip 6010, budget 9000 at 30 fps; `--frames`; the cell's trace.csv columns `frame,clock,lap,dist,...,kmh`),
  tools/menu_check.sh (the expected Video rows), tools/frame_regress.sh (tt_hud, fp_hud, zone_hud, zone_change:
  the scenes that must not move), tools/ghidra_headless.sh (`script Callers OUT 0xADDR...` lists every function
  that reads or writes an address; `script Decompile OUT 0xADDR...`)
- docs/controls.md ("Rebinding", "In settings.ini": where the Flashes row and `game.smooth_flashes` are described),
  docs/verification.md (the pin paragraph naming `PURE_SMOOTH_FLASHES`; "Which path for which change"),
  docs/release.md (settings.ini row), docs/fidelity.md ("The two-vblank stretches": names the three modes as 30 fps)

## Deliverable
One commit (or two: the hook and option, then the check and docs).
- `src/profile/enhancements.cpp`: a second option, listed **before** Flashes in `kOptions`: key `sixty_fps`, label
  `Frame rate`, choices `Original`, `60 fps`, default `60 fps` (index 1), tab Video, description along the lines of
  "Time Trial, Free Play and Zone run at 30 fps on the PSP. 60 fps runs them at the display's rate, as Single Race
  and Tournament already do. The game's speed is the same either way (it measures time)." Shorten the Flashes
  description's last sentence to match (it says those modes "still do" run at 30 fps: now "unless Frame rate says
  60 fps", or words to that effect).
- The hook, in the same `sceGeDrawSync` wrap as E6 and **before** E6's clear (so a Smooth flash in a free-running
  Time Trial takes E6's path too): when `settings::game_option("sixty_fps")` is 1, read `load32(0x08A8C5F4)`
  (`DAT_08a8c5f4`: the race backend object, stored by `BackendRoot_cpp__0880c068` at 0x0880c0cc, zeroed by
  `BackendRoot_cpp__0880c328`; 0 in the executable's .data); if it points into user RAM (0x08800000 to 0x0A000000)
  and the frame object pointer at `0x08A8E960` does too and `load8(obj + 0x116c) == 0`, `store8(obj + 0x116c, 1)`.
  Nothing else; outside the backend (the frontend) the byte is left alone. Log once at the first store `[pure]
  sixty fps: on (game.sixty_fps)`, and once at start if the option is off `[pure] sixty fps: off`. Give the two
  addresses named constants beside `kFrameObjectPtr`, with the comment saying what each is.
- Confirm the two facts the hook rests on, and name them in the Result: (a) every reader of `+0x116c` in
  `generated/` (loads at offset 4460 on the frame object: the planning session found `FUN_0886511c` at 0x08865240
  and eight functions of MemStickUtil.cpp, the save-dialog driver, which saves the byte to `DAT_08b17c14` before a
  dialog and restores it after); (b) every reference to `DAT_08a8c5f4` (`tools/ghidra_headless.sh script Callers
  out/072/refs.txt 0x08a8c5f4`): expected the constructor's store, the destructor's zero, and reads. If a reader of
  the byte acts on it beyond pacing and the dialog's save/restore, or a writer of `DAT_08a8c5f4` other than those
  two exists, BLOCKED with the list.
- The pin: `tools/purelib/port.py` `original_pacing(env)` also does `env.setdefault("PURE_SIXTY_FPS", "0")` (update
  its docstring and the constant beside `ORIGINAL_PACING`, or make it a tuple), and `SCRATCH_SETTINGS` gains
  `game.sixty_fps=0`. `tools/run_boot.py --env PURE_SIXTY_FPS=1` must win over the pin, as `--env
  PURE_SMOOTH_FLASHES=1` does (the same call order; nothing to change if it already covers every variable the
  function sets, but check).
- `tools/framerate_check.sh [--race] [--shell headless|metal|vulkan] [--backend metal|vulkan] [--out DIR]`, in the
  shape of tools/flash_check.sh:
  - default: the Time Trial route. Two headless runs of `main_menu.txt+time_trial.txt` to flip 7000 with
    `PURE_TRACE_CALLS=sceDisplay:0x289D82FE` and `PURE_WATCH_SHIP=1`, one with `--env PURE_SIXTY_FPS=0` and one
    with `1` (Flashes stays pinned to 0 in both). For each run take the flip intervals from the `[call]` lines' `t=`
    and compute the median over the frontend flips 4000 to 5000 and over the race flips 6300 to 6900 (the race's
    first frame is about flip 6010 on this route; the start fade is over by 6300), and the race clock's advance per
    flip from the `[pure] ship frame` lines' `clock=` between 6300 and 6900. PASS when: both frontend medians are
    within 31 to 36 ms (the frontend stays at two vblanks); the run with 0 has a race median within 31 to 36 ms
    and 29 to 31 flips a clock second; the run with 1 has a race median within 15 to 18 ms and 58 to 61 flips a
    clock second; the run with 1 prints `[pure] sixty fps: on` after flip 5900 and not before (grep the log's order:
    the line must follow the `[call]` line of a flip at or after 5900) and the run with 0 prints `off` and no `on`;
    a frame dumped at 6900 in the run with 1 passes `tools/hud_check.py` (the HUD is drawn). Print the medians, the
    flips a second and the wall time of both runs.
  - `--race`: two Time Trial cells of Vineta K through `tools/campaign_sweep.py time_trial vineta_k` (headless, the
    sweep's defaults; the run with 1 needs `--frames 18000`, twice the budget, since the budget counts flips), one
    with `PURE_SIXTY_FPS=0` in the environment and one with `1`, both with `PURE_WATCH_WORDS=08a8c3dc` (the game
    clock, a float at `DAT_08a8c3dc`, printed with the virtual time `t=` once a flip). From each cell's trace.csv
    (rows with `race` 1): flips a race-clock second over the race; from its log: the game clock's advance per
    virtual second over the race flips (parse the words lines; the clock jumps to 1000 once early on, so fit from
    the first value above 1000); from the trace: the mean `kmh` in each half-second bin of race clock from 0.5 to
    2.5 s (the standing start, before the first speed pad at about 2.5 s: the planning session saw 42/80/124/174
    km/h at 0.5/1.0/1.5/2.0 s at 30 and 40/78/121/168 at 60). PASS when the run with 0 has 29 to 31 flips a second
    and the run with 1 58 to 61; both game clocks advance 0.99 to 1.01 s a second; every start bin of the run with
    1 is within 5% or 10 km/h of the run with 0; both cells PASS in the sweep's own terms (3 laps, the results
    screen). Print both cells' lap times and contact counts as information (the follower's laps are faster at 60
    because it steers twice as often: not judged). About 4 minutes a cell (paced).
  - exit 0 on PASS; `framerate_check: PASS ...`/`FAIL ...` as the last line; the per-run figures in `--out`
    (default out/framerate_check/).
- `tools/menu_check.sh`: the expected Video rows of both shells gain `Frame rate` before `Flashes` (the menu's
  dump order follows the option table); the check passes on both shells.
- Docs: README.md (the switches table: `PURE_SIXTY_FPS=0|1`; the tools table: `tools/framerate_check.sh`),
  docs/timing.md (a section "E4: the 30-fps modes free-running (task 072)" after the E6 one: D-017, the hook, the
  gate on `DAT_08a8c5f4`, the readers of the byte, the figures), docs/fidelity.md (the two-vblank section: the three
  modes run at two vblanks on the PSP; the option lifts it, task 072, off in the checks), docs/controls.md (the
  Frame rate row and `game.sixty_fps` beside Flashes; the key in "In settings.ini"), docs/verification.md (the pin
  paragraph: both variables; the "Which path" table gains the check), docs/release.md (settings.ini:
  `game.sixty_fps`, default 1). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/framerate_check.sh` PASS: frontend medians two vblanks in both runs; race median two vblanks and 29 to
      31 flips a clock second with the option off, one vblank and 58 to 61 with it on; the `on` line only once the
      race starts; the HUD drawn
- [ ] `tools/framerate_check.sh --race` PASS: 29 to 31 against 58 to 61 flips a second, game clocks within 1% of
      real time, the standing start within 5% or 10 km/h, both cells PASS
- [ ] `tools/flash_check.sh` still PASS (Single Race is not touched by this option)
- [ ] `tools/menu_check.sh` and `tools/menu_check.sh --shell vulkan` PASS with the Frame rate row expected
- [ ] `tools/frame_regress.sh` PASS 18/18 (headless, the pin on): tt_hud, fp_hud, zone_hud, zone_change unchanged
- [ ] a 2200-flip frontend run (`tools/run_boot.py --frames 2200 --pad config/pad_scripts/main_menu.txt --env
      PURE_SIXTY_FPS=1`) prints no `sixty fps: on` line (the frontend's byte untouched)
- [ ] every reader of `+0x116c` and every reference to `DAT_08a8c5f4` named in the Result
- [ ] `python3 tools/docs_check.py` passes

## Verify
`tools/framerate_check.sh && tools/framerate_check.sh --race && tools/flash_check.sh && tools/menu_check.sh && tools/menu_check.sh --shell vulkan && tools/frame_regress.sh && python3 tools/docs_check.py`

## May touch
- src/profile/enhancements.cpp, src/profile/enhancements.hpp, src/profile/pure_profile.cpp (comments only)
- tools/framerate_check.sh (new), tools/menu_check.sh, tools/purelib/port.py, tools/run_boot.py
- README.md, docs/timing.md, docs/fidelity.md, docs/controls.md, docs/verification.md, docs/release.md,
  docs/tasks/072-sixty-fps-modes.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, vendor/, patches/, src/gpu/, src/host/, src/profile/test_hooks.*,
  tools/fidelity_audit.py, tools/campaign_sweep.py, tools/frame_regress.sh, tools/flash_check.sh, tools/hud_check.*,
  ref/, docs/decisions.md, docs/status.md, anything not listed above

## Estimated turns
50

## Escalate when
- the run with the option on does not take the free path (its race median stays near two vblanks), or the
  frontend's medians move
- a game clock advances outside 0.99 to 1.01 s a second, or a standing-start bin differs by more than 5% and
  10 km/h (the game's speed moved: stop, report the figures, do not tune)
- a reader of `+0x116c` acts on it beyond pacing and the dialog's save/restore, or `DAT_08a8c5f4` has a writer other
  than the backend's constructor and destructor
- a build takes over 5 minutes, or the change needs include/psprecomp/, a patch or generated code

## Result
Status: DONE. Every acceptance criterion holds and no escalation condition occurred. One number in the brief was
wrong and the check uses the measured one instead: the `on` line comes after flip 5704, not after 5900 (open
question 1).

Changed (branch task/072-sixty-fps-modes from batch/m2 55b511b):
- Commit 1 (c4d997a), the hook and option: `src/profile/enhancements.cpp` (the Frame rate option `sixty_fps`
  before Flashes: Original / 60 fps, default 1, Video, with the brief's description; Flashes' last sentence now
  "run at 30 fps unless Frame rate says 60 fps"; `kBackendPtr` = 0x08A8C5F4 beside `kFrameObjectPtr`; the one
  `sceGeDrawSync` wrap now calls `sixty_fps()` and then E6's `smooth_flashes()`; the two `[pure] sixty fps` lines),
  `src/profile/enhancements.hpp` and `src/profile/pure_profile.cpp` (comments only), `tools/purelib/port.py`
  (`ORIGINAL_PACING` is now a tuple of `PURE_SIXTY_FPS` and `PURE_SMOOTH_FLASHES`, `original_pacing` sets each to 0
  unless it is already named, `SCRATCH_SETTINGS` gains `game.sixty_fps=0`), `tools/run_boot.py` (docstring only:
  `--env` is merged before `original_pacing` runs, and that call uses setdefault, so `--env PURE_SIXTY_FPS=1` already
  wins), `tools/menu_check.sh` (Video ends with `Frame rate`, `Flashes` on both shells).
- Commit 2 (3db1c66): `tools/framerate_check.sh` (new), README.md, docs/timing.md (new "E4" section), docs/fidelity.md,
  docs/controls.md, docs/verification.md, docs/release.md.
- Commit 3: this Result.

The facts the hook depends on:
- (a) Every reader of `+0x116c` (every load at offset 4460 in `generated/`; all 28 accesses are listed by address in
  out/072/offset4460.txt of the worktree): `FUN_0886511c` at 0x08865240 (step 5), and eight functions of the MemStickUtil save
  dialog: `FUN_088965e0` (0x088966B8), `MemStickUtil_cpp__08896730` (0x0889687C), `FUN_088968f4` (0x08896AB4),
  `MemStickUtil_cpp__08896b68` (0x08896CBC), `FUN_08896ea4` (0x08896FD4), `FUN_08897050` (0x088970E4),
  `FUN_08897180` (0x08897200), `FUN_088972b8` (0x088972F0). I read each of the eight in place: it loads the byte
  through `*0x08A8E960`, stores it to `DAT_08b17c14` and then stores 0. Nothing else is done with it. The value is
  put back by `FUN_08897f20` (0x08897FC4, 0x088981E8; the dialog driver, called from `FUN_0886511c`, which calls
  `sceUtilitySavedataUpdate(2)`), `FUN_08896d7c` (0x08896DD4) and `FUN_08896e30` (0x08896E60). No other reader.
- (b) Every reference to `DAT_08a8c5f4`. These come from Ghidra's Callers script, run on a read-only copy of the main
  checkout's ghidra_project in the scratchpad because Ghidra refuses a path containing `.claude`; the output is
  out/072/refs.txt. They agree with the stores at offset -14860 from 0x08A90000 in `generated/`. Writers:
  0x0880C0CC `BackendRoot_cpp__0880c068` (stores the backend) and 0x0880C5CC `BackendRoot_cpp__0880c328` (stores 0).
  Reads: `Text_Item_cpp__088d3000` (0x088D3340), `FUN_08817130` (0x08817640), `FUN_0881b148` (0x0881B398),
  `LinkObj_etc__08847a54` (0x08847AE8), `FUN_0887be60` (0x0887BE6C), `FUN_088ca0e0` (0x088CA1B0),
  `LinkObj_h__0888e340` (0x0888E364, 0x0888E5F8, 0x0888E6B4), `FUN_0886e4f8` (0x0886E500), `FUN_088066fc`
  (0x08806700), `FUN_0888681c` (0x08886830, 0x088868FC), `FUN_0886eda0` (0x0886EDB0), `LinkObj_h__088baeec`
  (0x088BAF48, 0x088BAF5C, 0x088BAF70, 0x088BB214, 0x088BB238), `FUN_0888db84` (0x0888DC7C), `FUN_08820464`
  (0x08820500), `FUN_08870db4` (0x08870DFC, 0x08870E20), and two reads outside any function Ghidra knows (0x0886EE8C,
  0x08886C44). That is 25 reads and 2 writes.

The other acceptance criteria:
- `tools/framerate_check.sh`: the frontend's median is 33.37 ms in both runs. The race is 33.37 ms at 29.97 flips a
  second with the option off and 16.68 ms at 59.94 with it on. `[pure] sixty fps: off` is printed with 0, and
  `on (game.sixty_fps)` with 1 after flip 5704. The HUD is drawn at 6900. Each run takes 7 to 8 s.
- `--race` (Verify run): 29.98 against 59.95 flips a race-clock second. The game clock runs at 0.9993 and 1.0001 s
  per virtual second. The start bins are 42.1/80.5/124.2/174.4 against 39.3/77.5/121.1/168.2 km/h. Both cells PASS.
  Laps were 73.6, 67.3, 66.9 s with 64 contacts against 61.4, 59.5, 53.9 s with 39 contacts. The cells took 223 and
  186 s. An earlier run gave the same rates and bins to the digit (0.9994 off).
- `tools/flash_check.sh` PASS (fade 57 flips off, 0 on). `tools/menu_check.sh` PASS on both shells.
  `tools/frame_regress.sh` 18/18, and tt_hud, fp_hud, zone_hud and zone_change match the main checkout's last run
  (68803cd) to the digit. The 2200-flip frontend run with `PURE_SIXTY_FPS=1` printed no `sixty fps` line at all.
  `docs_check` PASS.

Verify output (`tools/verify_task.sh 072`, last 20 lines):
```
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
docs_check: 33 files, 0 findings: PASS
verify 072: PASS
```

Open questions:
1. The brief expected the `on` line after flip 5900 and gave the race's first frame as about flip 6010. That is when
   the race clock starts at 30 fps. On this route the race backend is made in the race load right after the TEAM
   SELECTION confirm at flip 5700. The race's first frame is flip 5707, and the fade waits two vblanks from 5708 to
   5764 in both runs. The hook's first store, and so the `on` line, comes after flip 5704. The check therefore
   requires the line after flip `RACE_LOAD`=5700. The frontend before that point is never written. With a 5900
   threshold the check would fail every time.
2. Measured: the race clock starts at flip 6010 with the option off and at 6175 with it on. In virtual time that is
   10.11 s and 8.74 s after flip 5707. This comes from the route's flip-indexed Cross hold at 5900, which lands 2.29 s
   sooner at 60 fps. With the hold moved to flip 6037 (where 5900 falls at 30 fps) the clock starts 10.04 s after
   5707, as in Single Race. So it is not per-frame logic. A player presses in real time.
3. These follow from reading step 5's code and were not measured. A locked frame decrements the countdown even when
   it is 0, so the countdown runs negative through a 30-fps race, and the hook never stores 0. Switching the menu to
   60 fps during a 30-fps race takes effect at once with Smooth, because E6 clears the countdown. With Original it
   waits until a flash has counted down from 2. Switching back to Original during the race leaves the byte at 1, and
   the race ends at 60. Making the switch-off immediate would mean storing 0 back for a backend the hook itself set,
   which goes beyond the brief's "Nothing else".
4. A save dialog that runs while the backend lives sets the byte to 0 to run at two vblanks. The hook stores 1 the
   next frame, so the dialog runs free with the option on, in Single Race and Tournament too. One example is the Time
   Trial ghost's auto-load: `GhostShip_etc__0891e4cc` calls `MemStickUtil_cpp__08896b68` when "Auto Load Ghost" is
   set and a ghost exists. The dialog's own restore puts back 1, and the port's savedata HLE ignores the update's
   vblank count. No run hit this case, because a new profile has no ghost.
5. Under the Vulkan shell the Video tab now has two rows labelled "Frame rate": the renderer's frame-rate cap and
   the game's E4 row (D-017's label). A different label might read better there.
6. On the standing-start bins: the planning figures (42/80/124/174) are reproduced by half-second bins centred on
   0.5, 1.0, 1.5 and 2.0 s, covering 0.25 to 2.25 s. The check uses those. On Vineta K the first speed pad comes at
   about 2.2 s, not 2.5 s. A [2.0, 2.5) bin would straddle it: in the planning cells it read 267/262 in Time Trial and
   184/255 in Free Play.
7. The acceptance's `--pad` is not a run_boot flag. The frontend run used `--script config/pad_scripts/main_menu.txt
   --shell headless`.

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

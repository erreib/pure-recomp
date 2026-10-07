# Verification: the record

What docs/verification.md recorded of each check's first runs and its before-and-after tables, moved here by task 053
(2026-10-07); how each check works stays in [docs/verification.md](../verification.md). Task 053 changed only the patch
numbers, which task 052 regrouped (patches/README.md maps them), naming each by the patch that holds the change now and
the task that made it. Tools and limits are as they were on the dates given.

## The frame regression suite as task 020 made it (2026-10-06)

The suite had five scenes until task 035; its table and notes as they stood:

One command that checks the port still renders the known screens like PPSSPP. By default (task 034) it runs headless
on the Metal backend (`--shell headless --backend metal`): no window, unpaced, the scenes the backend's own 480x272
pictures, about 10 s in all. `--shell metal --backend metal` runs the same backend in the Metal shell's window (the
macOS default for players since D-008, task 028) and `--shell vulkan --backend vulkan` the Vulkan path; in a window
each run is paced to real time and the suite takes about 7 minutes, and `--only race_hud` about 3.5. Which path to
run for which change: "Which path for which change" below. The race HUD check ("The race HUD check" below) covers
the race after the suite's last scene. The suite boots the game three times, once per route, captures five scenes,
and compares each capture with its reference in `ref/` using `tools/imgdiff.py`. It prints a table with PASS or FAIL
per scene and writes the same text to `<out>/summary.txt`. It exits 0 only when every scene passes, 1 when one
fails, and 2 on a usage error, a missing build, game or reference, or another PureNative running (below).

| Scene | Route (`config/pad_scripts/`) | Frame | Reference | Tol | Limit | Vulkan measured | Metal measured (window and headless) |
|---|---|---|---|---|---|---|---|
| `lang` | `frontend.txt` | 690 | `ref/frontend.png` | 24 | 0.07 | 0.054 (task 006; 0.0544) | 0.0002 (task 023) |
| `title` | `frontend.txt` | 1750 | `ref/title.png` | 24 | 0.05 | 0.030 (tasks 006, 009-011; 0.0302) | 0.0002 (task 023) |
| `profile` | `frontend.txt` | 2100 | `ref/profile.png` | 24 | 0.07 | 0.054 (task 006; 0.0543) | 0.0000 (task 023) |
| `main_menu` | `main_menu.txt` | 4700 | `ref/main_menu.png` | 24 | 0.05 | 0.033 (task 006; 0.0331) | 0.0106 (task 023) |
| `race_hud` | `main_menu.txt` + `single_race.txt` | 6016 | `ref/vineta_k_start.png` | 32 | 0.10 | 0.067 (task 011; 0.0672) | 0.0379 (task 025) |

The table lives at the top of the script (`SCENES`), with a measured column per backend and the source of each value
as a comment. A scene's fraction is the share of pixels that differ by more than Tol in any channel, with both frames
at 480x272 (a window's 960x544 capture is reduced by nearest neighbour; a headless capture is 480x272 already). The
scene passes at or below Limit, which is shared by both backends. The Metal column serves the Metal window and the
headless shell alike (task 034): the headless captures of all five scenes equal the Metal window's reduced to
480x272, pixel for pixel (tol 0), and three headless runs scored race_hud 0.0374, 0.0374 and 0.0371 and the other
four scenes at the column exactly, all within 0.001 of it.

- On the Vulkan path lang and profile score 0.054 because of one-pixel edges of lines and glyphs, which the 2x-to-1x
  reduction moves. The Metal backend draws at 480x272 and its shell scales by exactly 2x with nearest sampling, so no
  edge moves: its few differing pixels are blinking cursors (docs/metal-backend.md, "Verify numbers").
  The main menu capture catches the help text partway through typing.
- `race_hud` is frame 6016 of the race route, with bloom and shadows on (the defaults). It is the first frame where
  the HUD has fully faded in, and the same game moment as the PPSSPP frame 7155. The AI ships on the grid change from
  run to run, so this scene varies. Runs of the same code have scored 0.063 to 0.086 on the Vulkan path, and 0.0344 to
  0.0384 on the Metal path (task 025's 0.0379, four runs of task 028 and five of task 031, every capture with its
  HUD), plus one of 0.0823 in task 028 whose capture most likely lacked the HUD, which adds about 0.04 to a frame:
  until task 031 the Metal shell's window dropped the race HUD in most frames once the race ran ("The race HUD check"
  below).

The deliberate regression (2026-10-06, the Vulkan path): `tools/frame_regress.sh --shell vulkan --backend vulkan
--only race_hud --env PURE_NO_STENCIL_BUFFER=1 --out out/regress-nostencil` turns off the stencil attachment of task
011 (a Vulkan backend switch; the Metal backend does not read it). That removes the ship shadows, and task 009's
alpha path darkens the whole track. race_hud then scores 0.3053 (delta +0.238), so it fails with
`out/regress-nostencil/race_hud.diff.png` written, and the suite exits 1.

## The scenes task 035 added (2026-10-06)

Thirteen more PPSSPP scenes (task 035, docs/fidelity.md "PPSSPP references beyond the five"; captures and commands
in `ref/README.md`), each reachable by a route the suite already has, so they add three runs (the Time Trial, Free
Play, Tournament and Zone routes; the Single Race menus share the race route's run). Headless the whole suite now
takes about 23 s.

| Scene | Route (`config/pad_scripts/`) | Frame | Reference (PPSSPP vblank) | Tol | Limit | Vulkan measured | Metal measured |
|---|---|---|---|---|---|---|---|
| `single_player` | `main_menu.txt` + `single_race.txt` | 4765 | `ref/single_player.png` (5850) | 24 | 0.05 | 0.025 | 0.0000 |
| `class_select` | the same | 4990 | `ref/class_select.png` (6050) | 24 | 0.07 | 0.045 | 0.0000 |
| `league_select` | the same | 5185 | `ref/league_select.png` (6250) | 24 | 0.08 | 0.062 | 0.0000 |
| `track_select` | the same | 5390 | `ref/track_select.png` (6450) | 24 | 0.06 | 0.041 | 0.0000 |
| `team_select` | the same | 5600 | `ref/team_select.png` (6690) | 24 | 0.06 | 0.042 | 0.0000 |
| `tt_track_select` | `main_menu.txt` + `time_trial.txt` | 5375 | `ref/tt_track_select.png` (6650) | 24 | 0.06 | 0.040 | 0.0000 |
| `tt_hud` | the same | 5890 | `ref/tt_hud.png` (7340) | 32 | 0.12 | 0.096 | 0.0617 |
| `fp_track_select` | `main_menu.txt` + `free_play.txt` | 5375 | `ref/fp_track_select.png` (6650) | 24 | 0.06 | 0.041 | 0.0000 |
| `fp_hud` | the same | 5890 | `ref/fp_hud.png` (7340) | 32 | 0.11 | 0.095 | 0.0620 |
| `tournament_select` | `main_menu.txt` + `tournament.txt` | 5185 | `ref/tournament_select.png` (6450) | 24 | 0.08 | 0.063 | 0.0000 |
| `zone_track_select` | `main_menu.txt` + `zone.txt` | 4975 | `ref/zone_track_select.png` (6250) | 24 | 0.05 | 0.033 | 0.0000 |
| `zone_hud` | the same | 5260 | `ref/zone_hud.png` (6694) | 32 | 0.09 | 0.065 | 0.0348 |
| `zone_change` | the same | 5679 | `ref/zone_change.png` (7528) | 32 | 0.10 | 0.082 | 0.0649 |

- The menus match PPSSPP exactly on the Metal backend (0 pixels over tol 24): the frontend's 2D draws at 480x272.
  On the Vulkan path (one windowed run, `--shell vulkan --backend vulkan`, 15.5 min for the five routes) they score
  0.025 to 0.063, the one-pixel edges of glyphs and lines that its 2x-to-1x reduction moves, as `lang` and `profile`
  do. The limits follow the re-baselining rule below: the larger backend's value plus about 0.015, rounded up to a
  hundredth.
  Each frame sits inside a run of identical port frames, away from the blinking cursor's changes.
- The three race scenes are the first frame with the HUD fully faded in (as `race_hud` is): CURRENT, BEST and the
  bronze time in Time Trial and Free Play, SCORE and ZONE in Zone. The player is alone in those modes, so the frames
  do not vary from run to run: three headless runs gave the same fraction to four places in every new scene. What
  differs from PPSSPP there is the 3D (docs/fidelity.md: the mip levels, the environment-mapped ship).
- `zone_change` (added last, 2026-10-06) is Zone 1's first zone change: the first frame with ZONE 2, where the score
  jumps from 299 to 800, port flip 5679 and PPSSPP vblank 7528 (both found from the HUD, `ref/README.md` run O). With
  Cross held the ship is at rest against the first barrier by then. Metal scored 0.0649 in three headless runs, the
  Vulkan path 0.0818 in one windowed run (`--only zone_change`, 3 min 10 s); limit 0.10 by the rule below.
- Matching a race scene needs care on the PPSSPP side: a capture made during a load moves the race in emulated time
  (`ref/README.md`), so these references come from runs with no capture before the race.

## Re-baselines of the Metal column

Re-baselined 2026-10-07 after task 036 (environment and projection mapping): the Metal column of race_hud (0.0262),
tt_hud (0.0229), fp_hud (0.0232), zone_hud (0.0122) and zone_change (0.0353). The Vulkan column is unchanged (it keeps
mode 0), and `tools/gerec/metal_check.sh` runs the race A/B with `PURE_NO_TEXMAP=1` so both backends draw mode 0.

Re-baselined again 2026-10-07 after task 037 (mipmaps): race_hud 0.0149, tt_hud 0.0112, fp_hud 0.0116, zone_hud 0.0121.

## The race HUD check (task 031, 2026-10-06)

| Path | Before task 031 | After |
|---|---|---|
| Metal shell and backend (the default) | 11 of 61 (task 028's probe: 12) | 61 of 61 |
| Vulkan shell and backend | 61 of 61 (task 028's probe) | 61 of 61 |
| headless, Metal backend | 61 of 61 (task 028's probe) | 61 of 61 |

## Fast, silent test runs (task 034, 2026-10-06)

Every scripted run used to be held to real time from its first frame, so the 4,450 flips of movies and menus before
MAIN MENU cost about 150 s a run, and a windowed run touched the player's data directory and played its sound. Since
task 034:

Wall times on this Mac (Apple M4 Pro), before (the windowed Metal default, on b5cb152 and 8364dc0) and after:

| Run | Before | After |
|---|---|---|
| `tools/frame_regress.sh` (default) | 7m 9s (Metal window: frontend 72 s, main_menu 159 s, race 197 s) | 9 to 10 s (three runs; headless: 2, 2 and 4 s a route) |
| `tools/frame_regress.sh --shell metal --backend metal` | 7m 9s | 7m 9s (5/5; a window is paced) |
| `tools/frame_regress.sh --shell vulkan --backend vulkan` | 7m 10s to 7m 16s (tasks 028, 031) | 7m 10s (5/5) |
| `tools/campaign_sweep.py single_race vineta_k --no-damage` | 402 s (Metal window) | 197 s (headless, the race paced: 188.6 s of race clock) |
| `tools/campaign_sweep.py time_trial vineta_k --no-damage` (30 flips a second) | 404 s (a windowed run of 2026-10-06 in the main checkout's summary) | 228 s, PASS, the `ref` shot's bar 100% |
| `tools/campaign_sweep.py zone zone_1` | 247 s (likewise) | 75 s, PASS, SHIP DESTROYED read, TOTAL ZONES CLEAR 6 as before |
| `tools/hud_check.sh` (Metal window) / `--shell headless` | about 4 min / about 15 s (task 031) | 229 s / 13 s, 61 of 61 each |
| `main_menu.txt` from boot to MAIN MENU (flip 4380) | about 146 s (paced, 30 flips a second) | 1.8 to 2.05 s (three runs) headless unpaced |
| the NEW-profile leg: the profile screen (flip 2100) to MAIN MENU | about 76 s | 0.65 s (three runs) |

The NEW-profile leg (name, tag, save question) costs well under the brief's 5 s once the menus are unpaced, so the
routes keep it: a cached profile and a LOAD route would save under a second a run.

## Test hooks (task 051, 2026-10-07)

The proof of no change was a log diff of three headless runs of the Vineta K Single Race route
(`main_menu.txt` + `single_race.txt` without their `shot` lines) to flip 6500, on the Metal backend, each on an empty
memory stick (a `PURE_GAME_DIR` holding links to `game/EBOOT.ELF` and the disc image and an empty `ms0/PSP/SAVEDATA`,
as `tools/frame_regress.sh` makes it), with `--max-lines 400000`:
- the brief's run: `PURE_TEST_UNLOCK_ALL=1 PURE_TEST_NO_DAMAGE=1 PURE_WATCH_GRID=1 PURE_WATCH_SHIP=1
  PURE_WATCH_RAND=1 PURE_TRACE_RAND=1` (8969 lines): identical;
- the rest beside the run-control switches: `PURE_WATCH_MOVIE=1 PURE_WATCH_WORDS=08AB45BC,08B17C18
  PURE_TRACE_CALLS=sceDisplay:0x289D82FE,UtilsForUser:0x37FB5C42 PURE_VFPU_DOT=ppsspp PURE_WATCH_RAND=2
  PURE_TEST_NO_DAMAGE=1 PURE_FRAME_LOG=100 PURE_PACED_FROM=100000` (20398 lines): the same lines, 66 of them in
  another place (below);
- the race clock: `PURE_TEST_RACE_CLOCK=ref/race_clock/vineta_k.txt PURE_TEST_UNLOCK_ALL=1 PURE_WATCH_SHIP=1
  PURE_WATCH_RAND=1 PURE_TRACE_CALLS=sceDisplay:0x289D82FE,ThreadManForUser:0x82BC5777` (14875 lines): identical.

Two things to know when repeating it:
- **The log diff needs `PURE_NO_BUSY_CLOCK=1`.** A headless run's log is deterministic except for the framework's
  busy-time charge (`Kernel::charge_busy_time`): a thread that runs over 100 ms of wall time without a wait has that
  time (up to 250 ms) added to the virtual clock. On a loaded machine a race frame sometimes crosses the line: two of
  the twelve runs made with the charge on, with other workers' games beside them, took a 101 ms (flip 6072 to 6073)
  and a 105 ms (flip 6428 to 6429) step, which changes every later `t=` and, without the race clock's replayed frame
  times, the race. `PURE_NO_BUSY_CLOCK=1` turns the charge off; with it each run gave the same log twice on both builds.
  Beyond that only the framework's wall-clock figures differ between runs (the `[metal]` lines' ms, fps and GPU wait
  counts, the `[run_boot] exit` time), which the diff masks.
- **Two orders moved, the lines did not.** With one install call the start-up lines come in one block after the
  profile's own, so `[pure] PURE_PACED_FROM=N: ...` now comes before the `TEST SWITCH` lines instead of between the
  race clock's and no damage's and the unlock lines, and the `PURE_AUDIO_WAV` capture's `audio capture: mix -> ...`
  line after the unlock lines instead of before them. Within a flip the profile's own lines (`[pure] frame N`,
  `[pure] paced from frame N`) now come before every test hook's line; `[pure] rand calls frame N` and `[pure] words
  frame N` used to come before them (the probes' other lines came after them, as now). No tool reads these lines by
  their order; every effect (each binding, each native function, the GPI answer, the rounding mode) happens at the
  same moment as before.

## The M4 checks (2026-10-05)

| Check | Run | Result |
|---|---|---|
| (a) frontend music | `main_menu.txt`, `--frames 4700` | the game plays no music between the language confirm and the main menu, only movie audio and interface sounds (PPSSPP's `ref/boot-hle.log` creates its only sceAtrac context at about vblank 5400, also at the main menu). Music starts at t=145.5 s (flip ~4370); from 146 s to the end (157.5 s) active 11/11, no clipping. From 15 s: active 0.25, so the brief's `--from 15` check fails |
| (b) loop boundary | `main_menu.txt` plus DOWN/UP on the main menu every 300 flips (left idle, the attract demo starts about 30 s after the music and releases it), `--frames 7700` | the frontend track is 1,764,236 samples (40.0 s) with a whole-track loop (`PURE_TRACE_ATRAC`: `at=1762188 count=2048 next=0` twice); the music repeats bit for bit at +1,764,236 frames, boundaries at 185.49 s and 225.49 s; 146-257.6 s active 111/111, no zero run of 50 ms, no clipping |
| (c) race | `out/race/route.txt` + Cross held 1500 flips from 6100, `--frames 7700` | race 209-232 s: mix, effects (ch1) and music (ch2) each active 23/23, no clipping, 0 underruns on ch1 over the run, no zero run in ch1; effects RMS median 2185 vs music 1106, effects above the music in 22 of 23 s; mix peak 6.3 to 18.4 times the music RMS every second |

Dropouts seen once each, not reproduced: in the first race run the frontend music held 7,547 zero frames (171 ms) at
183.9 s, right after the TRACK SELECTION confirm (flip 5500), and the music then repeated at +1,771,742 frames instead
of +1,764,236, so the zeros were inserted, not skipped; in the idle main-menu run, 8,902 zero frames (202 ms) at
164.1 s. Both runs predate the underrun log. Each run of zeros starts inside a buffer the game submitted (1,792 and
768 frames into a 2944-frame buffer), so at least its start is silence the game handed to sceAudio (its music feed
starved), not a late output call; the reruns logged no underrun on the music channel.

## The SAS reverb check (task 043, 2026-10-07)

| Port | 0-100 ms | 100-200 | 200-300 | 300-400 | 400-500 | 500-1000 ms | Result |
|---|---|---|---|---|---|---|---|
| PPSSPP's dump | 383 | 194 | 116 | 60 | 31 | 16, 8, 4, 2, 1 | |
| patch 0008-sas-reverb (the default) | 487 (1.27) | 234 (1.20) | 131 (1.13) | 63 (1.05) | 35 (1.13) | 18, 9, 5, 2, 1 | PASS |
| `PURE_NO_REVERB=1` | 254 (0.66) | 0 | 0 | 0 | 0 | 0 | FAIL |
| `PURE_SAS_REVERB_SPU_RATE=1` | 607 (1.59) | 416 (2.14) | 358 (3.09) | 267 (4.42) | 211 (6.83) | 158 to 42 | FAIL |

(port/PPSSPP in brackets; the port's held effects end at 558.085 s, 150 ms after START at 557.935 s, PPSSPP's at
480.609 s, 130 ms after 480.479 s.) The first step of the port without the reverb is the last 10 ms of the held
effects' fade; from there it is exact zeros.

## The VFPU dot-product check (task 047, 2026-10-07)

The breakpoints change PPSSPP's AI race a little (the player's ship ends within 1 mm of the reference at 12 s in
every run): every ship's end position against the scorecard's reference race at the same clock, the largest of the
seven AI ships:

| Breakpoints (JIT) | Largest AI offset at 12.1 s |
|---|---|
| one, on code the race never runs (the measure's floor) | 0.055 m |
| four, on integer instructions next to the two task 046 `vdot.t` sites | 0.550 m |
| four, on those two `vdot.t` sites and the instructions after them | 0.560 m |
| 330, on the 195 sampled sites and the instructions after them | 8.040 m |

A breakpoint beside a `vdot` moves the race as much as one on it, so it is the breakpoints' place in the JIT's blocks,
not a different `vdot`, that moves it; each logged row is still one execution's operands and result.

## The two rounding modes (task 047, 2026-10-07)

The check of the corpus rebuild with the rounding of old patch 0020 (now part of patch 0009-vfpu-rounding):

and, for the default mode, the port's results against the hardware model (`vfpu_model.model_fn("c", vfpu_model.HW[1])`)
over `vfpu_model.dot_rows(...)` of `out/vfpu_psp/jit`, which must agree on every row. On 2026-10-07 after the corpus
rebuild: the test mode 100 percent at vdot.t (466447), vdot.q (7506), vtfm3.t (255222), vtfm4.q (59064) and vmmul.q
(384704); the default mode equal to the hardware rule on every one of the same 1172943 dot products. The probe's
harness compiles the header, so the check runs without a game; the vtfm and vmmul sites need the regenerated corpus
(`tools/regen.sh`), since their code is emitted inline.

## The other kinds (task 048, 2026-10-07)

On 2026-10-07 (PPSSPP 1.20.4, JIT): `vcrsp.t` is unfused (both products rounded, then their difference) on all
1592532 result lanes of the two circuits, which the port's test mode gives on 75.9% (Vineta K) and 79.8% (Karbonis);
`vfad` in lane order and `vmscl` one IEEE product on all, which the port gives on all. With the header copy of the
Result of docs/tasks/048 the test mode reproduces every one and the default mode equals the PSP's rule on every one.
The check runs in about 2.5 minutes over every set under `ref/vfpu`.

## The shared runner (task 050, 2026-10-07)

Checked against the tools before the move (task 050's Result): every check of the brief gave the same result; the
old `run_boot.py` and the sweep's old pty reader against `PtyRun` on a stand-in game, in six ways a run ends (frame
exit, deadline, signal, an exit status, a slow writer, a 30,000-line flood), with and without the line cap, gave the
same logs, lines, stdout and codes; `fidelity_audit.py --rescan` of the cached 46-cell matrix gave the same cells and
tables; `pp_lines.py --port` on a grid log gave the same samples.

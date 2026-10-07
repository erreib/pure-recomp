# Frame verification tools (task 002, 2026-10-05)

Every visual check compares a captured frame with a reference frame (a PPSSPP capture in `ref/` or an earlier run)
with a tolerance. The tools are pure Python 3.13 with zlib only (no PIL, no numpy, no venv), so they run in every
worktree and subagent as they are.

## tools/png.py

| Function | Does |
|---|---|
| `read_png(path)` | returns `(width, height, channels, bytes)`, rows top first, channels interleaved (1 grey, 2 grey+alpha, 3 RGB, 4 RGBA). 8-bit non-interlaced only, filter types 0-4, chunk CRCs checked. Anything else (palette, 1/2/4/16-bit, Adam7) raises `ValueError` naming the IHDR fields. |
| `write_png(path, width, height, channels, bytes)` | writes the same layout back, filter type 0 on every row. |
| `read_bmp(path)` | reads the framework's `PURE_SCREENSHOT_DIR` captures (24-bit, bottom-up, BGR) and 32-bit BMPs (BI_RGB, fourth byte dropped; BI_BITFIELDS with byte-aligned masks, alpha kept when the header has an alpha mask), bottom-up or top-down. Same return value as `read_png`. |

The BMP captures can be used directly; no `sips -s format png` step is needed. `read_bmp` on a capture gives the same
pixels as the sips-converted PNG beside it (checked on `out/shots/frame_{60,120,600,1260}`). A 960x544 capture with
Paeth-filtered rows reads in about 0.12 s, a BMP in a few milliseconds.

## tools/imgdiff.py

```
tools/imgdiff.py A B [--tol 24] [--max-frac 0.02] [--mask mask.png] [--region x,y,w,h] [--out diff.png] [--json]
tools/imgdiff.py A [B] --min-variance V [--region x,y,w,h] [--json]
tools/imgdiff.py --selftest
```

A and B are PNG or BMP, recognised by their magic bytes. Alpha is dropped and grey is spread to RGB before
anything is compared.

| Option | Meaning |
|---|---|
| (sizes differ) | both frames are resized to 480x272 by nearest neighbour (source pixel `floor(x * w / 480)`), so a 960x544 capture compares against a 480x272 PPSSPP reference. Frames of the same size are compared at their own size. |
| `--tol T` | a pixel differs when any channel differs by more than T (default 24). |
| `--max-frac F` | PASS (exit 0) when differing / total is at most F (default 0.02), FAIL (exit 1) otherwise. Bad input or unreadable files exit 2. |
| `--mask M` | pixels that are black in M (every channel below 128) are ignored and leave the total. M is resized to the comparison size. |
| `--region x,y,w,h` | in PSP screen pixels (480x272) whatever the frame size; scaled to the frame being measured (x2 on a 960x544 capture). Without `--min-variance` it limits the comparison to that rectangle (combined with `--mask` if both are given). |
| `--min-variance V` | no comparison: PASS when the largest per-channel variance of A inside the region (the whole frame without `--region`) is at least V. A "something is drawn here" check; B may be omitted. |
| `--out D` | writes a PNG at the comparison size: A dimmed to a third, differing pixels pure red. |
| `--json` | prints one JSON object instead of the text line. Compare mode: `result`, `mode`, `width`, `height`, `fraction`, `differing`, `total`, `tol`, `max_frac`, `resized`, `a_size`, `b_size`, `mask`, `region`, `pixel_region`, `out`. Variance mode: `result`, `mode`, `width`, `height`, `region`, `pixel_region`, `variance` (R, G, B), `max_variance`, `min_variance`. |

Examples:
```
tools/imgdiff.py out/shots/frame_900.bmp ref/frontend.png --out out/frontend-diff.png
tools/imgdiff.py out/shots/frame_600.bmp --region 140,100,200,40 --min-variance 100
```

## Self-test

`python3 tools/imgdiff.py --selftest` builds synthetic 480x272 images in a temporary directory and checks: identical
frames give 0.0; the top-left quadrant shifted 7 px gives 0.25 +/- 0.01 (FAIL) and the diff image marks exactly the
differing pixels red; a mask over that quadrant and a region on another quadrant give 0.0; a 960x544 BMP against the
480x272 PNG of the same picture gives 0.0; BMP round trips (24-bit with padded rows, 32-bit top-down, 32-bit V5
bitfields with alpha); PNG rows written with each of the filter types 0-4 at 1 to 4 channels; a 16-bit PNG is
rejected with its IHDR fields; the variance check fails on a flat region and passes on a drawn one; the CLI's
`--json` keys and exit code. It prints PASS and exits 0 in under 2 s (0.15 s on this Mac, about 0.7 s on a first run while Python compiles the modules).

# Frame regression suite (task 020, 2026-10-06)

```
tools/frame_regress.sh [--backend metal|vulkan] [--shell headless|metal|vulkan] [--out DIR] [--only SCENE[,SCENE...]]
                       [--env KEY=VAL ...] [--allow-parallel]
```

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

How the runs are made:
- Each route's input script is written to `<out>/<route>.route.txt`. The route files are joined in order with their
  own `shot` steps dropped. One `FRAME:shot SCENE` step is put first for each scene on that route, so a shot at the
  same frame as a press captures before the press.
- `race_hud` uses the same presses as `~/dev/pure-recomp/out/race/route.txt`, the route that measured it. Those are
  `main_menu.txt` followed by `single_race.txt`. Its Cross hold at 6100 comes after the run ends.
- Each run goes to its last shot plus 30 flips (`--frames`), so 2130, 4730 and 6046.
- Every run starts from an empty memory stick in `<out>/game`, where `EBOOT.ELF` and `disc.iso` are links to
  `game/`. `main_menu.txt` creates and saves a profile, and a profile left on the stick would change the next boot.
  The checkout's `game/ms0` is never touched.
- Outputs go to `<out>`, by default `out/regress`. The suite's files from an earlier run there are removed first.
  - captures: `<out>/shots/<scene>.png` (with the BMP)
  - run logs: `<out>/<route>.log`
  - the runner's stdout: `<out>/<route>.stdout`
  - diff images for failing scenes only: `<out>/<scene>.diff.png`, the capture dimmed with differing pixels in red
- `--backend` (default `metal`) sets `PURE_GE_BACKEND` for the runs, records it in the summary and picks the
  measured column. `--shell` (default `headless` since task 034) sets `PURE_SHELL`: the captures are the backend's
  own 480x272 pictures (unpaced: each route takes seconds), the Metal shell's window or the Vulkan shell's.
- The runs are silent (`PURE_NO_AUDIO=1`, `tools/run_boot.py`) and use the data directory `out/data/frame_regress`
  (settings.ini, the Vulkan pipeline caches), kept between runs, unless the environment sets `PURE_NO_AUDIO` or
  `PURE_DATA_DIR`; the player's `~/Library/Application Support/pure-recomp/PureNative/` is never read or written, so
  a setting changed while playing cannot move a scene. The summary names the data directory.
- One game at a time: the suite refuses to start while another PureNative runs (`pgrep -f build/.*/bin/PureNative`,
  kept when the process is PureNative itself), names it and exits 2, unless `--allow-parallel` is given.
- `--env KEY=VAL` passes extra environment to every run, through `tools/run_boot.py --env`. The summary records it.
- The summary's first lines give the date, the commit (`+changes` when tracked files differ from it), the shell, the
  backend and so the measured column, the extra environment, and each run's exit code, whether it reached its last
  frame, and how long it took. The last line, the verdict, names the shell and the backend again.
- Next to each fraction, the table prints `delta`, the difference from the running backend's measured value, to four
  decimals. If a scene moved by more than 0.03, a line names it. That means something changed, even if the scene still
  passes.

The deliberate regression (2026-10-06, the Vulkan path): `tools/frame_regress.sh --shell vulkan --backend vulkan
--only race_hud --env PURE_NO_STENCIL_BUFFER=1 --out out/regress-nostencil` turns off the stencil attachment of patch
0006 (a Vulkan backend switch; the Metal backend does not read it). That removes the ship shadows, and the 0004
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

## Re-baselining the limits

Change a limit only for a reason that is understood and written down. A renderer fix that brings a scene closer to
PPSSPP is one. New references are another. Never raise a limit to get a regression through.

1. Run the suite three times on the change, each with its own output: `--out out/regress-1`, `-2`, `-3`. Use `--only`
   for the scenes concerned. Three runs show the spread, which matters for `race_hud` because of the AI grid.
2. Look at each capture and its diff (`tools/imgdiff.py CAPTURE REF --tol T --out diff.png`). Confirm the scene
   shows the same moment as the reference. If a route's timing moved, fix the frame column first.
3. In the script's `SCENES` table, set the running backend's measured column to the typical value of the runs, to
   three decimals (four on the Metal path, whose fractions are near zero). Set `limit` about 0.015 to 0.02 above the
   largest run of either backend, rounded to a hundredth. Today's limits follow that rule on the Vulkan path, the
   larger of the two: lang and profile 0.054 to 0.07, title 0.030 and main_menu 0.033 to 0.05, and race_hud's largest
   run 0.086 to 0.10.
4. Update the comment beside the row with the task and the date, and update the table above. The commit says why
   the number moved. A change to one backend moves only that backend's column; run the other path to show its column
   still holds.

If the references themselves are regenerated (`ref/README.md`, "Regenerate"), check the new SHA-256 values against
that README. New references mean a new baseline for every scene, following the steps above.

## The race HUD check (task 031, 2026-10-06)

```
tools/hud_check.sh [--shell metal|vulkan|headless] [--backend NAME] [--out DIR] [--env KEY=VAL ...]
```

Runs beside the suite on every renderer or shell change, on both paths. The suite's `race_hud` is flip 6016, before
the race clock starts, and a frame there usually has its HUD even when the race's frames do not: in task 028 the
Metal shell's window showed the race without its HUD in 49 of 61 probe shots while the suite passed (the shell
sampled the backend's target from a command queue of its own; docs/metal-backend.md, "One command queue"). This
check covers the race itself.

- The route: `main_menu.txt` + `single_race.txt` (Vineta K, Cross held from flip 6100, no steering), their own `shot`
  steps dropped, on an empty memory stick (`<out>/game`), with a `shot` every 25 flips from 6200 to 7700: 61 shots,
  the race starting at about 6250. The run ends at flip 7710.
- `tools/hud_check.py` reads each shot for the HUD's two yellow labels, in PSP pixels scaled to the shot's size: the
  CURRENT label (x 2, y 2, 52 x 10, the lap clock's) and the LAP label (x 2, y 232, 26 x 10). A pixel is yellow
  when red > 180, green > 130 and blue < 90 (task 028's probe's thresholds). A shot has the HUD when both labels have
  yellow pixels.
- It prints the shots as `FLIP:H` (both labels), `h` (one) or `-` (none), then `hud_check: N of M shots have the
  HUD`, and exits 0 when all 61 shots were taken and have it. `<out>/summary.txt` holds the yellow counts per label.
- `--shell metal` (the default, kept by task 034: the check tests the window) checks the Metal shell's window
  shots, about 4 minutes paced to real time; `--shell vulkan` the Vulkan shell's, with the Vulkan backend; `--shell
  headless` the Metal backend's own 480x272 captures (`capture_frame`), unpaced, about 15 s. The run is silent and
  uses the data directory `out/data/hud_check` (task 034). `--backend` names another backend. Outputs go to `--out`,
  by default `out/hud/<shell>` (the route, the run's log, the shots and the summary), removed first.

| Path | Before task 031 | After |
|---|---|---|
| Metal shell and backend (the default) | 11 of 61 (task 028's probe: 12) | 61 of 61 |
| Vulkan shell and backend | 61 of 61 (task 028's probe) | 61 of 61 |
| headless, Metal backend | 61 of 61 (task 028's probe) | 61 of 61 |

# Fast, silent test runs (task 034, 2026-10-06)

Every scripted run used to be held to real time from its first frame, so the 4,450 flips of movies and menus before
MAIN MENU cost about 150 s a run, and a windowed run touched the player's data directory and played its sound. Since
task 034:

| Tool | Shell by default | Pacing | Sound | Data directory |
|---|---|---|---|---|
| `tools/frame_regress.sh` | headless, Metal backend | unpaced (the headless shell) | off | `out/data/frame_regress` |
| `tools/campaign_sweep.py` | headless, Metal backend | `PURE_PACED_FROM=<the mode's Cross-hold flip>`: menus unpaced, the race paced | off; `--sound` turns it on and paces the whole run | `out/data/campaign_sweep` |
| `tools/hud_check.sh` | the Metal window (it tests the window) | paced (the window) | off | `out/data/hud_check` |
| `tools/save_roundtrip.sh` | the Metal window | paced | off | `out/data/save_roundtrip` |
| `tools/run_boot.py` | headless unless `--window`, `--shell`, `--script` or `--shots` | the shell's | off; `--sound` | `out/data/run_boot` (`--data-dir`) |

- `PURE_PACED_FROM=N` (`src/profile/pure_profile.cpp`): the kernel runs unpaced from start-up until flip N and is
  held to real time from flip N on, in any shell (patch 0011's `Kernel::set_paced`, set every flip). Headless, the
  menus take seconds and the race keeps real time. In a window the shell still presents at the display's rate (the
  Metal shell waits for a drawable at vsync), so there the menus go at most at the display's rate instead of 30
  flips a second. `0` paces from the start in any shell; unset leaves it to the shell.
- Sound: `PURE_NO_AUDIO=1` unless `--sound`, or the environment sets `PURE_NO_AUDIO`, or sets `PURE_AUDIO_WAV` for
  a run with a window. It turns off the audio device only: the game's sceAudio calls still run on the virtual clock,
  so the `PURE_AUDIO_WAV` capture works without the device (checked: `main_menu.txt` headless with
  `PURE_NO_AUDIO=1`, the music channel from t=145.48 s, as in check (a) above, `wavstats.py --from 146` active
  12/12, no clipping).
- Data directory: `PURE_DATA_DIR=out/data/<tool>` unless the environment names one, made on first use with a
  settings.ini holding `ui.menu_hint_seen=1` (the menu hint would sit over a window's first 12 s) and kept between
  runs, so pipeline caches persist. The game comes from `PURE_GAME_DIR` as before (`game/`, or the suite's and the
  sweep's own memory sticks). A suite and a sweep cell left the player's directory's mtimes unchanged.
- One game at a time: the suite and the sweep refuse to start while another PureNative runs (task 032 saw a headless
  recording beside a windowed cell delay the cell's boot and break its menu route), naming the process, unless
  `--allow-parallel` is given. No tool passes it on its own; the headless suite's own results do not depend on timing
  (unpaced, flip-indexed), so it is the run that can take `--allow-parallel` safely, while a sweep cell (its race
  paced and steered closed loop) and the window paths should not. `run_boot.py`, `hud_check.sh` and
  `save_roundtrip.sh` do not check.

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

## Which path for which change

| Change | Run before merging |
|---|---|
| tools, routes, the profile's probes, HLE outside the GE | `tools/frame_regress.sh` (headless, seconds) |
| the Metal backend (`src/gpu/`), shaders, the GE side of the HLE, a vendor patch under the GE | `tools/frame_regress.sh` while working; before merging `--shell metal --backend metal` and `--shell vulkan --backend vulkan` (D-008: both paths) and `tools/hud_check.sh` |
| the Metal shell (`src/host/metal_shell.mm`), presenting, the window, the interface | `--shell metal --backend metal` and `tools/hud_check.sh`: the headless default never draws through a shell |
| the Vulkan backend or shell (vendor renderer patches) | `--shell vulkan --backend vulkan` and `tools/hud_check.sh --shell vulkan` |
| pacing, the kernel's clock, the input script, the follower | the headless suite, one window path (`--shell metal`), and a sweep cell (`campaign_sweep.py single_race vineta_k --no-damage`) |

# Audio (task 013, 2026-10-05)

## PURE_AUDIO_WAV

`PURE_AUDIO_WAV=<file>` (src/hle/audio_capture.cpp) wraps the bound `sceAudioOutputPannedBlocking`,
`sceAudioOutputBlocking` and `sceAudioOutputPanned` and writes what the game submits: each buffer as stereo 16-bit
44.1 kHz with the call's volumes applied the way the sink applies them (`sample * min(volume, 0x8000) >> 15`), to
`<file>.ch<N>.wav` per channel and the clipped sum to `<file>`. It also follows `sceAudioChReserve`,
`sceAudioSetChannelDataLen` and `sceAudioChangeChannelConfig`, because the frame count of an output call is the
channel's data length and format bit 0x10 makes it mono. Every file is on the kernel's virtual clock, sample 0 at
time 0: a buffer starts where the channel's previous one ended, or at the call's virtual time when it came late, and
the gap is zeros. A gap under 2 s on a playing channel is logged as an underrun
(`[pure] audio capture: channel N underrun of F frames (M ms) at t=US`), and the exit line counts them per channel.
The headers are rewritten after every write, so a killed run still leaves readable files.

What the channels are in this game (all stereo):

| Channel | Frames per call | Carries |
|---|---|---|
| 1 | 768 | the sceSas mix: interface sounds, engine, weapons, speech |
| 2 | 2944 | music (sceAtrac): the frontend loop from the main menu, the race tracks |
| 3 | 2048 | movie audio (sceMpeg): the clip after the language confirm, the intro movie |

The capture is the sink's input bit for bit: on the loop run below, 16-frame windows of the capture at 146.5 s and
175.5 s occur exactly in the framework's `PURE_AUDIO_DUMP` of the same run, 0.816 s earlier (the sink drops the
silence a fast load produces), and the total energy of the two files agrees within 0.3%.

Times: the frontend flips at 30 a second (two vblanks), so flip N of a route is at about N/30 s of virtual time
there (the language confirm at flip 700 is at ~23 s); a race flips at 60.

## tools/wavstats.py

```
tools/wavstats.py <wav> [--from S] [--to S] [--floor RMS] [--gap-ms G] [--min-active-frac F] [--max-clip-frac C] [--quiet]
```

One row per second (RMS and peak over both sides, clipped samples, `silent` below the floor), then the window, the
silent seconds, the longest silent run, the active fraction (whole seconds with RMS above `--floor`, default 100,
about -50 dBFS) and the clipping fraction (samples at -32768 or 32767). A dropout too short to silence a whole
second shows in the zero runs: every stretch of at least `--gap-ms` (default 50) where all samples are exactly 0, not
touching either end of the window. They are information only (between interface sounds they are normal, inside
music they are dropouts). With `--min-active-frac` and/or
`--max-clip-frac` the last line is PASS (exit 0) or FAIL (exit 1); without either it is INFO. Pure Python
(`array` and `math.sumprod`), about a second per minute of audio.

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

## tools/audio_compare.py: the port against PPSSPP (task 041, 2026-10-07)

```
tools/audio_compare.py A.wav B.wav [--from S] [--from-b S] [--seconds N] [--floor RMS] [--block-ms MS] [--top N]
                       [--quiet] [--detail S:E]
tools/audio_compare.py A.wav B.wav --locate T:LEN:FROM:TO
tools/audio_compare.py --selftest
```

Two WAVs side by side, typically PPSSPP's audio dump (`tools/ppsspp/ppsspp_ctl.py run --dump-audio`, docs/ppsspp.md)
and the port's `PURE_AUDIO_WAV` capture of the same route. Each file has its own window start (`--from` for A,
`--from-b` for B), since the two reach a scene at different times. Per whole second: each file's RMS, peak and
clipped samples, `-` after a silent one (RMS at or under `--floor`, 100 as in `wavstats.py`), `<>` where only one is
active; then each file's active seconds, peak (and dBFS), clipped samples and fraction, and its `--top` longest
silences, runs of 10 ms blocks at or under the floor (`all zero` when every sample is 0). `--detail S:E` adds 100 ms
rows for a stretch of the window, the sample-level view of a gap.

PPSSPP's dump is the mix only, and in a race the effects are louder than the music, so a music gap does not show in
the mix's level. `--locate T:LEN:FROM:TO` finds B's stretch from T to T+LEN inside A between FROM and TO by normalised
cross-correlation (8 times decimated, then refined at the full rate) and prints the time in A, the offset and the
correlation: the port's music channel (`<file>.ch2.wav`) found in PPSSPP's mix at 0.3 to 0.7. The same offset at two
times means the two played the same samples in between; a different offset after a track change is the difference
in the switch, to the sample. A 2 s template takes about half a second per second searched.

`--selftest` (task 041's Verify) writes WAVs with known gaps, clipping and a hidden stretch and checks the figures,
PASS or FAIL. The comparisons of differences 7 to 9, and the routes on both sides, are in docs/fidelity.md
("Differences 7 to 9"). Two things to know when repeating them: the game picks the attract demo's tracks itself,
differently from run to run, so demos compare by their figures rather than sample for sample; and a dump of a race
includes PPSSPP's SAS reverb, which the port models since task 043 (patch 0018; before it, PPSSPP's idle race mix had
about 1.4% more level).

## The SAS reverb check (task 043, 2026-10-07)

```
tools/sas_reverb_check.sh [--out DIR] [--env KEY=VAL ...] [--allow-parallel]
```

Plays the Free Play pause route headless and unpaced with `PURE_AUDIO_WAV` (about 20 s; the run is the port's side of
task 041's Free Play idle: `main_menu.txt` and `free_play.txt` without its Cross hold, so the ship idles on Vineta
K's grid, START at flip 16700, to flip 16800, on an empty memory stick in `<out>/game`) and compares the sound after
the pause with PPSSPP's dump of the same route, `ref/audio/free_play_pause.wav` (ref/README.md: the command, about 8
minutes, and its SHA-256; START at vblank 28800). At the pause the game stops the music, holds the effects at one
level for 70 to 150 ms, then keys them off; what sounds after that is the reverb's tail. In each mix the tail starts
at the first 10 ms block after START whose RMS is under 0.6 of the median of the five blocks before it, once those
five are all under 0.7 of the median level of the 0.5 s before START (the music has stopped, so the drop is the
held effects' end, not the music's). START's time: PPSSPP's from its vblank timing, the port's from the virtual time
of the first sceSas call the run logs after the script's START (it traces `__sceSasRevEVOL`, which the race calls
every frame). It prints both starts and the RMS of ten 100 ms steps from there, and checks the first five: PASS (exit
0) when each of the port's is non-zero and within a factor of 2 of PPSSPP's, else FAIL (exit 1); exit 2 when the
reference or the build is missing or another PureNative runs (one game at a time; `--allow-parallel` starts
anyway). `<out>` (default `out/sas_reverb`) keeps the route, the log, the WAVs and `summary.txt`. `--env` passes the
A/B switches: `--env PURE_NO_REVERB=1` (the port before task 043) and `--env PURE_SAS_REVERB_SPU_RATE=1` (the SPU's own
22050 Hz) both FAIL.

| Port | 0-100 ms | 100-200 | 200-300 | 300-400 | 400-500 | 500-1000 ms | Result |
|---|---|---|---|---|---|---|---|
| PPSSPP's dump | 383 | 194 | 116 | 60 | 31 | 16, 8, 4, 2, 1 | |
| patch 0018 (the default) | 487 (1.27) | 234 (1.20) | 131 (1.13) | 63 (1.05) | 35 (1.13) | 18, 9, 5, 2, 1 | PASS |
| `PURE_NO_REVERB=1` | 254 (0.66) | 0 | 0 | 0 | 0 | 0 | FAIL |
| `PURE_SAS_REVERB_SPU_RATE=1` | 607 (1.59) | 416 (2.14) | 358 (3.09) | 267 (4.42) | 211 (6.83) | 158 to 42 | FAIL |

(port/PPSSPP in brackets; the port's held effects end at 558.085 s, 150 ms after START at 557.935 s, PPSSPP's at
480.609 s, 130 ms after 480.479 s.) The first step of the port without the reverb is the last 10 ms of the held
effects' fade; from there it is exact zeros.

Re-baselined 2026-10-07 after task 036 (environment and projection mapping): the Metal column of race_hud (0.0262),
tt_hud (0.0229), fp_hud (0.0232), zone_hud (0.0122) and zone_change (0.0353). The Vulkan column is unchanged (it keeps
mode 0), and `tools/gerec/metal_check.sh` runs the race A/B with `PURE_NO_TEXMAP=1` so both backends draw mode 0.

Re-baselined again 2026-10-07 after task 037 (mipmaps): race_hud 0.0149, tt_hud 0.0112, fp_hud 0.0116, zone_hud 0.0121.

## The save interchange check (task 045, 2026-10-07)

```
tools/save_interchange.sh [--port-only]
tools/save_interchange.sh --check FOLDER FILE [PLAIN_OUT]
tools/save_interchange.sh --make-ppsspp-save
```

Checks that saves move both ways between the port and PPSSPP (a PSP's stand-in) now that the port writes them in the
PSP's own format, the save-data utility's no-key mode (patch 0019, docs/savedata.md "The PSP's format"). The port runs
are headless, unpaced and silent on memory sticks of their own under `out/045/<step>/game`; the PPSSPP run is the
driver's, real time, on PPSSPP's own memory stick, which the script leaves as it found it. About 3 minutes when PPSSPP
is free; it waits (at most 20 minutes) while another PPSSPP runs, and never touches another process.

| Step | What runs | Passes when |
|---|---|---|
| (a) PPSSPP to port | PPSSPP's NAME0000 (`ref/saves/ppsspp/UCUS98612P0000`, ref/README.md) alone on a fresh stick; `profile_load.txt` headless with `PURE_TRACE_SAVEDATA` to flip 3900 | LISTLOAD loads 41570 bytes and logs both hashes verified (mode 1); MAIN MENU within 0.05 of `ref/main_menu.png` at tol 24 (the suite's limit; 0.011); SET NAME's digits vary by 500 or more (1531: NAME0000); the game's PROFILE > SAVE writes P0000 back in mode 1, 41586 bytes, with "User name: NAME0000" in its PARAM.SFO (the game's own profile line), and that save verifies |
| plain | the build before patch 0019's plain save (`ref/saves/port-plain/`), the same route | it loads as a plain save (flag 0) and shows as in (a); the game's save rewrites it in mode 1, and that verifies |
| born | `main_menu.txt` headless on an empty stick, with SET NAME's shot at 2250 | NEW writes P0000 and the first-boot AUTOSAVE writes `PPCD00001DLS001` in mode 1; SET NAME on the empty stick is blank past NAME (variance 0, the control) |
| (b) port to PPSSPP | (a)'s save (the round trip's) copied into PPSSPP's stick; `tools/ppsspp/routes/profile_load.txt` (LOAD, the load dialog, Enter, "Load completed.", Back, MAIN MENU, PROFILE > NEW > YES, SET NAME) | MAIN MENU at 3720 within 0.05 of `ref/main_menu.png`; SET NAME at 4560 varies by 500 or more, equals the port's SET NAME of (a) (tol 24, 0.02) and differs from the empty stick's; the stick holds what it held before |
| (c) side by side | the port's NEW profile and the round trip's against PPSSPP's, the port's `PPCD00001DLS001` against PPSSPP's, each through the framework's `load_save` and hash checks (`out/045/savecheck`, built from `vendor/portablekit`'s save-data sources) | both sides verify (PARAM.SFO's hash, the data file's listed hash, decrypted); PARAM.SFO the same size, keys, formats, lengths and values apart from the bytes that cover the random header (the file's hash in `SAVEDATA_FILE_LIST`, the mode-1 hash at SAVEDATA_PARAMS 0x10); the flag byte equal; ICON0, ICON1, PIC1 and SND0 byte-equal. The decrypted contents are compared and every difference is listed (not a failure) |

What (c) finds (2026-10-07): the two `PROFILE.BIN`s, decrypted, differ in 71 of 41570 bytes, all inside 69 words that
hold addresses in the PSP's user RAM, the port's each 0x200 above PPSSPP's (0x08ECAF10 against 0x08ECAD10 and so on):
the profile keeps pointers into the game's heap verbatim, and the port's heap sits 512 bytes higher at that point. The
game sets them again when it loads a profile (the round trip's save, loaded from PPSSPP's and saved by the port, has
the port's addresses), so they do not matter to a load either way. Nothing else differs: no timestamp, no counter.
`DATA1.BIN` of `PPCD00001DLS001` is identical decrypted; `DATA2.BIN` beside it, which the game writes itself through
sceIo (not the save utility), differs in nearly every byte (it is the game's own, enciphered by it) and is only
reported.

`--port-only` runs everything but (b) and exits 3 (never PASS), for when PPSSPP is busy for long. `--check FOLDER
FILE [PLAIN_OUT]` puts one save folder through the same checks and writes the decrypted file (for any tool that has
to read a profile's contents: the plain bytes of a mode-1 save are not on the stick any more). `--make-ppsspp-save`
remakes PPSSPP's reference save with `frontend.txt` + `save_yes.txt` + `save_dialog.txt` and moves it out of PPSSPP's
stick into `ref/saves/ppsspp/`.

# Verification

The checks this repository runs: what each guards, its pass bar and when it runs. How to call a check and how it
measures are in its script's header; docs/developing.md gives each tool one line. Every visual check compares a
capture with a reference (a PPSSPP capture in `ref/`, or an earlier run) at a tolerance. The fidelity layer's checks
(audio, the reverb, saves with PPSSPP, the scorecard, the VFPU) are reference, not gates: docs/fidelity.md, "The
fidelity layer's checks". What each check measured when it was made, the runs and before-and-after tables:
[docs/history/verification.md](history/verification.md).

| Check | Command | Guards | Pass bar | When it runs |
|---|---|---|---|---|
| frame regression | `tools/frame_regress.sh` | the pictures: 18 scenes against PPSSPP's captures | each scene's fraction of pixels over its tolerance at or below its limit ("Frame regression suite") | headless after every change; the two window paths before merging a renderer or shell change |
| race HUD | `tools/hud_check.sh` | the race's HUD in a window, after the suite's last race scene | 61 of 61 shots show the CURRENT and LAP labels | with the window paths |
| no change | `tools/refactor_check.sh` | a change that only moves code | 0 differing pixels and the same backend counts | a refactor; Metal's Fill and texture detail at scale 1 and one more |
| internal scale | `tools/scale_check.sh [S]` | the Metal backend at scale S against 1 (E3) | each scene reduced within 5% at tol 24 of the 1x capture; the bloom within 10% | the Metal backend's targets, the texture detail, the sprite upscale |
| billboards | `tools/billboard_check.sh` | the advert screen shows the advert, not bars (difference 15) | the screen's vertical luminance step at least the script's threshold | a change to how a target is sampled as a texture |
| Metal against Vulkan | `tools/gerec/metal_check.sh` | the two backends on one recording | the TEAM SELECTION frames and race frame 6016 within 0.02 at tol 24 | the Metal backend's draws and effects |
| ge_replay | `tools/gerec/replay_check.sh` | the replay and the recordings | every step | ge_replay or the record backend |
| flashes (E6) | `tools/flash_check.sh [--race]` | E6, run with it on | 57 two-vblank flips at the fade with 0, none with 1; `--race` no stretch with 1, laps within 5% | E6 and the enhancement hooks |
| frame rate (E4) | `tools/framerate_check.sh [--race]` | E4, run with it on | 29 to 31 against 58 to 61 flips a race-clock second; `--race` both game clocks within 1%, the start within 5% | E4 and the enhancement hooks |
| display rate (E8) | `tools/display_rate_check.sh [--race \| --audio]` | E8, run with it on; `--audio` the sound at the display's rate | the race at 120 x (1 - margin) plus or minus 3, the menus at the PSP's rate; `--audio` at most 1 resync and no second under 95% | E8, the presents, the pacer; `--audio` on both shells on a display above 60 Hz, the window uncovered |
| stutter | `tools/stutter_check.sh` | wall time in a window with sound | at most 1 second in 10 with a frame over 25 ms; the readback at most 2 ms a frame | a GPU wait, write-back or submit (on the rig); E8 with `PURE_DISPLAY_RATE=1` |
| sprite upscale (E7) | `tools/sprite_check.sh`, `tools/sprite_proto_check.py` | E7, run with it on; the scaler against its prototype | each scene within its limit, changed by 1%, the HUD found; the prototype within 2 levels | the sprite upscale |
| texture pack | `tools/sprite_pack.sh --check` | the Vulkan renderer's pack loader with the upscaled art | 40 keys, 10 drawn, both scenes changed and within their limits | the pack's keys or loader |
| texture detail (E5) | `tools/texture_check.sh [--shell vulkan]` | E5, run with it on | each scene within its limit; the three Vineta K scenes changed by 1% with more high-frequency energy | texture sampling or the level rule, on both renderers |
| the 3D view's shape (E2) | `tools/aspect_check.sh [--shell metal]` | E2: Fill in a 21:9 window | the view within 10% of Original between the HUD's bars, the HUD and the main menu within 5%, the outer strips the scene | E2's hook, the window size, the interface fit, Metal's Fill |
| the Esc menu | `tools/menu_check.sh [--shell vulkan]` | the rows against what the game and the shell have | every tab's rows as the script lists them | the menu, a shell, an enhancement; on both shells |
| the performance overlay | `tools/overlay_check.sh` | the Metal shell's overlay | the rectangle changed by 20%, the rest within 0.10 at tol 32, `FPS` read back | the Metal shell's overlay |
| download packs | `tools/dlc_check.sh --packs DIR` | the twelve US packs loaded, raced and imported | twelve opened and imported, three pack races with the HUD | the pack folders, the save transfer, the Download packs section |
| saves | `tools/save_roundtrip.sh` | profiles saved, loaded and listed | all five runs | savedata; the download packs |
| controls | `tools/controls_check.py` | docs/controls.md's tables against the framework's sources | no difference | the bindings or the pad tuning |
| the app | `tools/bundle.sh --check DIR` | the app bundle: signature, libraries, no game data, setup and a run | every check | packing, a release |
| the Windows zip | `tools/bundle_windows.sh --check DIR` | the release folder: files, DLLs, icon, no game data, setup and a run | every check | packing on the rig, a release |
| what goes public | `tools/release_check.sh [--history] [--archive ZIP ...]` | no game file, key or secret in what a push or a release publishes | no finding | before a push or a release |
| the docs | `tools/docs_check.py` | the docs name only what exists; every tools/ file has its line | no finding | a change that moves or renames a file, a tool or a patch |
| a task | `tools/verify_task.sh NNN` | a brief's Verify line | PASS | the worker's run and the merge |

# Frame verification tools (task 002)

The tools are pure Python 3.13 with zlib only (no PIL, no numpy, no venv), so they run in every worktree and subagent
as they are.

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
bitfields with alpha); PNG rows written with each of the filter types 0-4 at 1 to 4 channels; a 16-bit PNG is rejected
with its IHDR fields; the variance check fails on a flat region and passes on a drawn one; the CLI's `--json` keys and
exit code. It prints PASS and exits 0 in under 2 s (0.15 s on this Mac, about 0.7 s on a first run while Python compiles
the modules).

# Frame regression suite

```
tools/frame_regress.sh [--backend metal|vulkan] [--shell headless|metal|vulkan] [--out DIR] [--only SCENE[,SCENE...]]
                       [--window-scenes | --all-scenes] [--paced-from N | --paced] [--env KEY=VAL ...]
                       [--allow-parallel]
```

One command that checks the port still renders the known screens like PPSSPP (task 020; thirteen scenes added by
task 035). By default (task 034) it runs headless on the Metal backend (`--shell headless --backend metal`): no
window, unpaced, the scenes the backend's own 480x272 pictures, about 25 s in all. `--shell metal --backend metal`
runs the same backend in the Metal shell's window (the macOS default for players since D-008) and `--shell vulkan
--backend vulkan` the Vulkan path. In a window (task 069) the suite captures the seven window scenes, the five race
scenes and `title` and `main_menu`, and each run is unpaced until 300 flips before its route's first scene and paced
to real time from there: about 5 minutes a path, where the 18 scenes paced from boot took about 20
([the wall times](history/verification.md#the-window-checks-paced-from-the-scene-task-069-2026-10-10)).
`--all-scenes` runs the 18 in a window (about 8 minutes), `--paced` paces each run from boot as before. Which path
to run for which change: "Which path for which change" below.
The race HUD check ("The race HUD check" below) covers the race after the suite's last race scene. The suite boots
the game once per route (seven routes), captures each scene of the route, and compares each capture with its
reference in `ref/` using `tools/imgdiff.py`. It prints a table with PASS or FAIL per scene and writes the same text
to `<out>/summary.txt`. It exits 0 only when every scene passes, 1 when one fails, and 2 on a usage error, a missing
build, game or reference, or another PureNative running (below).

| Scene | Route (`config/pad_scripts/`) | Frame | Reference (PPSSPP vblank) | Tol | Limit | Vulkan measured | Metal measured |
|---|---|---|---|---|---|---|---|
| `lang` | `frontend.txt` | 690 | `ref/frontend.png` | 24 | 0.07 | 0.054 | 0.0002 |
| `title` | `frontend.txt` | 1750 | `ref/title.png` | 24 | 0.05 | 0.030 | 0.0002 |
| `profile` | `frontend.txt` | 2100 | `ref/profile.png` | 24 | 0.07 | 0.054 | 0.0000 |
| `main_menu` | `main_menu.txt` | 4700 | `ref/main_menu.png` | 24 | 0.05 | 0.033 | 0.0106 |
| `race_hud` | `main_menu.txt` + `single_race.txt` | 6016 | `ref/vineta_k_start.png` (7155) | 32 | 0.10 | 0.047 | 0.0149 |
| `single_player` | `main_menu.txt` + `single_race.txt` | 4765 | `ref/single_player.png` (5850) | 24 | 0.05 | 0.025 | 0.0000 |
| `class_select` | the same | 4990 | `ref/class_select.png` (6050) | 24 | 0.07 | 0.045 | 0.0000 |
| `league_select` | the same | 5185 | `ref/league_select.png` (6250) | 24 | 0.08 | 0.062 | 0.0000 |
| `track_select` | the same | 5390 | `ref/track_select.png` (6450) | 24 | 0.06 | 0.041 | 0.0000 |
| `team_select` | the same | 5600 | `ref/team_select.png` (6690) | 24 | 0.06 | 0.042 | 0.0000 |
| `tt_track_select` | `main_menu.txt` + `time_trial.txt` | 5375 | `ref/tt_track_select.png` (6650) | 24 | 0.06 | 0.040 | 0.0000 |
| `tt_hud` | the same | 5890 | `ref/tt_hud.png` (7340) | 32 | 0.12 | 0.049 | 0.0112 |
| `fp_track_select` | `main_menu.txt` + `free_play.txt` | 5375 | `ref/fp_track_select.png` (6650) | 24 | 0.06 | 0.041 | 0.0000 |
| `fp_hud` | the same | 5890 | `ref/fp_hud.png` (7340) | 32 | 0.11 | 0.048 | 0.0116 |
| `tournament_select` | `main_menu.txt` + `tournament.txt` | 5185 | `ref/tournament_select.png` (6450) | 24 | 0.08 | 0.063 | 0.0000 |
| `zone_track_select` | `main_menu.txt` + `zone.txt` | 4975 | `ref/zone_track_select.png` (6250) | 24 | 0.05 | 0.033 | 0.0000 |
| `zone_hud` | the same | 5260 | `ref/zone_hud.png` (6694) | 32 | 0.09 | 0.045 | 0.0121 |
| `zone_change` | the same | 5679 | `ref/zone_change.png` (7528) | 32 | 0.10 | 0.052 | 0.0353 |

The table lives at the top of the script (`SCENES`), with a measured column per backend and the source of each value
as a comment; the one above is the script's as of 2026-10-10 (task 040's re-baseline of the Metal column; task 056's
viewport fix, 2026-10-08, moved race_hud, tt_hud and fp_hud by under 0.001; the Vulkan column's five race scenes are
task 069's, the median of three runs in the Vulkan window on this Mac, paced from the scene, which scored the same to
the pixel each time, where tasks 056 to 060 had measured them on Windows). A scene's
fraction is the share of pixels that differ by more than Tol in any channel, with both frames at 480x272 (a window's
window capture (960x544 under the Vulkan shell; the Metal shell's drawable, 1920x1088 on a Retina Mac since task 065) is reduced by nearest neighbour; a headless capture is 480x272 already). The scene passes at or below
Limit, which is shared by both backends. The Metal column serves the Metal window and the headless shell alike: the
headless captures equal the Metal window's reduced to 480x272, pixel for pixel (task 034), and task 069's three Metal
window runs paced from the scene scored the headless values on all seven window scenes.

- On the Vulkan path the 2D scenes score 0.025 to 0.063 because of one-pixel edges of lines and glyphs, which the
  2x-to-1x reduction moves. The Metal backend draws at 480x272 and its shell scales by exactly 2x with nearest
  sampling, so no edge moves: the menus match PPSSPP exactly (0 pixels over tol 24), and the few differing pixels of
  `lang` and `title` are blinking cursors. The main menu capture catches the help text partway through typing. Each
  menu frame sits inside a run of identical port frames, away from the blinking cursor's changes.
- The race scenes are the first frame with the HUD fully faded in: `race_hud` (Vineta K, the same game moment as
  PPSSPP's frame 7155, bloom and shadows on), CURRENT, BEST and the bronze time in Time Trial and Free Play, SCORE and
  ZONE in Zone. `zone_change` is Zone 1's first zone change, the first frame with ZONE 2, where the score jumps from
  299 to 800 (with Cross held the ship is at rest against the first barrier by then). The AI ships on `race_hud`'s
  grid are the race's own (docs/fidelity.md, difference 13), so its fraction moves a little from build to build; the
  player is alone in the other race scenes, which repeat to four places. `race_hud` comes before the race clock
  starts; the race itself is the HUD check's.
- Matching a race scene needs care on the PPSSPP side: a capture made during a load moves the race in emulated time
  (`ref/README.md`), so these references come from runs with no capture before the race.

How the runs are made:
- Each route's input script is written to `<out>/<route>.route.txt`. The route files are joined in order with their
  own `shot` steps dropped. One `FRAME:shot SCENE` step is put first for each scene on that route, so a shot at the
  same frame as a press captures before the press.
- `race_hud` uses the same presses as `~/dev/pure-recomp/out/race/route.txt`, the route that measured it. Those are
  `main_menu.txt` followed by `single_race.txt`. Its Cross hold at 6100 comes after the run ends.
- Each run goes to its last shot plus 30 flips (`--frames`): 2130 (`frontend.txt`), 4730 (`main_menu.txt`), 6046
  (Single Race), 5920 (Time Trial and Free Play), 5215 (Tournament) and 5709 (Zone). With the window scenes the
  frontend run ends at 1780 and the Tournament route is not run.
- The scenes (task 069): headless, all 18. In a window on macOS, the window scenes (`WINDOW_SCENES` in the script):
  the five race scenes, and `title` and `main_menu` as a smoke test of the two menu routes. A window capture of a menu
  scene is the backend's own picture scaled by a whole number, pixel for pixel (task 065: 0 of 2088960 pixels on 14
  scenes), so the other eleven menu scenes are left to the headless suite. `--all-scenes` runs the 18 in a window,
  `--window-scenes` the seven headless, and `--only` picks from the whole table either way. On Windows, where nothing
  draws headless, the default stays all 18. The summary's `scenes:` line names the set and the scenes not run, and
  the verdict says `the window scenes` when it is that set.
- The pace (task 069): headless, unpaced. In a window each run sets `PURE_PACED_FROM` to its route's first scene's
  flip minus 300 (`PACE_MARGIN`): the menus before it go at the display's rate, and the last 300 flips before the
  first capture (10 s of 30-fps menus) are paced, so the shell's first presents after the switch are over by then.
  With the window scenes that is 1450 (`frontend.txt`), 4400 (`main_menu.txt`), 5716 (Single Race), 5590 (Time Trial
  and Free Play) and 4960 (Zone); with `--all-scenes` 390, 4400, 4465, 5075, 5075, 4885 (Tournament) and 4675.
  `--paced-from N` sets N for every run, `--paced` sets nothing (the shell's pace: from boot in a window, as before
  task 069), and a `PURE_PACED_FROM` of the caller's (the environment, or `--env`) wins over all three. The summary's
  `pacing:` line and each run's line say which.
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
- One game at a time: the suite refuses to start while another PureNative runs (`tools/run_boot.py`'s
  `other_games()`, from `tools/purelib`), names it and exits 2, unless `--allow-parallel` is given.
- `--env KEY=VAL` passes extra environment to every run, through `tools/run_boot.py --env`. The summary records it.
- The summary's first lines give the date, the commit (`+changes` when tracked files differ from it), the shell, the
  backend and so the measured column, the extra environment, and each run's exit code, whether it reached its last
  frame, and how long it took. The last line, the verdict, names the shell and the backend again.
- Next to each fraction, the table prints `delta`, the difference from the running backend's measured value, to four
  decimals. If a scene moved by more than 0.03, a line names it. That means something changed, even if the scene still
  passes.

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
  shots; `--shell vulkan` the Vulkan shell's, with the Vulkan backend; in a window the run is unpaced until flip 5900,
  300 flips before the first shot, and paced to real time from there (task 069; `PURE_PACED_FROM`, which the caller's
  environment or `--env` overrides): about 80 s
  ([the wall times](history/verification.md#the-window-checks-paced-from-the-scene-task-069-2026-10-10)).
  `--shell headless` checks the Metal backend's own 480x272 captures (`capture_frame`), unpaced, about 15 s. The run
  is silent and uses the data directory `out/data/hud_check` (task 034). `--backend` names another backend. Outputs
  go to `--out`, by default `out/hud/<shell>` (the route, the run's log, the shots and the summary), removed first.

Until task 031 the Metal shell's window showed the race without its HUD in most shots (11 of 61) while the suite
passed: [the race HUD check](history/verification.md#the-race-hud-check-task-031-2026-10-06).

# Fast, silent test runs

Since task 034 no test run is paced to real time before its race, none plays sound, and none touches the player's
data directory:

| Tool | Shell by default | Pacing | Sound | Data directory |
|---|---|---|---|---|
| `tools/frame_regress.sh` | headless, Metal backend | unpaced (the headless shell); in a window `PURE_PACED_FROM=<the route's first scene - 300>` (task 069) | off | `out/data/frame_regress` |
| `tools/campaign_sweep.py` | headless, Metal backend | `PURE_PACED_FROM=<the mode's Cross-hold flip>`: menus unpaced, the race paced | off; `--sound` turns it on and paces the whole run | `out/data/campaign_sweep` |
| `tools/hud_check.sh` | the Metal window (it tests the window) | `PURE_PACED_FROM=5900` in a window: the menus unpaced, the race paced (task 069) | off | `out/data/hud_check` |
| `tools/save_roundtrip.sh` | the Metal window | paced | off | `out/data/save_roundtrip` |
| `tools/run_boot.py` | headless unless `--window`, `--shell`, `--script` or `--shots` | the shell's | off; `--sound` | `out/data/run_boot` (`--data-dir`) |

- `PURE_PACED_FROM=N` (`src/profile/pure_profile.cpp`): the kernel runs unpaced from start-up until flip N and is held
  to real time from flip N on, in any shell (`Kernel::set_paced` of patch 0005-kernel-host-waits-and-pacing, set every
  flip). Headless, the menus take seconds and the race keeps real time. In a window the shell still presents at the
  display's rate (the Metal shell waits for a drawable at vsync), so there the menus go at most at the display's rate
  instead of 30 flips a second. `0` paces from the start in any shell; unset leaves it to the shell.
- Sound: `PURE_NO_AUDIO=1` unless `--sound`, or the environment sets `PURE_NO_AUDIO`, or sets `PURE_AUDIO_WAV` for
  a run with a window. It turns off the audio device only: the game's sceAudio calls still run on the virtual clock,
  so the `PURE_AUDIO_WAV` capture works without the device (checked: `main_menu.txt` headless with
  `PURE_NO_AUDIO=1`, the music channel from t=145.48 s, as in task 013's check (a), `wavstats.py --from 146` active
  12/12, no clipping).
- Data directory: `PURE_DATA_DIR=out/data/<tool>` unless the environment names one, made on first use with a
  settings.ini holding `ui.menu_hint_seen=1` (the menu hint would sit over a window's first 12 s) and kept between
  runs, so pipeline caches persist. The game comes from `PURE_GAME_DIR` as before (`game/`, or the suite's and the
  sweep's own memory sticks). A suite and a sweep cell left the player's directory's mtimes unchanged.
- The enhancements off (task 070, D-016; task 072, D-017; task 073, D-018; task 075, D-019; task 089, D-022): every
  run through `tools/run_boot.py` or `tools/campaign_sweep.py` (so every tool's) has `PURE_SIXTY_FPS=0`,
  `PURE_SMOOTH_FLASHES=0`, `PURE_SPRITE_UPSCALE=0`, `PURE_TEXTURE_DETAIL=0` and `PURE_DISPLAY_RATE=0` unless its caller
  names the variable (`port.original_pacing`, over `port.ENHANCEMENTS_OFF`, called by `port.silence` and
  `port.steady_clock`; a new scratch data directory's settings.ini also says `game.sixty_fps=0`,
  `game.smooth_flashes=0`, `game.sprite_upscale=0`, `game.texture_detail=0` and `game.display_rate=0`), as the Metal
  runs are pinned to internal scale 1: Time Trial, Free Play and Zone and the full-screen flashes keep the PSP's two
  vblanks a frame, the vblank its 59.94 Hz on any display, and the Metal backend draws the menus' and the HUD's bitmaps
  as the PSP's texels and the mipmapped textures at the PSP's levels, so the suites' scenes, the HUD check, the sweep
  and the audit measure the game as it was measured. `tools/gerec/metal_check.sh`, whose replays run outside the
  runner, sets `PURE_SPRITE_UPSCALE=0`, `PURE_TEXTURE_DETAIL=0` and `PURE_DISPLAY_RATE=0` for them itself. `--env PURE_SIXTY_FPS=1`,
  `--env PURE_SMOOTH_FLASHES=1`, `--env PURE_SPRITE_UPSCALE=1` or `--env PURE_TEXTURE_DETAIL=1` (run_boot) or the
  variable in a sweep's environment wins; `tools/framerate_check.sh`, `tools/flash_check.sh`, `tools/sprite_check.sh`,
  `tools/texture_check.sh` and `tools/display_rate_check.sh` are the checks that run them on.
- One game at a time: the suite and the sweep refuse to start while another PureNative runs (task 032 saw a headless
  recording beside a windowed cell delay the cell's boot and break its menu route), naming the process, unless
  `--allow-parallel` is given. No tool passes it on its own; the headless suite's own results do not depend on timing
  (unpaced, flip-indexed), so it is the run that can take `--allow-parallel` safely, while a sweep cell (its race
  paced and steered closed loop) and the window paths should not. `run_boot.py`, `hud_check.sh` and
  `save_roundtrip.sh` do not check; the scorecard waits for the other game instead ("The shared runner").

Since task 050 the Python tools share one runner, `tools/purelib` ("The shared runner"), and every headless run it
starts sets `PURE_NO_BUSY_CLOCK=1`, so a run does not depend on the machine's load. The wall times before and after
task 034: [Fast, silent test runs](history/verification.md#fast-silent-test-runs-task-034-2026-10-06).

The window columns wobble on the race scenes, now and then: a window run's race can be another race than the
headless one, so a window run of `zone_change` has scored anywhere from 0.002 to 0.042 (task 065 measured three runs:
0.0024, 0.0148, 0.0423) and the suite's "moved more than 0.03" line can fire there; the Metal column is the headless
value and is not re-baselined from a window run.

## Which path for which change

| Change | Run before merging |
|---|---|
| tools, routes, the profile's probes, HLE outside the GE | `tools/frame_regress.sh` (headless, seconds) |
| the Metal backend (`src/gpu/`), shaders, the GE side of the HLE, a vendor patch under the GE | `tools/frame_regress.sh` while working; before merging `--shell metal --backend metal` and `--shell vulkan --backend vulkan` (D-008: both paths) and `tools/hud_check.sh`; a change to the shader's texture sampling (`sample_texture` in `shaders/ge.metal`) or the level rule also `tools/texture_check.sh` |
| the Metal shell (`src/host/metal_shell.mm`), presenting, the window, the interface | `--shell metal --backend metal` and `tools/hud_check.sh`: the headless default never draws through a shell; the performance overlay (task 090) also `tools/overlay_check.sh` and `tools/menu_check.sh` on both shells |
| the Vulkan backend or shell (vendor renderer patches) | `--shell vulkan --backend vulkan` and `tools/hud_check.sh --shell vulkan`; a change to `ge.frag`'s texture sampling, the level rule in `submit` or the samplers (patches 0012-vulkan-mipmaps and 0020-vulkan-texture-detail) also `tools/texture_check.sh --shell vulkan`; a change to a GPU wait, a write-back or the frame's submits (patch 0022-vulkan-async-readback) also `tools/stutter_check.sh` on the rig |
| pacing, the kernel's clock, the input script, the follower | the headless suite, one window path (`--shell metal --paced`, paced from boot), and a sweep cell (`campaign_sweep.py single_race vineta_k --no-damage`) |
| an enhancement (`src/profile/enhancements.cpp`, a game option of patch 0019-game-option-rows) | the headless suite (with the option off, as every tool runs), `tools/menu_check.sh` on both shells, and the option's own check with it on (E4: `tools/framerate_check.sh` and `--race`; E6: `tools/flash_check.sh` and `--race`; E7: `tools/sprite_check.sh`; E5: `tools/texture_check.sh` and `--shell vulkan`; E8: `tools/display_rate_check.sh` and `--race`, `--audio` and `--audio --shell vulkan` in the window on a display above 60 Hz, and `PURE_DISPLAY_RATE=1 tools/stutter_check.sh` there) |
| the display rate's period or margin (`display_rate()` in `src/profile/enhancements.cpp`), the presents (the Metal shell's `present_time`, the Vulkan swapchain and its submits), or the pacer's hold to real time | `tools/display_rate_check.sh`, `--race`, and `--audio` on both shells (`--audio` and `--audio --shell vulkan`, the window uncovered) on a display above 60 Hz: the sound at the display's rate is what a miss costs (task 091, docs/timing.md "E8"); the rig's 100 Hz display takes `--audio --shell vulkan` too |
| the 3D view's shape (E2: `src/profile/aspect.cpp`, the projection override and the flip's tangent write; the window-size switch of patch 0027-window-size-switch; the interface fit of patch 0028-vulkan-orthographic-fit) | `tools/aspect_check.sh`, the headless suite (unchanged: at the PSP's shape the hook registers and writes nothing) and `--shell vulkan --backend vulkan` (unchanged for the same reason; with `--env PURE_TRACE_ASPECT=1` the override runs there with the aspect left alone, 7/7 in task 084) |
| the Metal path's Fill (E2, task 086: the targets of the drawable's shape and their two scales in `src/gpu/`, the 2D fit in `draw` and `ge_vertex`, the shell's aspect, `game_aspect` and `PURE_WINDOW_SIZE` in `src/host/metal_shell.mm`) | `tools/aspect_check.sh --shell metal`, `tools/refactor_check.sh` from the commit before at internal scale 1 and at an odd one (`--env PURE_INTERNAL_SCALE=3`: Original must be the old path to the pixel), the headless suite, `--shell metal --backend metal`, `tools/hud_check.sh`, `tools/menu_check.sh` on both shells, `tools/texture_check.sh` and `tools/gerec/metal_check.sh` |
| the texture detail (`sample_texture`'s gradient path in `src/gpu/shaders/ge.metal`, the `levels > 1` block of `draw` in metal_draw.mm, the anisotropic samplers) | `tools/texture_check.sh`, the headless suite, `tools/scale_check.sh` and `tools/sprite_check.sh` (the option off: unchanged), `tools/refactor_check.sh` from the commit before at scale 1 and at `PURE_INTERNAL_SCALE=4` (the Original path to the pixel), and `tools/gerec/metal_check.sh` |
| the sprite upscale (`src/gpu/sprite_upscale.cpp`, its rule in metal_draw.mm) | `tools/sprite_check.sh`, `tools/sprite_proto_check.py` on a `PURE_SPRITE_DUMP` of the main menu route, the headless suite and `tools/scale_check.sh` (the option off: unchanged), and `tools/gerec/metal_check.sh` |
| the texture pack of the upscaled art (the pack entries of `PURE_SPRITE_DUMP` in `src/gpu/metal_textures.mm`; the scaler or its rule, which change the pack's pictures; the Vulkan renderer's pack loader) | `tools/sprite_pack.sh --check` (the pack built from the routes, opened and drawn by the Vulkan renderer in the window, main_menu and race_hud changed and within their limits after the reduction), and once after a change to the keys: the main menu route under the Vulkan renderer with `PURE_TEXTURE_DUMP=DIR`, whose file names must include the pack's keys of the fonts and the art atlases (docs/metal-backend.md "The texture pack"); on Windows `tools/sprite_pack.sh --check --pack DIR` with a pack from the Mac |
| the download packs (the pack folders in `src/profile/pure_profile.cpp`'s list, `tools/purelib/dlc.py`, the pack routes, the save transfer's acceptance of a pack, patch 0021-content-packs: the System tab's Download packs section and Import's file-list rule) | `tools/dlc_check.sh --packs DIR` (the twelve opened, the league and team screens changed, three pack races with the HUD, and since task 078 the menu's Install download packs… driven in a Metal window: twelve found, twelve imported, the section's count before and after, Back up saves copying the profile alone; DIR the player's packs, never in the repository), `tools/menu_check.sh` on both shells (the section's rows), `tools/save_roundtrip.sh`, the headless suite |

The window paths capture the seven window scenes (task 069); a change that could move a menu in a window alone, such
as the shell's scaling, runs `--all-scenes` once.

# Test hooks

The port's test instruments live in `src/profile/test_hooks.{hpp,cpp}`, apart from the game's profile
(`src/profile/pure_profile.cpp`): `PURE_TEST_NO_DAMAGE`, `PURE_TEST_UNLOCK_ALL`, `PURE_TEST_RACE_CLOCK`,
`PURE_VFPU_DOT`, `PURE_WATCH_SHIP`, `PURE_WATCH_GRID`, `PURE_WATCH_RAND`, `PURE_WATCH_WORDS`,
`PURE_TRACE_RAND` and `PURE_TRACE_CALLS`, each in its own function under its README row's text (README.md marks the
row test-only). The profile keeps the run-control switches, `PURE_EXIT_AT_FRAME`, `PURE_FRAME_LOG` and
`PURE_PACED_FROM`: they shape a run (its length, a log line, the pace) and neither change nor watch the game, and
README.md lists them in the main table, not under "Test switches".

The seam is two calls from the profile:
- `test_hooks::install(hle)`, once, from `register_pure_hle`: the switches' start-up lines, the race clock's
  `sceKernelGetSystemTimeWide` wrapper and the `PURE_TRACE_CALLS` wrappers; it returns what `sceKernelGetGPI`
  answers (0 as on retail, 1 under the unlock switch or a race clock file's `unlocked 1`), which the profile binds.
- `test_hooks::flip(rt, frame)`, from the profile's flip counter (the `sceDisplaySetFrameBuf` wrapper) once a flip
  before the game's own: the native `srand()` and `rand()` of the race clock and `PURE_TRACE_RAND` at the first flip,
  `PURE_VFPU_DOT` there too, then the probes and the shield refill.

The bindings keep their order: the flip counter, then `install` (the frame timer, then the call traces), then the
audio capture, then `sceKernelGetGPI`. So `PURE_TRACE_CALLS` still wraps the flip counter
(`tools/scorecard.py` counts flips with `sceDisplay:0x289D82FE`) and the race clock's timer, and a trace of
`sceKernelGetGPI` still finds the framework's binding and is replaced by the profile's answer. A new instrument goes
in `test_hooks.cpp` with its switch read there (`pure_profile.cpp` reads no `TEST_`, `WATCH_` or `TRACE_` switch) and
a test-only row in README.md.

A headless run's log is deterministic, so a change to the hooks is proved by a log diff of the same route before and
after (task 051 diffed three runs of the Vineta K route to flip 6500 with every switch on:
[the proof](history/verification.md#test-hooks-task-051-2026-10-07)). The diff needs `PURE_NO_BUSY_CLOCK=1`: the
framework's busy-time charge (`Kernel::charge_busy_time`) adds a thread's wall time to the virtual clock when it runs
over 100 ms without a wait, which on a loaded machine moves every later `t=` and, without the race clock's replayed
frame times, the race. Beyond that only the framework's wall-clock figures differ between runs (the `[metal]` lines'
ms, fps and GPU wait counts, the `[run_boot] exit` time), which the diff masks.

# The fidelity layer's checks

Reference, not gates: they measure the port against PPSSPP and the PSP, and no merge waits on them. Their sections
moved to docs/fidelity.md, "The fidelity layer's checks", under the same headings (task 092): "Audio" with
`PURE_AUDIO_WAV`, `tools/wavstats.py`, `tools/audio_compare.py` and "The SAS reverb check"; "The save interchange
check"; "The accuracy scorecard"; "The VFPU dot-product check" with "The two rounding modes (D-013)" and "The
other kinds".

# The shared runner: tools/purelib

The Python tools share one copy of the code that runs the game, waits its turn and reads the log: the package
`tools/purelib/` (standard library only). A tool puts `tools/` on `sys.path`, as every tool does for `tools/png.py`,
and imports `from purelib import port, logs`. Every function is documented in one line in the source. No command
line, output or file layout of a tool changed with the move.

| Module | Holds | Used by |
|---|---|---|
| `purelib.port` | `ROOT`, `EXE` (`build/arm64/bin/PureNative`) and `GAME` of the checkout the tool is in (a worktree runs its own build and game), `main_checkout()` for what a worktree never makes (the matrix of task 035); `clean_env` (a run's environment); `scratch_data_dir` and `silence` (task 034); `fresh_stick` (a game directory on an empty memory stick); `other_games`, `refuse` (the guard that will not start), `wait_game`, `wait_until` and `waited` (the guard that waits, and for how long); `PtyRun` (PureNative under a pty, the log folded as it comes); `headless_run` (one run through `tools/run_boot.py`: script, frames, shell, backend, paced-from, extra environment, shots, game and data directories; returns the exit code, the exit frame and the log); `run_tool` (another tool, its output to a file) | `run_boot.py` (`PtyRun`), `campaign_sweep.py` (`PtyRun`, the stick, the refusal), `scorecard.py` (`headless_run`, the wait), `fidelity_audit.py` (its cells' environment, `run_tool`); the bash checks for the guard, the sticks and the data directories: `frame_regress.sh`, `hud_check.sh`, `save_roundtrip.sh`, `save_interchange.sh`, `billboard_check.sh`, `menu_check.sh`, `overlay_check.sh`, `aspect_check.sh`, `flash_check.sh`, `framerate_check.sh`, `display_rate_check.sh`, `stutter_check.sh`, `sprite_pack.sh`, `dlc_check.sh`, `gerec/replay_check.sh` |
| `purelib.logs` | the line formats and their readers: `[pure] ship` (`SHIP_RE`, `SHIP_T_RE`), `player object` (`PLAYER_RE`), `[pure] grid` (`GRID_RE`, `grid_samples`), `[pure] exit at frame` (`exit_frame`), `[hle-stub]` and the start-up list (`STUB_RE`, `UNIMPL_RE`, `unimplemented`, `HALT_RE`), the `[metal]` exit lines (`metal_exit`, `metal_pipelines`, `METAL_FPS_RE`), the GE exit list (`ge_ignored`), the audio capture's underruns and files (`UNDERRUN_RE`, `wav_files`, `wav_channel`) | `run_boot.py`, `campaign_sweep.py`, `scorecard.py`, `fidelity_audit.py`, `pp_lines.py`, `flash_check.sh`, `framerate_check.sh`, `display_rate_check.sh` |
| `purelib.ppsspp` | PPSSPP's shared use: `wait_free` (no PPSSPPSDL running and no profile save on its memory stick, as the scorecard waited), `stick_snapshot` and `stick_restore` (what a run added to the stick moved out, changes reported) | `scorecard.py`, `vfpu_probe.py`, `ai_seed_check.sh` |
| `purelib.dlc` | (task 077) the twelve US download packs: `PACKS` (folder name to title), `read_param_sfo`, `check_pack_folder` (the name, PI.WAD in either case, PARAM.SFO naming the folder), `find_pack_folders` (a pack, a folder of packs, its SAVEDATA or PSP/SAVEDATA), `app_data_dir` | `dlc_install.sh`, `dlc_check.sh` |
| `purelib.conpty` | (task 055) PureNative under a Windows pseudoconsole (ConPTY), so its C runtime sees a console and does not buffer: `ConPty`, `strip_vt` (a console line back to its text), `undo_oem` | `purelib.port` on Windows |

Every headless port run the runner starts has `PURE_NO_BUSY_CLOCK=1` (`port.steady_clock`, from task 051's finding:
the framework's busy-time charge made a headless run depend on the machine's load) unless its environment names the
switch: `run_boot.py` without a window and without `--sound` (so the headless suite, `hud_check.sh --shell headless`
and the scorecard's runs), the sweep's headless cells (the audit's too) and `--record-line`; a window or `--sound`
keeps the charge, as a player has it. Every run, headless or not, has `PURE_SIXTY_FPS=0`, `PURE_SMOOTH_FLASHES=0`,
`PURE_SPRITE_UPSCALE=0`, `PURE_TEXTURE_DETAIL=0` and `PURE_DISPLAY_RATE=0` (`port.original_pacing`) unless its
environment names them: the enhancements E4, E6, E7, E5 and E8 off, so the runs pace the race at the PSP's vblank and
draw the bitmaps and the mipmapped textures as the PSP does ("Fast, silent test runs").

The tools' own rules moved as they were; the module holds each of them, it did not merge them:
- The environment. `run_boot.py` and the sweep start from the whole environment (the sweep keeps `PURE_SHELL`,
  `PURE_GE_BACKEND` and `PURE_PACED_FROM` from it). The audit's cells drop the `PURE_TRACE_*` switches and the four
  switches it or the sweep sets per cell (`clean_env(drop=CELL_DROP)`) and pass the rest to the sweep. The
  scorecard's runs drop every `PURE_*` and `PSPRECOMP_*` switch except `PURE_ROOT` and `PURE_MAIN_CHECKOUT`
  (`clean_env()`).
- One game at a time. The sweep refuses with exit 2 unless `--allow-parallel` (`refuse`, as `frame_regress.sh` does
  in bash); the audit stops when its sweep refused; the scorecard waits (a poll every 10 s, at most an hour a wait,
  then it runs anyway) and reports the time; `run_boot.py` and `hud_check.sh` do not check.
- Exit codes. A game ended by a signal is 128 plus the signal in run_boot's exit line and status, and the negative
  status in the sweep's `[sweep] exit` line (`PtyRun.code(signals=...)`).
- PPSSPP. The scorecard, `vfpu_probe.py` and `ai_seed_check.sh` wait through `wait_free`; `save_interchange.sh` keeps
  its bash wait (PPSSPP only, at most 30 minutes).

How the move was shown to change nothing (task 050): [the shared
runner](history/verification.md#the-shared-runner-task-050-2026-10-07).

# The docs check

```
python3 tools/docs_check.py [--quiet] [FILE.md ...]
```

Task 053 (2026-10-07). Reads README.md, ref/README.md, patches/README.md and every doc under `docs/` except the task
files (`docs/tasks/` is the record: each cites what existed when it was written, and is never rewritten), and checks
that the docs name only what exists:

- **Paths.** Every `tools/...`, `src/...`, `config/...`, `docs/...`, `packaging/...` and `third_party/...` path a doc
  names exists: a file, a directory, a glob that matches, `a.{hpp,cpp}` braces with every member, or a stem
  (`src/tools/ge_replay`); a placeholder in capitals (TRACK, MODE, NAME, FILE, DIR and the like) stands for any
  name. Paths inside code blocks count too. The spike reports about other repositories (docs/codegen-baseline.md,
  docs/research.md) and the dated history files under `docs/history/` are not path-checked.
- **Links.** Every relative Markdown link resolves, and a `#anchor` names a heading of its file (GitHub's rule).
- **Patches.** Every `NNNN-slug` patch name is a file in `patches/`, and a patch cited by the word and a number alone is
  reported: task 052 regrouped the series, so the numbers tasks 001 to 048 used name other patches now.
  A doc cites a patch as `NNNN-slug` with the task that made the change ("patch 0002-ge-state-commands (task 037)"),
  or an old number as "old NNNN" on purpose; a history file may cite an old patch by the name patches/README.md's
  mapping table gives it.
- **Tasks.** Every `docs/tasks/NNN` cited is a task file.
- **Tools.** Every tracked file under `tools/` (`__pycache__` aside) is named in docs/developing.md, by its path or a
  brace form of it, so a new tool gets its row there (task 092).

It prints one line per finding (`FILE:LINE: what`) and a verdict, and exits 0 when there is none, 1 otherwise. Run it
after editing a doc, and in a task that moves or renames a file, a tool or a patch.

## History

[docs/history/verification.md](history/verification.md): each check's first runs and tables (the
suite's first five scenes and the thirteen task 035 added, the re-baselines, the HUD check before
task 031, the wall times of task 034, task 051's log diff, the M4 audio checks, the reverb's steps,
the VFPU measurements, the shared runner's equivalence checks, the window checks' wall times of task 069 and the
checks table as it stood before task 092).

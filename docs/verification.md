# Verification

The checks this repository runs, what each compares and how to read it. Every visual check compares a capture with a
reference (a PPSSPP capture in `ref/`, or an earlier run) at a tolerance; the other checks compare audio, saves,
trajectories and VFPU results with PPSSPP's, or the docs with the tree. What each check measured when it was made,
the runs and before-and-after tables: [docs/history/verification.md](history/verification.md).

| Check | Command | What it guards | Section |
|---|---|---|---|
| frame regression | `tools/frame_regress.sh` | 18 scenes against PPSSPP, headless on Metal in about 25 s; the merge gate for renderer changes | "Frame regression suite" |
| race HUD | `tools/hud_check.sh` | the race's HUD in 61 shots of the Metal window | "The race HUD check" |
| billboards | `tools/billboard_check.sh` | an advert screen shows the advert, not bars (task 063): headless on Metal in about 10 s, or `--backend vulkan --shell vulkan` | docs/fidelity.md, difference 15 |
| Metal against Vulkan | `tools/gerec/metal_check.sh` | the two backends on the TEAM screen and the race, through ge_replay | docs/metal-backend.md, "The 3D check" |
| ge_replay | `tools/gerec/replay_check.sh` | the replay itself | docs/ge-backend.md, section 7 |
| no change | `tools/refactor_check.sh` | a change that moves code changes no pixel and no count | docs/metal-backend.md, "Files" |
| audio | `PURE_AUDIO_WAV`, `tools/wavstats.py`, `tools/audio_compare.py` | the game's sound, against PPSSPP's dump | "Audio" |
| SAS reverb | `tools/sas_reverb_check.sh` | the reverb's tail at a pause against PPSSPP's | "The SAS reverb check" |
| saves | `tools/save_roundtrip.sh`, `tools/save_interchange.sh` | the round trip of profiles; saves both ways with PPSSPP | docs/savedata.md; "The save interchange check" |
| scorecard | `tools/scorecard.py` | how close the port is to the original, six categories | "The accuracy scorecard" |
| trajectories, race clock pinned | `tools/ai_seed_check.sh` | the scorecard's trajectories on PPSSPP's race clock | docs/fidelity.md, difference 13 |
| VFPU rounding | `tools/vfpu_probe.py`, `tools/vfpu_model.py` | the port's VFPU results against PPSSPP's and the PSP's rule | "The VFPU dot-product check" |
| controls | `tools/controls_check.py` | docs/controls.md's tables against the framework's sources | docs/controls.md |
| the app | `tools/bundle.sh --check DIR` | the app bundle: signature, libraries, no game data, setup and a run | docs/release.md |
| the Windows zip | `tools/bundle_windows.sh --check DIR` | the release folder: its files, its DLLs, no game data, setup and a run | docs/release.md, "Windows" |
| the docs | `tools/docs_check.py` | every path, link, patch and task file the docs name exists | "The docs check" |
| a task | `tools/verify_task.sh NNN` | the Verify line of `docs/tasks/NNN-*.md`, PASS or FAIL | CLAUDE.md |

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
                       [--env KEY=VAL ...] [--allow-parallel]
```

One command that checks the port still renders the known screens like PPSSPP (task 020; thirteen scenes added by
task 035). By default (task 034) it runs headless on the Metal backend (`--shell headless --backend metal`): no
window, unpaced, the scenes the backend's own 480x272 pictures, about 25 s in all. `--shell metal --backend metal`
runs the same backend in the Metal shell's window (the macOS default for players since D-008) and `--shell vulkan
--backend vulkan` the Vulkan path; in a window each run is paced to real time: the Vulkan path took 19m 47s for the
18 scenes in task 040, and the Metal window's time for the 18 is unverified (it took 7 minutes for the first five,
as the Vulkan path did). Which path to run for which change: "Which path for which change" below.
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
| `race_hud` | `main_menu.txt` + `single_race.txt` | 6016 | `ref/vineta_k_start.png` (7155) | 32 | 0.10 | 0.067 | 0.0149 |
| `single_player` | `main_menu.txt` + `single_race.txt` | 4765 | `ref/single_player.png` (5850) | 24 | 0.05 | 0.025 | 0.0000 |
| `class_select` | the same | 4990 | `ref/class_select.png` (6050) | 24 | 0.07 | 0.045 | 0.0000 |
| `league_select` | the same | 5185 | `ref/league_select.png` (6250) | 24 | 0.08 | 0.062 | 0.0000 |
| `track_select` | the same | 5390 | `ref/track_select.png` (6450) | 24 | 0.06 | 0.041 | 0.0000 |
| `team_select` | the same | 5600 | `ref/team_select.png` (6690) | 24 | 0.06 | 0.042 | 0.0000 |
| `tt_track_select` | `main_menu.txt` + `time_trial.txt` | 5375 | `ref/tt_track_select.png` (6650) | 24 | 0.06 | 0.040 | 0.0000 |
| `tt_hud` | the same | 5890 | `ref/tt_hud.png` (7340) | 32 | 0.12 | 0.096 | 0.0112 |
| `fp_track_select` | `main_menu.txt` + `free_play.txt` | 5375 | `ref/fp_track_select.png` (6650) | 24 | 0.06 | 0.041 | 0.0000 |
| `fp_hud` | the same | 5890 | `ref/fp_hud.png` (7340) | 32 | 0.11 | 0.095 | 0.0116 |
| `tournament_select` | `main_menu.txt` + `tournament.txt` | 5185 | `ref/tournament_select.png` (6450) | 24 | 0.08 | 0.063 | 0.0000 |
| `zone_track_select` | `main_menu.txt` + `zone.txt` | 4975 | `ref/zone_track_select.png` (6250) | 24 | 0.05 | 0.033 | 0.0000 |
| `zone_hud` | the same | 5260 | `ref/zone_hud.png` (6694) | 32 | 0.09 | 0.065 | 0.0121 |
| `zone_change` | the same | 5679 | `ref/zone_change.png` (7528) | 32 | 0.10 | 0.082 | 0.0353 |

The table lives at the top of the script (`SCENES`), with a measured column per backend and the source of each value
as a comment; the one above is the script's as of 2026-10-07 (task 040's re-baseline of the Metal column; task 056's
viewport fix, 2026-10-08, moved race_hud, tt_hud and fp_hud by under 0.001 and left the Vulkan column as it was). A scene's
fraction is the share of pixels that differ by more than Tol in any channel, with both frames at 480x272 (a window's
960x544 capture is reduced by nearest neighbour; a headless capture is 480x272 already). The scene passes at or below
Limit, which is shared by both backends. The Metal column serves the Metal window and the headless shell alike: the
headless captures equal the Metal window's reduced to 480x272, pixel for pixel (task 034).

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
  (Single Race), 5920 (Time Trial and Free Play), 5215 (Tournament) and 5709 (Zone).
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
  shots, about 4 minutes paced to real time; `--shell vulkan` the Vulkan shell's, with the Vulkan backend; `--shell
  headless` the Metal backend's own 480x272 captures (`capture_frame`), unpaced, about 15 s. The run is silent and
  uses the data directory `out/data/hud_check` (task 034). `--backend` names another backend. Outputs go to `--out`,
  by default `out/hud/<shell>` (the route, the run's log, the shots and the summary), removed first.

Until task 031 the Metal shell's window showed the race without its HUD in most shots (11 of 61) while the suite
passed: [the race HUD check](history/verification.md#the-race-hud-check-task-031-2026-10-06).

# Fast, silent test runs

Since task 034 no test run is paced to real time before its race, none plays sound, and none touches the player's
data directory:

| Tool | Shell by default | Pacing | Sound | Data directory |
|---|---|---|---|---|
| `tools/frame_regress.sh` | headless, Metal backend | unpaced (the headless shell) | off | `out/data/frame_regress` |
| `tools/campaign_sweep.py` | headless, Metal backend | `PURE_PACED_FROM=<the mode's Cross-hold flip>`: menus unpaced, the race paced | off; `--sound` turns it on and paces the whole run | `out/data/campaign_sweep` |
| `tools/hud_check.sh` | the Metal window (it tests the window) | paced (the window) | off | `out/data/hud_check` |
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
- One game at a time: the suite and the sweep refuse to start while another PureNative runs (task 032 saw a headless
  recording beside a windowed cell delay the cell's boot and break its menu route), naming the process, unless
  `--allow-parallel` is given. No tool passes it on its own; the headless suite's own results do not depend on timing
  (unpaced, flip-indexed), so it is the run that can take `--allow-parallel` safely, while a sweep cell (its race
  paced and steered closed loop) and the window paths should not. `run_boot.py`, `hud_check.sh` and
  `save_roundtrip.sh` do not check; the scorecard waits for the other game instead ("The shared runner").

Since task 050 the Python tools share one runner, `tools/purelib` ("The shared runner"), and every headless run it
starts sets `PURE_NO_BUSY_CLOCK=1`, so a run does not depend on the machine's load. The wall times before and after
task 034: [Fast, silent test runs](history/verification.md#fast-silent-test-runs-task-034-2026-10-06).

## Which path for which change

| Change | Run before merging |
|---|---|
| tools, routes, the profile's probes, HLE outside the GE | `tools/frame_regress.sh` (headless, seconds) |
| the Metal backend (`src/gpu/`), shaders, the GE side of the HLE, a vendor patch under the GE | `tools/frame_regress.sh` while working; before merging `--shell metal --backend metal` and `--shell vulkan --backend vulkan` (D-008: both paths) and `tools/hud_check.sh` |
| the Metal shell (`src/host/metal_shell.mm`), presenting, the window, the interface | `--shell metal --backend metal` and `tools/hud_check.sh`: the headless default never draws through a shell |
| the Vulkan backend or shell (vendor renderer patches) | `--shell vulkan --backend vulkan` and `tools/hud_check.sh --shell vulkan` |
| pacing, the kernel's clock, the input script, the follower | the headless suite, one window path (`--shell metal`), and a sweep cell (`campaign_sweep.py single_race vineta_k --no-damage`) |

# Test hooks

The port's test instruments live in `src/profile/test_hooks.{hpp,cpp}`, apart from the game's profile
(`src/profile/pure_profile.cpp`): `PURE_TEST_NO_DAMAGE`, `PURE_TEST_UNLOCK_ALL`, `PURE_TEST_RACE_CLOCK`,
`PURE_VFPU_DOT`, `PURE_WATCH_MOVIE`, `PURE_WATCH_SHIP`, `PURE_WATCH_GRID`, `PURE_WATCH_RAND`, `PURE_WATCH_WORDS`,
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

# Audio

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

The checks of task 013 (the frontend music, its loop, a race's mix; 2026-10-05):
[The M4 checks](history/verification.md#the-m4-checks-2026-10-05).

## tools/audio_compare.py: the port against PPSSPP

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

`--selftest` (task 041's Verify) writes WAVs with known gaps, clipping and a hidden stretch and checks the figures, PASS
or FAIL. The comparisons of differences 7 to 9, and the routes on both sides, are in docs/history/fidelity.md
("Differences 7 to 9"). Two things to know when repeating them: the game picks the attract demo's tracks itself,
differently from run to run, so demos compare by their figures rather than sample for sample; and a dump of a race
includes PPSSPP's SAS reverb, which the port models since task 043 (patch 0008-sas-reverb; before it, PPSSPP's idle race
mix had about 1.4% more level).

## The SAS reverb check

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

On 2026-10-07 the port's five steps were 1.05 to 1.27 of PPSSPP's (PASS); without the reverb the tail is exact zeros
after the first step, and at the SPU's own rate 1.59 to 6.83 times PPSSPP's (both FAIL):
[the table](history/verification.md#the-sas-reverb-check-task-043-2026-10-07).

## The save interchange check

```
tools/save_interchange.sh [--port-only]
tools/save_interchange.sh --check FOLDER FILE [PLAIN_OUT]
tools/save_interchange.sh --make-ppsspp-save
```

Checks that saves move both ways between the port and PPSSPP (a PSP's stand-in) now that the port writes them in the
PSP's own format, the save-data utility's no-key mode (patch 0007-savedata-list-and-no-key-mode, task 045;
docs/savedata.md "The PSP's format"). The port runs are headless, unpaced and silent on memory sticks of their own under
`out/045/<step>/game`; the PPSSPP run is the driver's, real time, on PPSSPP's own memory stick, which the script leaves
as it found it. About 3 minutes when PPSSPP is free; it waits (at most 20 minutes) while another PPSSPP runs, and never
touches another process.

| Step | What runs | Passes when |
|---|---|---|
| (a) PPSSPP to port | PPSSPP's NAME0000 (`ref/saves/ppsspp/UCUS98612P0000`, ref/README.md) alone on a fresh stick; `profile_load.txt` headless with `PURE_TRACE_SAVEDATA` to flip 3900 | LISTLOAD loads 41570 bytes and logs both hashes verified (mode 1); MAIN MENU within 0.05 of `ref/main_menu.png` at tol 24 (the suite's limit; 0.011); SET NAME's digits vary by 500 or more (1531: NAME0000); the game's PROFILE > SAVE writes P0000 back in mode 1, 41586 bytes, with "User name: NAME0000" in its PARAM.SFO (the game's own profile line), and that save verifies |
| plain | the plain save of the build before task 045 (`ref/saves/port-plain/`), the same route | it loads as a plain save (flag 0) and shows as in (a); the game's save rewrites it in mode 1, and that verifies |
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

## The accuracy scorecard

```
tools/scorecard.py [--quick | --full] [--only CATEGORY[,CATEGORY...]] [--out DIR] [--tracks TRACK[,...]]
tools/scorecard.py --refresh-references [CATEGORY] [--tracks TRACK[,...]]
tools/scorecard.py --selftest
```

The standing answer to "how accurate is the port" (D-009): six categories, each row measured on the port headless and
compared with PPSSPP or with the game's own facts, graded `faithful`, `close` or `differs` by a stated threshold.
`docs/scorecard.md` holds the latest `--full` run of this branch, its header the thresholds of every category. The
tool writes `scorecard.json` (every row with its figures) and `scorecard.md` to `--out` (default `out/scorecard`),
with every run's route, log, captures and WAVs under `<out>/runs/`; a `--full` run of every category also rewrites
`docs/scorecard.md`. Exit 0 once the scorecard is written, whatever the grades.

| Mode | Categories | Port runs | Time on this Mac |
|---|---|---|---|
| `--quick` (the default) | pictures, timing (from the matrix's cells), saves, coverage | the suite, three extra race frames, a short race for the load, a profile | about a minute |
| `--full` | all six | also 12 straight-on races (three with `PURE_AUDIO_WAV`), the main menu with `PURE_AUDIO_WAV`, four sweep cells (Single Race, Time Trial and Free Play on Vineta K, Zone 1; races paced) | about 18 minutes |
| `--only CATEGORY,...` | the named ones, with `--full`'s sources (or `--quick`'s beside `--quick`) | | |

Every port run is `tools/run_boot.py --shell headless --backend metal` on an empty memory stick of its own
(`<out>/game`), silent, with the data directory `out/data/scorecard`, and no `PURE_*` switch inherited from the shell;
the suite and the sweep cells run with their own headless defaults. One game at a time: when another task's
PureNative (or PPSSPP, for the references) is running, the tool waits for it and never touches it; the report gives
the time spent waiting beside the wall time.

How each category measures:

- **Pictures.** `tools/frame_regress.sh --out <out>/regress` as it is, its `summary.txt` read for the 18 scenes; then
  the first full-HUD frames of Blue Ridge (flip 6016), Sinucit (6016) and Sebenco Climb (6018, with the unlock
  switch), the sweep's picks after `main_menu.txt` + `single_race.txt`, against `ref/blue_ridge_hud.png`,
  `sinucit_hud.png` and `sebenco_climb_hud.png` at tol 32. Their measured values and limits are in the tool's
  `EXTRA_SCENES`, set by the re-baselining rule above; Sinucit's and Sebenco Climb's compare two states of the weather
  mist (difference 3, task 038), so their fractions stay high whatever the renderer does.
- **Trajectories.** Each circuit's Single Race at Vector by the sweep's route (`main_menu.txt`, `single_race.txt`, the
  picks of `tools/campaign_sweep.py`), `PURE_TEST_UNLOCK_ALL=1` on all twelve, Cross held from flip 6100, no steering,
  `PURE_WATCH_GRID=1`, to flip 7800 (about 25 s of race clock; 10200 on the three audio circuits). PPSSPP's side is the
  same race through the routes of task 035 with Cross held from the first READY frame, its race records sampled as
  `tools/pp_lines.py` samples them (its block and parser), each block read twice and kept only when both reads agree.
  Both sides are cut at each ship's first lap-clock restart; the port's positions, every flip, are interpolated at
  PPSSPP's race clocks. Two PPSSPP runs of Vineta K agree at every common clock, so PPSSPP's AI is repeatable and the
  AI ships get a row per circuit (the worst of the seven). The port's headless runs repeat themselves as well, AI
  included (two runs each of Karbonis and Sinucit: 0 m apart at every common clock), so where the port's AI parts
  from PPSSPP's it is another race, not noise. A player row that differs names the nearest AI ship on each side at
  the clock it first parts (a contact with an AI ship that is somewhere else in the other run).
- **Timing.** Flips per race-clock second: pairs of `[pure] ship` lines on consecutive flips whose clock moved (a
  lap-clock restart counts the new clock; a pause, when the probe prints nothing, does not count), over the matrix's
  cells at Vector in `--quick`, over this run's sweep cells in `--full` (Tournament stays the matrix's: its cell takes
  17 minutes). The stretches: `tools/fidelity_audit.py`'s `scan_log` on the Vineta K race (the matrix's cell or this
  run's) against the summary of `--ppsspp-race vineta_k`. The race load: from the TEAM SELECTION confirm (port flip
  5700, PPSSPP vblank 6700) to the first of the 57 two-vblank flips of the race-start fade, which end where the race's
  one-vblank flips begin, in game time (the port's `PURE_TRACE_CALLS` on `sceDisplaySetFrameBuf`, PPSSPP's flip log);
  graded `accepted (D-011)`.
- **Audio.** The main menu: `main_menu.txt` with L every 600 flips (20 s) from 4800, to flip 6900, against PPSSPP's dump
  of `frontend.txt` + `main_menu_music.txt` (L every 1200 vblanks): the attract demo, which would start 30 s after the
  last new button and play a track the game picks itself, never comes, and L makes no sound there (the port's
  sceSas channel stays silent). `--locate` finds three two-second stretches of the port's mix (4, 24 and 44 s into
  the music) in PPSSPP's dump; the lowest correlation is graded, and the per-second RMS ratio over the aligned 60 s.
  The races: the port's music channel (`.ch2.wav`) located in PPSSPP's mix at five stretches from GO + 10 s, the
  median correlation graded; then the two mixes over 60 s from GO aligned by the best stretch's offset: the share of
  seconds where both or neither are active, and the clipped samples. The AI ships differ in the port, so the effects
  do too; the RMS ratio of the race mixes is reported, not graded.
- **Saves.** `tools/save_roundtrip.sh`'s first run, `main_menu.txt` on an empty stick (NEW, NAME0000, AAA, SAVE PROFILE
  YES), made headless in seconds (the script itself runs five windowed runs in 13 minutes and has no option for one),
  against PPSSPP's save of the same profile (`ref/scorecard/saves/UCUS98612P0000`). Since task 045 (patch
  0007-savedata-list-and-no-key-mode) both write PROFILE.BIN enciphered in the save utility's mode 1, so it is compared
  by size and by its contents, each side decrypted through the framework's own load path with both hashes checked
  (`tools/save_interchange.sh --check`): close when the only differing words hold user-RAM addresses on both sides (the
  profile keeps heap pointers verbatim, task 045's finding; the game sets them again on a load).
- **Coverage.** The cell results of `tools/fidelity_audit.py` from `out/035-wip/fidelity` (this checkout's, else the
  main checkout's, else `out/fidelity`); without them the rows say which command makes them (about 4 hours; the
  scorecard never runs the matrix). The 278 imports by state from `config/imports.csv`, the start-up list of
  unimplemented imports and the `[hle-stub]` and `UNVERIFIED` lines of the matrix's logs (the brief names an
  `hle_coverage.csv` under `config/`, which does not exist). The GE commands still ignored from this run's exit list.
  Functions entered: not measured (no cheap entry count exists).

`--refresh-references [CATEGORY]` (trajectories, audio, saves or timing; all four without one) takes the PPSSPP side
into `ref/scorecard/`, one PPSSPP at a time, waiting while PPSSPP runs for another task or while its memory stick
holds a profile save, and lists every file with its SHA-256 in `ref/scorecard/manifest.json` and `ref/README.md`
(the commands are there too). A row whose reference is missing says `no reference` and names the command; it does not
fail the run. `--selftest` checks every grader, the parsers and the report on synthetic inputs (PASS in about a
second).

## The VFPU dot-product check

```
tools/vfpu_probe.py cover [--track T] [--seconds S]          # once: which sites a race runs (ref/vfpu/coverage.csv)
tools/vfpu_probe.py sample --out ref/vfpu/jit --sites all --cap 5000 --seconds 12
tools/vfpu_probe.py sample --out ref/vfpu/interp --cpu-core 0 --cap 1500 --seconds 12 --sites ADDR,...
tools/vfpu_probe.py port ref/vfpu/jit                        # the port's results for the same operands
python3 tools/vfpu_model.py --selftest && python3 tools/vfpu_model.py --check ref/vfpu
```

The check behind difference 13's last step (docs/history/fidelity.md, "The dot-product rule, measured"): PPSSPP's VFPU
results at the game's own instructions, and a model that reproduces every one of them.

**The sites.** `scan` decodes EBOOT.ELF and keeps the instructions the corpus has code for (its `L_XXXXXXXX` labels,
so decoded data is left out): 711 sites of `vdot`, `vtfm`, `vmmul`, `vrcp`, `vrsq`, `vsqrt`, `vsin` and `vcos`
(`vhdp` decodes only in data, which the corpus has no code for; `vexp2`, `vlog2` and `vasin` do not occur at all).
`cover` found 205 of them executed from READY to 3.2 s of race clock on Vineta K, 1.4 million hits; `vsin` and `vcos`
(two sites each) were not among them.

**The PPSSPP side.** The route is the scorecard's reference route (`frontend.txt`, `vineta_k_start.txt`, Cross held
from READY), so the race is the one the scorecard's references and the race clocks of task 046 come from. Log-only
breakpoints (`cpu.breakpoint.add` with `log` and a `logFormat`; PPSSPP's expressions take the scalar names S000 to
S733) sit on each site, logging its source lanes, and on the next instruction, logging the destination lanes; a pair
counts only when the two lines are consecutive in PPSSPP's log. Three things the debugger taught:
- A breakpoint added while the CPU runs never fires in a block the JIT has already compiled (the first coverage run,
  armed at READY, saw 47 sites and none of the ship update's). The probe adds every breakpoint at boot with the
  condition `usec >= READY` (and an end for the hot sites), which keeps them silent through the menus.
- `cpu.getAllRegs` offers the GPRs, the FPU and the 128 VFPU scalars, not the prefix registers; the probe reads the
  `vpfx` words in front of each site from the code (`sites.json`). None of the sampled sites has a prefix.
- With the interpreter (`--cpu-core 0`) a log-only breakpoint stops the CPU like any other; the probe then reads the
  registers with `cpu.getAllRegs` at each stop and resumes (about 90 stops a second, so that run samples 27 sites).

The breakpoints change PPSSPP's AI race a little (the player's ship ends within 1 mm of the reference at 12 s in every
run; the AI ships up to 8 m with 330 breakpoints), by their place in the JIT's blocks, not by the instruction they
sit on; each logged row is still one execution's operands and result. The measurements:
[the breakpoints](history/verification.md#the-vfpu-dot-product-check-task-047-2026-10-07).

**The port side.** `port` builds, for every sampled site, the corpus's own block of that instruction
(`generated/generated_unit_*.cpp`, between its label and its `goto`) into one program with the corpus's flags
(`/usr/bin/clang++ -O2 -std=gnu++20 -arch arm64`), loads PPSSPP's operands into an `AllegrexContext`, runs it and
writes the destination lanes: the port's results on PPSSPP's operands, without a port run. The model's emulation of
the port (model b) reproduces every one of them.

**The model.** `--check` takes each sample set under `ref/vfpu`, the rule of the PPSSPP core that made it
(`vfpu_model.py` `RULES`) and the instruction, and counts the dot products the rule reproduces; it exits 0 when it is
all of them, else prints up to 20 failing rows a group (operands, PPSSPP's result, the model's and the port's). It
then reports the transcendental instructions. About 10 s. `--report` runs every candidate model over every set
(about 70 s for the JIT set). The samples are git-ignored; ref/README.md has the commands and their hashes.

### The two rounding modes (D-013)

The port's generated code rounds dot products as a real PSP does by default and as PPSSPP's JIT does under the test
mode (`PURE_VFPU_DOT=ppsspp`, or `PURE_TEST_RACE_CLOCK`, which implies it). Both are checked against the recorded
samples by recomputing the port side with the probe's harness under each mode:

```sh
for mode in ppsspp psp; do
  rm -rf out/vfpu_$mode && mkdir -p out/vfpu_$mode && cp -R ref/vfpu/jit out/vfpu_$mode/jit && cp ref/vfpu/coverage.* out/vfpu_$mode/
  PURE_VFPU_DOT=$mode python3 tools/vfpu_probe.py port out/vfpu_$mode/jit
done
python3 tools/vfpu_model.py --report out/vfpu_ppsspp     # the "port" row must read 100% in every column
```

and, for the default mode, the port's results against the hardware model (`vfpu_model.model_fn("c", vfpu_model.HW[1])`)
over `vfpu_model.dot_rows(...)` of `out/vfpu_psp/jit`, which must agree on every row. The probe's harness compiles
the header, so the check runs without a game; the vtfm and vmmul sites need the regenerated corpus (`tools/regen.sh`),
since their code is emitted inline. The figures of the corpus rebuild of 2026-10-07:
[the two rounding modes](history/verification.md#the-two-rounding-modes-task-047-2026-10-07).

### The other kinds

```sh
P=/opt/homebrew/bin/python3
K=vcrs,vcrsp,vqmul,vfad,vavg,vrot,vmscl
for t in vineta_k karbonis; do
  $P tools/vfpu_probe.py cover --track $t --kinds $K --seconds 13 --out ref/vfpu/jit/048_$t        # 2.5 min each
  $P tools/vfpu_probe.py sample --track $t --out ref/vfpu/jit/048_$t --sites all --cap 0 --seconds 13   # 4 min each
  $P tools/vfpu_probe.py port ref/vfpu/jit/048_$t --modes ppsspp,psp
done
python3 tools/vfpu_model.py --check ref/vfpu          # every set: the dot forms, the other kinds, both modes
python3 tools/vfpu_model.py --diff ref/vfpu/jit/048_karbonis --limit 20    # where the test mode differs, in time order
```

The same check as the dot products' for the kinds beside them: `vcrs.t`, `vcrsp.t`, `vqmul.q`
(`execute_vfpu_cross_quat` and the codegen's inline `vcrs`), `vfad`, `vavg` (`execute_vfpu_horizontal`), `vrot` and
`vmscl`. Each result lane is one problem (a cross product's three lanes, a horizontal sum's one, a vmscl's sixteen
elements), with its own candidate models in `vfpu_model.kind_models` and PPSSPP's measured rule in `RULES_048`. The
game's code has only `vcrsp.t`, `vfad`, `vrot` and `vmscl`; `vcrs.t`, `vqmul.q` and `vavg` decode only in data, so
their models are checked against pspautotests' `vector.expected` alone (`--selftest`), and no `vrot` ran from READY to
13 s on either circuit.

What is new in the tools:
- `sample --cap 0` logs every execution from READY (these kinds run rarely enough: 0.9 million rows a circuit), and
  `--window FROM,TO` logs every execution of every listed site between two race clocks and nothing else, placed on
  PPSSPP's emulated time by the player's samples of the scorecard's reference race (`--sites` may then name sites
  that never run; they give empty files). Karbonis' dot and transcendental window (`048_karbonis_dot`, 711 sites, 6.0 to
  7.0 s) was taken with `--sites` set to every dot and transcendental site of `scan`.
- `port --modes ppsspp,psp` runs the harness under each rounding mode of patch 0009-vfpu-rounding and writes
  `<ADDR>.port.<mode>.csv`; `--check` then prints, under every rule line, the test mode against PPSSPP and the default
  mode against the PSP's rule (`hw_of`: the hardware dot product, or `HW_048`'s model). The harness now compiles with
  `-ffp-contract=off`, as the corpus does since task 047.
- A header experiment never touches `vendor/`: copy `vendor/portablekit/include` to `out/048/candidate/include`, edit it
  there, then `port DIR --modes ppsspp,psp --tag candidate --include out/048/candidate/include` and `vfpu_model.py
  --check DIR --tag candidate`. The corpus before task 047's rounding is the same with that rounding's header hunk (old
  patch 0020, the first part of `patches/0009-vfpu-rounding.patch`) reversed in the copy and `--fp-contract on --tag
  pre0020`.
- `vfpu_model.py --diff DIR [--which ppsspp]` lists, per site and then in time order, every sampled result where the
  port differs from PPSSPP: the candidates a divergence can start from.

What the samples of the other kinds showed (2026-10-07): [The other
kinds](history/verification.md#the-other-kinds-task-048-2026-10-07).

# The shared runner: tools/purelib

The Python tools share one copy of the code that runs the game, waits its turn and reads the log: the package
`tools/purelib/` (standard library only). A tool puts `tools/` on `sys.path`, as every tool does for `tools/png.py`,
and imports `from purelib import port, logs`. Every function is documented in one line in the source. No command
line, output or file layout of a tool changed with the move.

| Module | Holds | Used by |
|---|---|---|
| `purelib.port` | `ROOT`, `EXE` (`build/arm64/bin/PureNative`) and `GAME` of the checkout the tool is in (a worktree runs its own build and game), `main_checkout()` for what a worktree never makes (the matrix of task 035); `clean_env` (a run's environment); `scratch_data_dir` and `silence` (task 034); `fresh_stick` (a game directory on an empty memory stick); `other_games`, `refuse` (the guard that will not start), `wait_game`, `wait_until` and `waited` (the guard that waits, and for how long); `PtyRun` (PureNative under a pty, the log folded as it comes); `headless_run` (one run through `tools/run_boot.py`: script, frames, shell, backend, paced-from, extra environment, shots, game and data directories; returns the exit code, the exit frame and the log); `run_tool` (another tool, its output to a file) | `run_boot.py` (`PtyRun`), `campaign_sweep.py` (`PtyRun`, the stick, the refusal), `scorecard.py` (`headless_run`, the wait), `fidelity_audit.py` (its cells' environment, `run_tool`) |
| `purelib.logs` | the line formats and their readers: `[pure] ship` (`SHIP_RE`, `SHIP_T_RE`), `player object` (`PLAYER_RE`), `[pure] grid` (`GRID_RE`, `grid_samples`), `[pure] exit at frame` (`exit_frame`), `[hle-stub]` and the start-up list (`STUB_RE`, `UNIMPL_RE`, `unimplemented`, `HALT_RE`), the `[metal]` exit lines (`metal_exit`, `metal_pipelines`, `METAL_FPS_RE`), the GE exit list (`ge_ignored`), the audio capture's underruns and files (`UNDERRUN_RE`, `wav_files`, `wav_channel`) | the same tools and `pp_lines.py` |
| `purelib.ppsspp` | PPSSPP's shared use: `wait_free` (no PPSSPPSDL running and no profile save on its memory stick, as the scorecard waited), `stick_snapshot` and `stick_restore` (what a run added to the stick moved out, changes reported) | `scorecard.py`, `vfpu_probe.py`, `ai_seed_check.sh` |

Every headless port run the runner starts has `PURE_NO_BUSY_CLOCK=1` (`port.steady_clock`, from task 051's finding:
the framework's busy-time charge made a headless run depend on the machine's load) unless its environment names the
switch: `run_boot.py` without a window and without `--sound` (so the headless suite, `hud_check.sh --shell headless`
and the scorecard's runs), the sweep's headless cells (the audit's too) and `--record-line`; a window or `--sound`
keeps the charge, as a player has it.

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
  name. Paths inside code blocks count too. The spike reports about other repositories (docs/vendor-map.md,
  docs/codegen-baseline.md, docs/research.md) and the dated history files under `docs/history/` are not path-checked.
- **Links.** Every relative Markdown link resolves, and a `#anchor` names a heading of its file (GitHub's rule).
- **Patches.** Every `NNNN-slug` patch name is a file in `patches/`, and a patch cited by the word and a number alone is
  reported: task 052 regrouped the series, so the numbers tasks 001 to 048 used name other patches now.
  A doc cites a patch as `NNNN-slug` with the task that made the change ("patch 0002-ge-state-commands (task 037)"),
  or an old number as "old NNNN" on purpose; a history file may cite an old patch by the name patches/README.md's
  mapping table gives it.
- **Tasks.** Every `docs/tasks/NNN` cited is a task file.

It prints one line per finding (`FILE:LINE: what`) and a verdict, and exits 0 when there is none, 1 otherwise. Run it
after editing a doc, and in a task that moves or renames a file, a tool or a patch.

## History

[docs/history/verification.md](history/verification.md): each check's first runs and tables (the
suite's first five scenes and the thirteen task 035 added, the re-baselines, the HUD check before
task 031, the wall times of task 034, task 051's log diff, the M4 audio checks, the reverb's steps,
the VFPU measurements, the shared runner's equivalence checks).

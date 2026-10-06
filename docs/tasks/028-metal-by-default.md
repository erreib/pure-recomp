# 028: Metal by default; per-backend measured values in the suite; headless runs in the tools

Milestone: M7 | Branch: task/028-metal-by-default | Status: OPEN (after task 025)

## Goal
With tasks 023 to 027 the native path is `PURE_SHELL=metal PURE_GE_BACKEND=metal`, and it draws closer to PPSSPP than
the Vulkan bootstrap path. D-008 makes it the default on macOS. This task does that in our entry point, makes the
regression suite's bookkeeping per backend (its "measured" column is Vulkan's today, so a Metal run reports every
scene as "moved"), flips the suite's own defaults to the new path, and gives `tools/run_boot.py` a `--shell` option so
headless runs are one flag.

## Read first
- CLAUDE.md, docs/decisions.md D-002, D-007, D-008, docs/metal-backend.md ("Verify numbers", "The Metal shell"),
  docs/ge-backend.md 8.5 (selection), docs/verification.md (the suite's rules)
- src/host/pure_main.cpp (our `main()`), vendor/portablekit/host/gpu/ge_backend.cpp `selected_backend()` and
  host/shell/shell.cpp `selected_shell()` (both read `<prefix>_GE_BACKEND` / `<prefix>_SHELL`, default vulkan)
- tools/frame_regress.sh (SCENES table: `measured` column; `--backend`, `--shell`; the "moved more than 0.03" note),
  tools/run_boot.py (`--window`, `--script`, `--shots`, `--env`), tools/verify_task.sh, tools/campaign_sweep.py (how it
  sets the environment of its runs: it must keep working under the new default), docs/tasks/026-shell-seam.md
  (Result, open question 3: `run_boot.py --script` implies `--window` and leaves audio on)

## Deliverable
1. `src/host/pure_main.cpp`: before calling the framework's main, set `PURE_SHELL=metal` and `PURE_GE_BACKEND=metal`
   when unset (`setenv(..., 0)`), on macOS only (`#if defined(__APPLE__)`); an explicit value always wins, so
   `PURE_GE_BACKEND=vulkan PURE_SHELL=vulkan` still runs the bootstrap path and `PURE_NO_RENDER` keeps its meaning.
   `--replay` is unaffected (it names its backends). Print nothing extra.
2. `tools/frame_regress.sh`: the SCENES table carries a measured value per backend (`measured_vulkan`,
   `measured_metal`; the Metal values from docs/metal-backend.md: lang 0.0002, title 0.0002, profile 0.0000,
   main_menu 0.0106, race_hud 0.0379), the delta and the "moved" note use the running backend's column, and the
   defaults become `--shell metal --backend metal` (the Vulkan path stays `--shell vulkan --backend vulkan`). The
   summary line names both. `docs/verification.md` says so.
3. `tools/run_boot.py`: `--shell vulkan|metal|headless` sets `PURE_SHELL`; `--shell headless` also sets
   `PURE_GE_BACKEND=null` unless `--backend` or the environment names one, `PURE_NO_AUDIO=1` unless the environment says
   otherwise, and does not imply `--window`. `--backend NAME` sets `PURE_GE_BACKEND`. Existing flags unchanged.
4. `tools/campaign_sweep.py`, `tools/save_roundtrip.sh`, `tools/gerec/replay_check.sh`, `tools/gerec/metal_check.sh`:
   check each still runs under the new default (they set what they need explicitly where a backend matters:
   replay_check records with the Vulkan inner backend and must say so; metal_check records at scale 1 with Vulkan);
   fix only what the default breaks, and say what.
5. README.md: the default in the `PURE_GE_BACKEND` and `PURE_SHELL` rows, the `--shell`/`--backend` flags in the
   run_boot row, the suite's new defaults. docs/status.md: not yours (Fable updates it).

## Acceptance criteria
- [ ] `tools/run_boot.py --frames 300 out/028/default.log` (no environment) logs the Metal shell and the Metal backend
      and reaches frame 300; `PURE_GE_BACKEND=vulkan PURE_SHELL=vulkan tools/run_boot.py --frames 300 out/028/vulkan.log`
      logs neither Metal line.
- [ ] `tools/frame_regress.sh` (new defaults) passes 5/5 with every delta within 0.001 of the Metal measured column
      (no "moved" note), and `tools/frame_regress.sh --shell vulkan --backend vulkan` passes 5/5 with the Vulkan
      column (deltas as before).
- [ ] `tools/run_boot.py --shell headless --script config/pad_scripts/frontend.txt --shots out/028/shots --frames 2200
      out/028/headless.log` reaches frame 2200 in under 10 s with the four shots written and no audio device opened.
- [ ] `tools/campaign_sweep.py single_race vineta_k` still PASSes (it runs the Vulkan path or the Metal path; say
      which and why in Result).

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/frame_regress.sh --shell vulkan --backend vulkan --only lang && python3 tools/run_boot.py --shell headless --script config/pad_scripts/frontend.txt --shots out/028/shots --frames 2200 --seconds 60 out/028/headless.log && test -f out/028/shots/profile.png`

## May touch
- src/host/pure_main.cpp, tools/frame_regress.sh, tools/run_boot.py, tools/campaign_sweep.py (only if the default
  breaks it), tools/save_roundtrip.sh (same), tools/gerec/replay_check.sh and metal_check.sh (same), docs/verification.md,
  README.md

## Must not touch
- vendor/, patches/, src/gpu/, src/profile/, src/hle/, src/tools/, config/, ref/, CMakeLists.txt, docs/status.md

## Estimated turns
40

## Escalate when
A tool cannot work under the Metal default without a change outside "May touch" (say which and why), or the Metal
suite's fractions differ from docs/metal-backend.md's by more than 0.001 on a scene (report; do not change the
backend).

## Result
Status: PARTIAL. Deliverables 1 to 5 are in, and the Verify line passes (`tools/verify_task.sh 028`, exit 0). Both of
the brief's escalation conditions came up, from one cause that is outside "May touch": in races, the Metal shell's
window often shows the frame without the HUD. Because of it:
- `tools/campaign_sweep.py` cannot read its shots under the Metal default. It now runs the Vulkan path unless the
  environment names a shell or backend.
- The Metal `race_hud` scene scored 0.0823 once, against the measured 0.0379 (the Verify run). Four other runs scored
  0.0366 to 0.0383.

I did not change the backend or the shell. Details are under "The race HUD on the Metal window" below.

Changed:
- `src/host/pure_main.cpp`: on macOS, `setenv("PURE_SHELL", "metal", 0)` and `setenv("PURE_GE_BACKEND", "metal", 0)`
  before `portablekit_main`, and after the `--replay` branch, so a replay is untouched. An explicit value wins. That
  includes an empty one, which the framework reads as vulkan. `PURE_NO_RENDER` still forces the headless shell. The
  entry point prints nothing.
- `tools/frame_regress.sh`:
  - The `SCENES` rows have two measured columns, `vulkan` and `metal`. The Metal values are 0.0002, 0.0002, 0.0000,
    0.0106 and 0.0379, from docs/metal-backend.md, with their sources in the comments.
  - The delta and the "moved" note use the running backend's column. The delta is printed to four decimals.
  - The defaults are now `--shell metal --backend metal`.
  - The first summary line names the shell, the backend and the measured column. The verdict line names the shell
    and the backend.
- `tools/run_boot.py`:
  - `--shell vulkan|metal|headless` sets `PURE_SHELL`. `vulkan` and `metal` imply `--window`; without it,
    `PURE_NO_RENDER=1` would force the headless shell.
  - `headless` keeps the run headless even with `--script` or `--shots`. It sets `PURE_GE_BACKEND=null` unless
    `--backend` or the environment names a backend, and `PURE_NO_AUDIO=1` unless the environment sets it.
  - `--backend NAME` sets `PURE_GE_BACKEND`.
  - Existing flags behave as before.
- `tools/gerec/replay_check.sh` and `tools/gerec/metal_check.sh`: they record with `--shell vulkan
  --env PURE_GE_RECORD_INNER=vulkan`, and their headers say so.
- `tools/campaign_sweep.py`: `PURE_SHELL` and `PURE_GE_BACKEND` default to vulkan (`setdefault`), with the reason in
  the docstring.
- `README.md`:
  - the intro;
  - the `PURE_GE_BACKEND`, `PURE_SHELL`, `PURE_NO_RENDER` and `PURE_SCREENSHOT_DIR` rows;
  - the `PURE_GE_RECORD` row (the vulkan inner backend needs `PURE_SHELL=vulkan`);
  - the run_boot flag table: `--window`, the new `--shell` and `--backend`, and `--script`/`--shots`;
  - the `pure_main.cpp`, `frame_regress.sh`, `replay_check.sh`, `metal_check.sh` and campaign sweep rows.
- `docs/verification.md`: the suite section covers the defaults, the two measured columns, both paths before a
  merge, the summary lines and the 4-decimal delta. It also has the Metal `race_hud` spread, the Vulkan-only
  deliberate regression (`PURE_NO_STENCIL_BUFFER` is a Vulkan switch) and per-backend re-baselining.
- `tools/save_roundtrip.sh`: unchanged. It passes under the new default.
- Commits: ffd0575, 85eb864, 0e3270d, 08672ef, c7d454d, 1b3feae and the Result commit.

Acceptance:
1. Default run.
   - `tools/run_boot.py --frames 300 out/028/default.log` with no environment reached frame 300 in 1.4 s. It logs
     `[metal] drawing with Apple M4 Pro at 480x272 ...` and `[shell] headless (...)`, not the Metal shell. The reason
     is that run_boot's default sets `PURE_NO_RENDER=1`, and that always means the headless shell (D-007). The Metal
     backend now draws there, where the old default rendered nothing.
   - With `--window` and still no environment, the log shows `[shell] metal: Apple M4 Pro, window 960x544, vsync`,
     `[shell] metal (...)` and the `[metal] drawing` line, and the run reaches frame 300 in 11.2 s.
   - `PURE_GE_BACKEND=vulkan PURE_SHELL=vulkan tools/run_boot.py --frames 300 out/028/vulkan.log` logs
     "Renderer: disabled by PURE_NO_RENDER" and reaches frame 300, with no Metal line. With
     `--shell vulkan --backend vulkan` (windowed) it logs "Renderer: Vulkan on Apple M4 Pro, target 960x544" and no
     Metal line.
2. The suite on both paths.
   - New defaults (`out/028/regress-metal`, 7m 12s): 5/5 with no "moved" note. Each delta is within 0.001 of the
     Metal column.

     | Scene | Fraction | Delta |
     |---|---|---|
     | lang | 0.0002 | +0.0000 |
     | title | 0.0002 | +0.0000 |
     | profile | 0.0002 | +0.0002 (the blinking cursor after LOAD, as in task 027) |
     | main_menu | 0.0106 | +0.0000 |
     | race_hud | 0.0383 | +0.0004 |

   - Vulkan path (`out/028/regress-vulkan`, 7m 10s): 5/5 at 0.0544, 0.0302, 0.0543, 0.0331 and 0.0636. The last is
     race_hud, -0.0034: the AI grid, inside the documented 0.063 to 0.086.
   - Not every Metal run stays within 0.001:
     - The Verify run scored race_hud 0.0823 (+0.0444) and printed the "moved" note. The scene still passed under its
       0.10 limit. The suite run that came next (`--shell vulkan --only lang`) cleared that capture.
     - Three `--only race_hud` reruns scored 0.0370, 0.0374 and 0.0366. The last is -0.0013. All four captures I kept
       show the HUD.
     - A frame without the HUD scores about 0.04 more than the same frame with it (below), so the 0.0823 capture most
       likely lacked the HUD.
3. `tools/run_boot.py --shell headless --script config/pad_scripts/frontend.txt --shots out/028/shots --frames 2200
   out/028/headless.log` reached frame 2200 in 1.0 s. It wrote `lang`, `notice`, `title` and `profile` (black, from
   null) and logged "Audio: disabled by PURE_NO_AUDIO" and `[shell] headless`. It submitted 20586 draws, and 20643 in
   the Verify run. The game opens `Profile_part1.PMF` after Start. With `--backend metal`, the same route gives the
   backend's own pictures: lang 0.000169, title 0.000237 and profile 0.000000 against the references.
4. `tools/campaign_sweep.py single_race vineta_k` passes on the Vulkan path: flip 17770, laps 62.8, 61.6 and 64.9 s,
   46 contacts, 9.7 shield left, and the `ref` shot reads the shield bar as 100%.
   - It runs the Vulkan path because the sweep reads the race HUD, the results panel and the SHIP DESTROYED title
     from window shots, and the Metal window drops the HUD (below).
   - The run under the Metal default, before the pin, ended STALL: eliminated by damage at flip 15880, with 34
     contacts and probe shield -0.2. Its `ref` shot 600 flips into the race had no HUD, so the bar read 0%.
   - The damage itself comes from the probe (guest memory), so this cell is marginal on either path: 13 shield left in
     task 016, 9.7 here.
   - The Metal run is kept in `out/028/sweep-metal/`.

The other tools under the new default (deliverable 4):

| Tool | Under the Metal default | Change |
|---|---|---|
| `save_roundtrip.sh` | PASS, all three runs: MAIN MENU after LOAD at 0.000881 and 0.001134, SET NAME variance 1531 against the empty stick's 0. It runs on the Metal shell. | none |
| `gerec/replay_check.sh` | broken before the fix. The record backend's inner backend defaults to vulkan, which draws with the Vulkan shell's renderer, so the recording run printed "the record GE backend draws with the Vulkan shell's renderer, and the metal shell has none; nothing is drawn" and wrote no file. | `--shell vulkan`, `PURE_GE_RECORD_INNER=vulkan`. Then PASS in 487 s with all four recordings made fresh: race_warm 6014-6016 at 0.000000, frontend and title at 0.000000, null black, first draw named. |
| `gerec/metal_check.sh` | the same breakage | the same fix. PASS in 397 s with team and race_1x recorded fresh: team 0.000000; race_1x frame 6016 at 0.000015 (2 px); bisected for the record to draw 526 at 1x and draw 24 at 2x. |
| `campaign_sweep.py` | the shots lose the race HUD | Vulkan unless the environment names a shell or backend (above) |

The race HUD on the Metal window (escalation):
- The probe ran the race route (`main_menu.txt` + `single_race.txt`, Cross held, no steering) with a shot every 25
  flips from 6200 to 7700, and looked for the yellow CURRENT and LAP labels (`out/028/hud/run.sh`, `hud.py`).

  | Run | Shots with the HUD |
  |---|---|
  | Metal shell window (default) | 12 of 61; from flip 6250 on, 10 of 59 |
  | Vulkan shell window | 61 of 61 |
  | Headless Metal (the backend's `capture_frame`) | 61 of 61 |

- At flip 7000, the Vulkan window and the headless Metal capture both show "CURRENT 0.12.4" over the same view. The
  Metal window shows the same 3D picture, complete, with no HUD at all.
- A Metal window frame without the HUD differs from the headless capture of the same flip by 0.058 to 0.060 at
  tol 32. With the HUD on both, the difference is 0.016.
- The frontend and menus are not affected: lang, title, profile and main_menu score as in task 023.
- The suite's race_hud (frame 6016, before the start) usually has the HUD, so the suite does not catch this.
- The window capture copies the drawable being presented, so players see a flickering or missing HUD in races on the
  default path.
- Likely cause, not verified because `src/` is outside this brief: `MetalShell` samples the backend's target from a
  command queue of its own (`metal_shell.mm`). The backend commits the frame's last command buffer at
  `present_image` without waiting. In a race, the depth write-back at the SIGNAL commits and waits mid-frame, so the
  3D part is finished and only the draws after it, the HUD, may not have run when the shell samples.
- Possible fixes:
  - the shell uses the backend's queue;
  - an `MTLSharedEvent` signalled by the backend's commit;
  - the backend waits for its frame before handing the texture over.
- The fix belongs in `src/host/metal_shell.mm` and/or `src/gpu/metal_backend.mm`.

Verify output (last 20 lines; `tools/verify_task.sh 028`, exit 0):

The suite tables from the same run:
```
lang          690    0.0002   0.07   24    0.0002 +0.0000  PASS
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0823   0.10   32    0.0379 +0.0444  PASS

moved more than 0.03 from the metal measured value: race_hud (something changed; docs/verification.md)
frame regression: PASS, 5/5 scenes pass, shell metal, backend metal (7m 10s)
...
lang          690    0.0544   0.07   24     0.054 +0.0004  PASS
frame regression: PASS, 1/1 scenes pass, shell vulkan, backend vulkan (0m 24s)
```
The last 20 lines:
```
  0xda x1 first=0x0
  0xe2 x2 first=0x0
  0xe3 x2 first=0x0
  0xe4 x2 first=0x0
  0xe5 x2 first=0x0
  0xe6 x1 first=0x0
  0xf0 x1 first=0x0
  0xf1 x1 first=0x0
  0xf2 x1 first=0x0
  0xf3 x1 first=0x0
  0xf4 x1 first=0x0
  0xf5 x1 first=0x0
  0xf6 x1 first=0x0
  0xf7 x1 first=0x0
  0xf8 x1 first=0x0
  0xf9 x1 first=0x0
[render] null backend: 2200 frames, 20643 draws submitted, 0 block transfers, 0 uploads in 0.52458 s
[run_boot] shots: 4 new BMP(s) converted to PNG in out/028/shots (lang, notice, profile, title)
[run_boot] exit 0 after 0.9s, 345 lines
verify 028: PASS
```

Open questions:
1. The race HUD on the Metal window (above) is a defect in the default path. It needs a task on
   `src/host/metal_shell.mm` / `src/gpu/metal_backend.mm`. Once it is fixed:
   - `campaign_sweep.py`'s Vulkan pin can go;
   - a mid-race scene in the suite (for example flip 7000 of this route) would guard it, since race_hud at 6016 is
     before the race clock starts.
2. Acceptance 1 as written expects the Metal shell from a run_boot run with no flags, but run_boot's default is
   headless (`PURE_NO_RENDER=1`). Either `--window` belongs in that criterion, or run_boot's default should change;
   I kept the existing flags as the brief says. A side effect: every default headless run_boot now draws with Metal
   on the GPU, at 300 frames in 1.4 s against 0.7 s with no rendering. `--backend null` gives the old cost.
3. The Metal race_hud varies by about ±0.0013 run to run (the AI grid), so "every delta within 0.001" holds for some
   runs and not others. The column stays 0.0379, as the brief says. Re-baselining it is Fable's call.
4. Not in "May touch", and still naming vulkan as the default:
   - docs/ge-backend.md sections 6 and 8.5 (the selection tables' "vulkan (default)");
   - docs/metal-backend.md's command lines with `--backend metal`.
5. `--shell headless` in run_boot also sets `PURE_NO_RENDER=1` (run_boot's usual headless default). That changes
   nothing in the headless shell: pacing follows the shell, and fast loading only matters in a window.
6. An empty `PURE_SHELL=` or `PURE_GE_BACKEND=` counts as explicit and selects vulkan (`setenv(..., 0)`, as the
   brief asks). README says so.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

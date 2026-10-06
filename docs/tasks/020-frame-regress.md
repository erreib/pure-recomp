# 020: The frame regression suite

Milestone: M5/M6 | Branch: task/020-frame-regress | Status: OPEN (dispatch after task 018)

## Goal
One command that proves the port still renders the known screens like PPSSPP: boots the game through the frontend
route, captures the title, profile and main menu, runs the race route to the first full-HUD frame, compares each with
its reference at the tolerances already measured, and prints a table with PASS/FAIL per scene. This is the check every
renderer change (and the Metal backend later) runs before merging.

## Read first
- CLAUDE.md, docs/verification.md, tools/imgdiff.py, config/pad_scripts/frontend.txt and main_menu.txt,
  ~/dev/pure-recomp/out/race/route.txt, ref/README.md (frames and the capture settings), docs/tasks/006, 009, 010,
  011 Results (the measured fractions: title 0.030 at tol 24; main menu 0.033; profile and language 0.054 from
  downscale edges; race frame 6016 0.067 at tol 32)

## Deliverable
1. `tools/frame_regress.sh [--backend vulkan|metal] [--out DIR]`: runs the routes with `tools/run_boot.py --script`
   and `--shots`, captures `lang`, `title`, `profile`, `main_menu` (frontend + main-menu routes) and `race_hud`
   (frame 6016 of the race route, bloom and shadows on), compares each with `ref/<scene>.png` using the thresholds
   in a small table at the top of the script (lang 0.07, title 0.05, profile 0.07, main_menu 0.05 at tol 24;
   race_hud 0.10 at tol 32; keep the measured values beside them as comments), writes diff images for failures,
   and prints the table. Exit 0 only if every scene passes. Total run time about 8 minutes.
2. `docs/verification.md`: a section on the suite and how to re-baseline thresholds.
3. The `--backend` flag sets `PURE_GE_BACKEND` for later; today only vulkan exists and the flag is recorded, not
   enforced.

## Acceptance criteria
- [ ] `tools/frame_regress.sh` passes on batch/m2 with every scene's fraction printed.
- [ ] A deliberate regression (e.g. `PURE_NO_STENCIL_BUFFER=1` passed through an env hook) makes race_hud FAIL with
      a diff image written.

## Verify
`tools/frame_regress.sh && test -s out/regress/summary.txt`

## May touch
- tools/frame_regress.sh (new), docs/verification.md, README.md (one row), config/pad_scripts/ (new route files only)

## Must not touch
- src/, vendor/, patches/, tools/run_boot.py, tools/imgdiff.py, ref/

## Estimated turns
30

## Escalate when
A scene's fraction differs from the measured values by more than 0.03 on the first run (report; something changed).

## Result
(worker fills)

## Review
(Fable fills)

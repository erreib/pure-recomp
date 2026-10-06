# 020: The frame regression suite

Milestone: M5/M6 | Branch: task/020-frame-regress | Status: MERGED (dispatch after task 018)

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
Status: DONE

Changed:
- `tools/frame_regress.sh` (new): `[--backend vulkan|metal] [--out DIR] [--only SCENE[,SCENE...]] [--env KEY=VAL ...]`.
  - The scene table sits at the top of the script (`SCENES`): route, shot frame, reference, tol, limit and measured
    value for each scene, with a comment on each row saying where the measured value came from.
  - It makes one bounded windowed run per route, with `tools/run_boot.py --script --shots --frames`. Each run goes
    to its last shot + 30 flips and starts on an empty memory stick in `<out>/game`, because `main_menu.txt` saves a
    profile. The checkout's `game/ms0` is not touched.
  - It compares each capture with `tools/imgdiff.py --tol T --max-frac L`, keeps `<out>/<scene>.diff.png` only for
    failing scenes, and prints the table with `delta` (the move from the measured value). A line names any scene
    that moved more than 0.03.
  - It writes `<out>/summary.txt` (default `out/regress`) and exits 0 only when every scene passes.
  - `--backend` passes `PURE_GE_BACKEND` and records it in the summary; nothing reads it yet. `--env` is the env
    hook. `--only` runs a subset (race_hud alone takes 3m 18s).
- `docs/verification.md`: new section "Frame regression suite (task 020, 2026-10-06)", with "Re-baselining the
  limits".
- `README.md`: one row (`tools/frame_regress.sh`) in the Layout table.
- No new route file. The suite builds each run's script from the committed routes, with their own `shot` steps
  dropped and `FRAME:shot SCENE` put first. The race route is `main_menu.txt` + `single_race.txt`, which up to 6045
  has the same presses as `~/dev/pure-recomp/out/race/route.txt`. Its Cross hold at 6100 comes after the run ends.
- This file.

Per-scene fractions (tol 24, race_hud tol 32; both frames at 480x272). The first run was before the commit, the Verify
run on commit 5efb2a6:

| Scene | Route | Frame | Reference | Limit | Measured | First run | Verify run |
|---|---|---|---|---|---|---|---|
| lang | frontend.txt | 690 | ref/frontend.png | 0.07 | 0.054 | 0.0544 | 0.0544 PASS |
| title | frontend.txt | 1750 | ref/title.png | 0.05 | 0.030 | 0.0302 | 0.0302 PASS |
| profile | frontend.txt | 2100 | ref/profile.png | 0.07 | 0.054 | 0.0543 | 0.0543 PASS |
| main_menu | main_menu.txt | 4700 | ref/main_menu.png | 0.05 | 0.033 | 0.0331 | 0.0331 PASS |
| race_hud | main_menu.txt+single_race.txt | 6016 | ref/vineta_k_start.png | 0.10 | 0.067 | 0.0672 | 0.0672 PASS |

Escalation check: on the first run every scene was within 0.001 of its measured value (largest 0.0004), so there was
no escalation. lang 7099 px and main_menu 4323 px are the same pixel counts task 006 reported; profile is 7091 against
7096. Both full runs took about 7 minutes (7m 9s and 7m 7s): frontend 71-72 s, main menu 158 s, race 197-198 s. Every
run reached its last frame and run_boot exited 0.

Deliberate regression: `tools/frame_regress.sh --only race_hud --env PURE_NO_STENCIL_BUFFER=1 --out
out/regress-nostencil`. The log shows "stencil buffer off". race_hud scored 0.3053 (delta +0.238) and failed. The
diff `out/regress-nostencil/race_hud.diff.png` was written; it shows the whole darkened track in red. The drift line
named race_hud, and the suite exited 1.

Verify output (`tools/frame_regress.sh && test -s out/regress/summary.txt`, exit 0; the whole output is 17 lines):
```
frame regression 2026-10-06 02:08, commit 5efb2a6, backend vulkan (PURE_GE_BACKEND: recorded, not enforced)
extra environment: none
run frontend: 2130 flips ...
run frontend: run_boot exit 0, frame 2130 reached: yes, 71 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a1311a97d2d88fb57/out/regress/frontend.log
run main_menu: 4730 flips ...
run main_menu: run_boot exit 0, frame 4730 reached: yes, 158 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a1311a97d2d88fb57/out/regress/main_menu.log
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 198 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a1311a97d2d88fb57/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
lang          690    0.0544   0.07   24     0.054  +0.000  PASS
title        1750    0.0302   0.05   24     0.030  +0.000  PASS
profile      2100    0.0543   0.07   24     0.054  +0.000  PASS
main_menu    4700    0.0331   0.05   24     0.033  +0.000  PASS
race_hud     6016    0.0672   0.10   32     0.067  +0.000  PASS

frame regression: PASS, 5/5 scenes pass (7m 7s)
```

Open questions:
- race_hud scored 0.0672 in both full runs. Task 011 saw 0.063-0.086 because the AI grid changed between runs. The
  empty stick on every run may make the grid repeatable (the RTC is the other candidate). I did not check this. If
  the grid is repeatable, race_hud's limit could come down toward 0.08.
- All five scenes could come from one run of the race route, about 3.5 minutes instead of 7. The frontend and
  main-menu presses are a prefix of it. The only shared frame is main_menu.txt's DOWN at 2100, and the profile shot
  would run first there. I kept three runs because the brief names the routes and the measured values come from
  them.
- The PPSSPP references are git-ignored, so a fresh worktree needs `ref/*.png` copied from the main checkout. The
  suite exits 2 and names the missing file.
- `tools/verify_task.sh`, named in CLAUDE.md, does not exist. I ran the Verify line directly.

## Review
Merged (Fable). The suite is the merge gate for every renderer change from here on (task 021's acceptance uses it).
Decisions: keep the three runs (the measured values come from those routes); revisit race_hud's limit once the
grid's repeatability is understood (RNG seed question). `tools/verify_task.sh` now exists.

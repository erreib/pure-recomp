# 006: PPSSPP reference captures for the frontend, main menu and the Vineta K race start

Milestone: M2/M3 | Branch: task/006-ppsspp-references | Status: OPEN

## Goal
`ref/` is empty. The frame-comparison checks need PPSSPP captures of the screens our port now reaches: Language
Selection, title, Profile, Main Menu, and the Vineta K race start (countdown). Our port's own route to the main menu
and into the race is known (`config/pad_scripts/main_menu.txt`, and the race steps below), and the PPSSPP driver
already reaches the profile screen deterministically; what is missing is the rest of the PPSSPP route and the files.

## Read first
- CLAUDE.md, docs/ppsspp.md (the driver, its limits, the button sequence for the frontend and the race),
  tools/ppsspp/ppsspp_ctl.py, tools/ppsspp/routes/frontend_draft.txt (the SAVE PROFILE answer is mistimed there)
- config/pad_scripts/main_menu.txt (our port's sequence; PPSSPP needs the same buttons but its own frame numbers)
- ref/README.md (the file naming the tools expect), tools/imgdiff.py --help

## Deliverable
1. `tools/ppsspp/routes/frontend.txt`: boot to MAIN MENU in PPSSPP (language, notice, START to skip the intro movie,
   START on the title, NEW, 9-slot name with CROSS x4 then DOWN+CROSS x4 then CROSS on the blank 9th slot, CROSS to
   SET TAG, CROSS x3 + CROSS, SAVE PROFILE: DOWN to NO then CROSS, WARNING: CROSS). Verify each step with
   `--shots-every` captures; the frames must be stable across two runs (byte-identical captures).
2. `tools/ppsspp/routes/vineta_k_start.txt`: from MAIN MENU, CROSS on SINGLE PLAYER, SINGLE RACE, VECTOR, ALPHA,
   VINETA K, FEISAR; capture the frame that shows the countdown "3" (or the first frame with the HUD's CURRENT
   0.00.0 and the grid if the countdown ring is hard to pin).
3. Captures into `ref/`, software renderer at 1x: `frontend.png` (Language Selection), `title.png`, `profile.png`,
   `main_menu.png`, `vineta_k_start.png`, each with a `.ppdmp` GE dump of the same frame, plus `ref/boot-hle.log`
   (boot to main menu with HLE logging). Record the frame numbers in `ref/README.md`.
4. A first comparison against our port's captures (read-only, in the main checkout): `python3 tools/imgdiff.py
   ~/dev/pure-recomp/out/mm/menu.png ref/main_menu.png --tol 24 --max-frac 0.05 --json` and the same for
   `out/004-shots/title.png` vs `ref/title.png`, `out/004-shots/profile.png` vs `ref/profile.png`,
   `out/race/r6400.png` vs `ref/vineta_k_start.png`. Put the fractions in the Result (they are information, not
   acceptance; our port currently has a magenta cast in the race).

## Acceptance criteria
- [ ] Both route files replay deterministically (two runs, identical captures).
- [ ] The five PNGs and five .ppdmp files exist in ref/ with their frame numbers in ref/README.md.
- [ ] PPSSPP is not running afterwards and its ini is restored.

## Verify
`test -s ref/main_menu.png && test -s ref/vineta_k_start.png && test -s ref/vineta_k_start.ppdmp && test -s ref/boot-hle.log && python3 tools/imgdiff.py ref/main_menu.png --region 20,20,440,60 --min-variance 50`

## May touch
- tools/ppsspp/ (routes, driver fixes), ref/ (captures are git-ignored except README.md), docs/ppsspp.md

## Must not touch
- everything else; never commit a capture or a .ppdmp (git-ignored anyway; check `git status` before committing)

## Estimated turns
40

## Escalate when
The save-profile screen cannot be timed deterministically in PPSSPP, or the race route needs save-state support the
driver cannot provide; report the frames you reached.

## Result
(worker fills)

## Review
(Fable fills)

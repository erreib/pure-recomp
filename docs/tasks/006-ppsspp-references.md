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
Status: DONE

The SAVE PROFILE step was not a timing problem. SET TAG needs a fifth CROSS after the tag reads AAA; before that
press it does not move on. I checked this up to frame 5430, and a DOWN does not advance it. In the draft, the DOWN
meant for SAVE PROFILE landed on SET TAG and was lost. The next CROSS confirmed the tag, and the CROSS after that
picked YES. With the extra CROSS at 4860, SAVE PROFILE appears at about 4880. DOWN at 5000 moves to NO, CROSS at 5100
brings up WARNING, and CROSS at 5250 opens MAIN MENU at about 5340.

The race route continues from there: CROSS at 5700, 5900, 6100, 6300, 6500 and 6700, with each screen settled about
150 frames before its press. The countdown shows no digits. READY slides in at 7213 with a spinning blue ring, then
GO! appears. So vineta_k_start uses the brief's fallback: the first frame with the HUD (CURRENT 0.00.0) fully faded
in over the grid.

All runs were bounded by `--until`. PPSSPP quit cleanly after each one, and the ini was restored after each one
(it is now identical to `ppsspp.ini.orig`). The memstick only ever held `PPCD00001DLS001`, unchanged since 12:45.
No profile save was written, so nothing had to be moved aside.

Changed:
- `tools/ppsspp/ppsspp_ctl.py`:
  - A screenshot-only capture now leaves the CPU stepping, so the next capture arms its breakpoint before the game
    runs on. Before, each resume/pause round trip let about 16 frames pass: `--shots-every 15` drifted 3 frames per
    capture and named the files after the requested frames. Captures can now be one flip apart.
  - A capture that starts late is reported as `late_frames`.
  - `--pad-file` can be repeated, to chain routes.
- `tools/ppsspp/routes/frontend.txt` (new): boot to MAIN MENU, annotated.
- `tools/ppsspp/routes/vineta_k_start.txt` (new): MAIN MENU to the race start.
- `tools/ppsspp/routes/frontend_draft.txt`: removed (superseded).
- `ref/README.md`: settings, frame table, SHA-256 of every capture, regenerate commands.
- `docs/ppsspp.md`: status, timeline, memstick state, routes.

Frame table (frames are vblank counts since boot; "captured" is the flip that handed over the frame):

| Scene | Files | Requested | Captured |
|---|---|---|---|
| Language Selection | ref/frontend.{png,ppdmp} | 600 | 602 |
| Title | ref/title.{png,ppdmp} | 2650 | 2653 |
| Profile (LOAD highlighted) | ref/profile.{png,ppdmp} | 2880 | 2882 |
| Main Menu (help text fully typed) | ref/main_menu.{png,ppdmp} | 5640 | 5643 |
| Vineta K start (first full-HUD frame, before READY) | ref/vineta_k_start.{png,ppdmp} | 7154 | 7155.3 |
| HLE boot log | ref/boot-hle.log (1.6 MB, 15822 lines) | to 5659 | |

Determinism: I ran the routes three times:
- two capture runs, both routes, with GE dumps;
- one run of `frontend.txt` with `--log`.

All five PNGs were byte-identical across the runs that made them, and all five `.ppdmp` were byte-identical across
the two capture runs. Two exploration runs used the same pad script, one with the old unchained captures and one with
the new chained ones. They matched at all three frames they shared (7081, 7141 and 7201).

Comparison against our port's captures (`imgdiff --tol 24 --max-frac 0.05`). Our port's captures are 960x544 and
are resized to 480x272 for the comparison:

| Port capture | Reference | Fraction | Result |
|---|---|---|---|
| out/mm/menu.png | ref/main_menu.png | 0.0331 (4323 px) | PASS |
| out/004-shots/title.png | ref/title.png | 0.0302 (3943 px) | PASS |
| out/004-shots/profile.png | ref/profile.png | 0.0544 (7096 px) | FAIL |
| out/race/r6400.png | ref/vineta_k_start.png | 0.9464 (123557 px) | FAIL |
| out/004-shots/lang.png (extra) | ref/frontend.png | 0.0544 (7099 px) | FAIL |

On the frontend screens, most differing pixels are one-pixel edges of lines and glyphs, which suggests the 2x to 1x
downscale. Our menu capture is also caught mid-typing of the help text. The race pair is a different moment (0.02.4
after GO! in our port) and our port has the magenta cast.

Verify output:
```
PASS variance R/G/B 2249.2/492.6/149.2 (max 2249.2, need 50) in region 20,20,440,60 of ref/main_menu.png (480x272)
```

Open questions:
- The captures are git-ignored and exist only in this worktree's `ref/`. When merging, copy `ref/*` into
  `~/dev/pure-recomp/ref/`, or regenerate them with the two commands in `ref/README.md` (about 2 minutes each). The
  hashes in that README confirm a match.
- The Vineta K countdown has no "3". The reference is the first frame with the HUD fully in. If M3 wants a frame
  inside the countdown, frames 7213 to about 7390 hold READY and the ring. Either way, our port needs a capture at the same
  game event (HUD fade-in), not at r6400.
- profile and lang are at 0.054 against a 0.05 limit, almost entirely from edge pixels. Either compare our port at
  1x, or mask the edges, or raise the tolerance for UI screens. That is a decision for the comparison task.
- `docs/status.md` line 67 still mentions `routes/frontend_draft.txt`. That file is outside "May touch", so I did not
  change it.
- The zone scene and save states (`--savestate` needs the Accessibility permission) are still not done.

## Review
(Fable fills)

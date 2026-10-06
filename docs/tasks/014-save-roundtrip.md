# 014: Save round trip (M5)

Milestone: M5 | Branch: task/014-save-roundtrip | Status: OPEN

## Goal
Profile creation wrote `game/ms0/PSP/SAVEDATA/UCUS98612P0000` through the framework's savedata dialog. Prove the
round trip: create a profile, finish (or abandon) a race so progress exists, quit, start again, LOAD the profile,
and see it listed with its name; then verify the save folder has the PSP layout (PARAM.SFO, DATA/PROFILE.BIN,
ICON0.PNG) and that the game's own autosave of the profile works. This is also where the DLC door is checked:
sibling folders under SAVEDATA must not break the profile list.

## Read first
- CLAUDE.md, docs/status.md, config/pad_scripts/main_menu.txt (profile NEW route), docs/research.md (save folders
  `UCUS98612P%04d`, `UCUS98612D<PACK>`), vendor/portablekit/host/hle/hle_savedata.cpp and host/save_data/ (the
  dialog modes and the on-disk layout), `PURE_TRACE_SAVEDATA=1` output in ~/dev/pure-recomp/out/mm.log (read-only)

## Deliverable
1. `tools/save_roundtrip.sh`: starts from an empty `out/014/ms0` (own `PURE_GAME_DIR` copy with EBOOT.ELF and
   disc.iso linked), runs the main-menu route (which creates the profile and answers the save question YES),
   confirms the folder exists with the expected files, then a second run with a LOAD route
   (`config/pad_scripts/profile_load.txt`: title, Start, Profile LOAD, Cross on the listed profile, through to the
   main menu) and a capture of the profile list showing the name; exit 0 only if both hold.
2. A third run with a fake sibling folder `UCUS98612DGAMMAPACK1` (empty) present: the profile list still shows the
   profile and the game does not halt (DLC door).
3. `docs/savedata.md`: the modes the game uses (from the traces), the folder layout, and what the dialog shows
   headless vs windowed.

## Acceptance criteria
- [ ] `tools/save_roundtrip.sh` exits 0 with the three runs' outcomes printed.
- [ ] The profile-list capture after LOAD shows the saved name (region variance on the list area and a visual check
      described in the Result).

## Verify
`tools/save_roundtrip.sh`

## May touch
- tools/save_roundtrip.sh, config/pad_scripts/profile_load.txt, docs/savedata.md, README.md (one row)

## Must not touch
- src/, vendor/, patches/, tools/run_boot.py

## Estimated turns
35

## Escalate when
LOAD needs an on-screen dialog that never completes (report the savedata trace and stop), or the save folder lacks
PARAM.SFO (framework bug: report, do not patch).

## Result
(worker fills)

## Review
(Fable fills)

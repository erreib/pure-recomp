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
Status: DONE. Verify passes. The work departs from the brief in two places, both explained below: the capture shows SET NAME, not a profile list, and the autosave was not observed.

Changed:
- `tools/save_roundtrip.sh` (new): three windowed runs on a memory stick of its own (`PURE_GAME_DIR=out/014/game`, `ms0/` emptied at the start; the checkout's `game/ms0` is not touched). Exits 0 only when every check holds. Takes about 7 minutes.
- `config/pad_scripts/profile_load.txt` (new): title, Start, profile LOAD, MAIN MENU (shot `menu-loaded`), PROFILE > SAVE, then PROFILE > NEW > YES to SET NAME (shot `name-loaded`). The run ends there, before NEW saves anything.
- `docs/savedata.md` (new): the folders, the modes the game uses (from the traces), the sceIo accesses, what the dialog shows headless and windowed, autosave, and the DLC door.
- `README.md`: one row (`tools/save_roundtrip.sh`).

Outcomes (2026-10-05, `tools/save_roundtrip.sh`):
1. NEW (`main_menu.txt` on an empty stick): the game's LISTSAVE (mode 5, list `P0000..P0004`) writes `UCUS98612P0000`. The folder holds `PARAM.SFO` 4912, `PROFILE.BIN` 41570, `ICON0.PNG` 6742, `ICON1.PMF` 51200, `PIC1.PNG` 172944 and `SND0.AT3` 97604 bytes. In `PARAM.SFO`, `SAVEDATA_DIRECTORY` is `UCUS98612P0000` and the detail reads "User name: NAME0000 / Gold medals awarded: 0 / Ranking: Rookie". `PROFILE.BIN` is plain and holds pilot `NAME0000` and tag `AAA`. MAIN MENU is reached. The first boot also AUTOSAVEs `PPCD00001DLS001` (`DATA1.BIN` 768 bytes, plus `DATA2.BIN` 276 bytes, which the game writes itself through sceIo).
2. LOAD (`profile_load.txt`): LISTLOAD (mode 4) loads 41570 bytes from `P0000`, and MAIN MENU matches run 1's (0.1% of pixels differ at tolerance 32). The game's own MAIN MENU > PROFILE > SAVE writes `P0000` back through LISTSAVE: `PROFILE.BIN` is rewritten and the name is intact. SET NAME then shows "NAME0000".
3. DLC door (the same route with an empty `UCUS98612DGAMMAPACK1`): the game's boot scan of `ms0:/PSP/SAVEDATA/` lists the folder and tries to open its `PI.WAD`. That open fails (0x80010002, no such file) and the game carries on. The profile loads, saves and shows exactly as in run 2, the run reaches frame 3900 without halting, and the folder is left untouched.

The profile list does not exist on this port:
- On a PSP, LOAD opens the system's LISTLOAD dialog, which shows ICON0, the save's title and its "User name: ..." detail. The game draws no list of its own.
- The framework draws no dialog, windowed or headless. It confirms the first listed save that exists, and every request completes (status 1, 2, 3, 4, 0).
- So the route has no "Cross on the listed profile" step: an extra Cross would select SINGLE PLAYER.
- The capture that shows the saved name is SET NAME, which the game pre-fills with the current profile's name.
- Region variance over the name's 5th to 8th letters (PSP region 200,92,115,26) is 1545 in runs 2 and 3. On the empty-stick control (`out/014/run1/fresh-name.png`, the same screen) it is 0.
- Visual check: `out/014/run2/name-loaded.png` and `run3/name-loaded.png` read "NAME0000", and `run1/fresh-name.png` reads "NAME". `run2/menu-loaded.png` is MAIN MENU (SINGLE PLAYER, MULTIPLAYER, PROFILE, DOWNLOAD).

The escalation condition did not occur: no dialog stalls, and `PARAM.SFO` is present.

Verify output (last 20 lines):
```
  ok    MAIN MENU after LOAD matches run 1's (PASS fraction 0.001078)
  ok    SET NAME shows the loaded name past NAME (variance 1545 >= 500; control 0)
        UCUS98612P0000: ICON0.PNG 6742, ICON1.PMF 51200, PARAM.SFO 4912, PIC1.PNG 172944, PROFILE.BIN 41570, SND0.AT3 97604
  ok    PARAM.SFO present
  ok    PROFILE.BIN present
  ok    ICON0.PNG present
        TITLE = 'Wipeout Pure'
        SAVEDATA_TITLE = 'Profile data'
        SAVEDATA_DIRECTORY = 'UCUS98612P0000'
        SAVEDATA_DETAIL = 'User name: NAME0000  \nGold medals awarded: 0\nRanking: Rookie'
  ok    PARAM.SFO SAVEDATA_DIRECTORY is UCUS98612P0000
  ok    PARAM.SFO detail names the pilot NAME0000
        SAVEDATA_FILE_LIST = empty (plain save)
  ok    PROFILE.BIN holds pilot 'NAME0000', tag 'AAA'
  ok    UCUS98612DGAMMAPACK1 left as it was (empty)

run 1 NEW (main_menu.txt, empty stick): PASS: LISTSAVE wrote UCUS98612P0000 with PARAM.SFO, PROFILE.BIN (pilot NAME0000) and ICON0.PNG; MAIN MENU reached
run 2 LOAD (profile_load.txt): PASS: LISTLOAD loaded UCUS98612P0000, MAIN MENU as in run 1, PROFILE > SAVE rewrote it, SET NAME shows NAME0000 (variance 1545; empty stick 0)
run 3 DLC door (+ empty UCUS98612DGAMMAPACK1): PASS: seen by the SAVEDATA scan, its PI.WAD open fails (0x80010002, no such file) and the game moves on; profile loaded, saved and shown (variance 1545); last frame reached
save round trip: PASS
```

Open questions:
- Autosave was not observed:
  - The game saves only when asked. Nothing is saved after quitting a race from the pause menu (CONTINUE, RESTART, QUIT), and nothing after leaving SETTINGS or the PROFILE menu.
  - The executable has "Profile Autosaving" and "Ghost Autosaving" strings, most likely used after a finished race. Finishing a race needs the steered lap of task 012.
  - Of the brief's "finish (or abandon) a race", only abandon was tried.
  - What is shown to work is the game's own save of a loaded profile (PROFILE > SAVE).
  - Follow-up: add a finished-race leg to the tool once a route can finish a race.
- The brief's `DATA/PROFILE.BIN` does not exist. The PSP layout is flat, so `PROFILE.BIN` sits beside `PARAM.SFO`, and the tool checks for it there.
- Framework behaviour (not patched; `vendor/` is out of scope):
  - LISTSAVE always picks the first listed name (`P0000`), even when that save exists.
  - LISTLOAD always picks the first save that exists.
  - A second NEW profile would therefore overwrite the first, and `P0001` to `P0004` are unreachable.
  - Several profiles would need a save-list dialog UI in the framework, or an override in the profile.
- `src/profile/pure_profile.cpp` lists `kSaveFolders` as `UCUS98612P0001` to `P0004`, but the game's list starts at `P0000` and its only profile goes there. As a result, the overlay's save import and export (which use `save_folders`) would miss it. Suggested fix: `P0000` to `P0004`. I did not change it because `src/` is Must-not-touch here.
- The game's savedata parameter block is 0x5DC bytes, the firmware 1.x layout with no key, so its saves are plain, as on a PSP. `SAVEDATA_FILE_LIST` is empty for that reason, not because of a missing console key.

## Review
(Fable fills)

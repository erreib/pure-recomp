# 077: The download packs installed and checked (DLC)

Milestone: DLC (Erik, 2026-10-12; docs/dlc.md) | Branch: task/077-download-packs | Status: OPEN

## Goal
The planning session put the twelve US download packs on a scratch stick and the game loaded them unchanged
(docs/dlc.md): the frontend opened every PI.WAD, LEAGUE SELECTION listed Classic 2, Delta and Gamma beside Alpha,
TEAM SELECTION gained Icaras, and a Gamma race on Exostra Run ran with its HUD, headless on Metal, the twelve packs
costing half a second at boot. Nothing in the port needed changing. After this task the player has a way to
install packs, the Esc menu's Import saves screen accepts them, a check proves the packs load and a pack race
runs, and the docs say where packs go. The packs are the game's data: never in the repository, never in a release
archive; on this Mac they are at `$HOME/dlc-packs/` (twelve `UCUS98612D*` folders, 62 MB).

## Read first
- CLAUDE.md, docs/dlc.md (what the game does with a pack, the spike's findings, the pack list), docs/savedata.md
  (the folder table, "Download packs", the import and export section), docs/decisions.md (D-005, D-012),
  docs/tracks.md (the routes and the DOWN presses), docs/release.md (the data directory, `ms0/`)
- src/profile/pure_profile.cpp (`kSaveFolders`: the profiles; the comment naming the pack folders),
  vendor/portablekit/host/profile.hpp (`SaveFolder`: name, description, exported),
  vendor/portablekit/host/save_data/save_transfer.cpp (`is_game_save_name`, `check_save_folder`, `import_save`:
  what the menu's Import accepts, by the profile's list), vendor/portablekit/host/ui/save_screen.cpp (the Import
  saves screen; read-only: nothing here changes)
- tools/purelib/port.py (`fresh_stick`, `scratch_data_dir`), tools/run_boot.py (`--shell headless --backend metal
  --script --shots --every --data-dir --env`; a headless run without `--backend metal` captures nothing),
  tools/hud_check.py (its DIR of `h<FLIP>.bmp`), tools/imgdiff.py, tools/frame_regress.sh (how a route is joined
  from config/pad_scripts and shots are placed), config/pad_scripts/main_menu.txt and single_race.txt (the race
  route: MAIN MENU at 4450, SINGLE PLAYER 4700, SINGLE RACE 4900, class 5100, league 5300, track 5500, team 5700,
  Cross held from 6100), tools/sprite_pack.sh (a tool that takes a folder argument and installs into a scratch
  data directory), docs/verification.md ("Which path for which change"), README.md (the tools table)
- The spike's routes and logs in the main checkout, read-only for you: out/dlc/gamma_route3.txt (the Gamma route
  that reached the race), out/dlc/gamma3.log, out/dlc/spike1.log (the IO trace with the packs), out/dlc/sel/
  (the selection screens with packs), out/dlc/gamma3/ (the frames: 6500 TRACK SELECTION of the Gamma league, 7100
  on the race). What the spike learned about the route: confirming a pack league on a new profile shows a WARNING
  ("autosave will be disabled until the profile is saved from within the profile menu"); Cross on it returns the
  game to MAIN MENU, and the route navigates a second time (SINGLE PLAYER 5700, SINGLE RACE 5900, class 6100, the
  league's DOWN presses at 6180, 6210, 6240, league 6300, track 6500, team 6700, Cross held from 7100); the race HUD
  is up from flip 7100.

## Deliverable
One or two commits on the branch.
- **The profile lists the pack folders.** `kSaveFolders` in src/profile/pure_profile.cpp gains the twelve
  `UCUS98612D<PACK>` folders after the profiles, each with its pack's title as the description (Classic Pack 1 to
  3, Delta Pack 1 and 2, Gamma Pack 1 to 3, Daxter Pack, Jak X Pack, Socom 3 Pack, Socom FTB Pack: the titles the
  packs' PARAM.SFO carry, the Delta 1 typo "Delat" corrected) and `exported` false (a pack is the game's data, not
  the player's save: exports and backups leave it out; say so in the comment). With that the menu's Import saves
  screen accepts a pack folder, or a whole `PSP/SAVEDATA` tree of them, by name (`is_game_save_name`), and its save
  list names them. The list is only used by the save transfer and the save screen (`save_transfer.cpp`), not by
  the game's own save-data calls, which name their folders themselves. Check what `check_save_folder` makes of a
  pack's `TEST.BIN` (16 bytes, listed in `SAVEDATA_FILE_LIST` with a hash): whether the check passes with the
  framework's console keys. If it refuses a pack, report what it says and stop at that part (BLOCKED for that
  item alone; the rest of the task stands): a relaxation for pack folders is a vendor change for the next task,
  not this one.
- **`tools/dlc_install.sh [--data-dir DIR] PACKS`**: copies every `UCUS98612D*` folder found in PACKS (the folder
  itself, its `SAVEDATA`, or its `PSP/SAVEDATA`) into the data directory's stick, `<data dir>/ms0/PSP/SAVEDATA/`
  (the default data directory is the app's, as docs/release.md names it; `--data-dir` for a scratch one, as the
  check uses it), after checking each folder: the name is one of the twelve, `PI.WAD` (either case) and `PARAM.SFO`
  are present, and PARAM.SFO's `SAVEDATA_DIRECTORY` equals the folder's name (a Python check through
  tools/purelib or a few lines of the script). An existing folder of the same name is replaced only with
  `--replace`, else skipped with a line. Prints one line per pack (installed, skipped, refused and why) and a
  summary; exit 1 when any folder was refused. Never deletes anything else.
- **`tools/dlc_check.sh --packs PACKS [--out DIR] [--wait SECONDS]`**: installs the packs with `tools/dlc_install.sh`
  on a fresh stick of its own (`port.fresh_stick`) with a scratch data directory, then, headless on Metal:
  1. the selection run: the main_menu + single_race route with shots at 5185 (league_select) and 5600
     (team_select), with `PURE_TRACE_IO=1`; PASS when the log shows an open of `PI.WAD` in each of the twelve
     folders (count them), `league_select` differs from `ref/league_select.png` by at least 1% at tol 24 (the three
     pack leagues in the list) and `team_select` by at least 0.3% (Icaras), and the log has no `[hle-stub]` line
     for a pack-related call (say which lines you looked for);
  2. the race runs: the spike's Gamma route (above) and the same for Delta (two DOWN presses) and Classic 2 (one),
     each to flip 7600 with shots every 100 from 7100, PASS when `tools/hud_check.py` finds the HUD in at least 4 of
     the 6 shots of each race and the log's `[guest] Track Allocated` line is present (the spike saw it);
  3. the cost: the time of a boot to MAIN MENU (4700 flips) with the packs against one without, both headless,
     printed (no bar: the spike measured 3.2 s against 2.7 s).
  Print a table; `dlc_check: PASS` or `FAIL` last; exit 0 only on PASS, 2 when the packs folder is missing or a
  run could not start; everything under `--out` (default out/dlc_check). The packs folder is never written to.
- **The routes**: the pack-league race routes as files under config/pad_scripts/ (`gamma_race.txt`,
  `delta_race.txt`, `classic2_race.txt`, each documented in its header like single_race.txt: addresses, names and
  flips only, nothing of the game's data), joined after main_menu.txt by the check as frame_regress joins them.
- **Docs**: docs/dlc.md (a section "In the port (task 077)": the spike's result in brief, the warning and the
  double route, the install tool, the Esc menu's Import, the check, the cost figures; the "What the port needs"
  and "The plan" sections brought up to date), docs/savedata.md (the folder table's pack row: the twelve names,
  listed by the profile since this task; the import section: packs import), docs/release.md (where packs go in
  the data directory; that no release archive carries them), docs/windows.md (the rig checklist: install the packs
  from a copy and run the check with `--packs`), docs/tracks.md (the pack leagues' routes and the warning),
  README.md (the tools table: both tools). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/dlc_check.sh --packs "$HOME/dlc-packs"` PASS: twelve opens, the league and team screens changed, three
      pack races with the HUD, the cost printed
- [ ] `tools/dlc_install.sh` refuses a folder with a wrong name, a folder without PI.WAD, and a PARAM.SFO naming
      another folder (three hand-made bad folders under out/, figures in the Result), installs the twelve, and
      skips them on a second run without `--replace`
- [ ] the Esc menu's save screen names the pack folders (`PURE_MENU_DUMP` if it reaches that screen, else the save
      list's own log; say which) and `check_save_folder`'s verdict on a pack folder is known (the Result says
      what it printed, from the import flow or from a log line it writes)
- [ ] `tools/frame_regress.sh` PASS 18/18 (the profile change moves nothing: the game names its own folders) and
      `tools/save_roundtrip.sh` PASS
- [ ] `python3 tools/docs_check.py` passes

## Verify
`tools/dlc_check.sh --packs "$HOME/dlc-packs" && tools/frame_regress.sh && tools/save_roundtrip.sh && python3 tools/docs_check.py`

## May touch
- src/profile/pure_profile.cpp
- tools/dlc_install.sh (new), tools/dlc_check.sh (new), tools/purelib/ (a small helper if needed),
  config/pad_scripts/gamma_race.txt, delta_race.txt, classic2_race.txt (new)
- docs/dlc.md, docs/savedata.md, docs/release.md, docs/windows.md, docs/tracks.md, README.md,
  docs/tasks/077-download-packs.md (the Result)

## Must not touch
- include/psprecomp/, generated/, vendor/, patches/, src/gpu/, src/hle/, src/host/, src/profile/enhancements.*,
  src/profile/test_hooks.*, tools/frame_regress.sh, tools/save_roundtrip.sh, tools/hud_check.*, tools/imgdiff.py,
  ref/, docs/decisions.md, docs/status.md, anything not listed above; the packs folder and ~/Downloads (read only)

## Estimated turns
50

## Escalate when
- a pack race does not reach its HUD after the route's timings were checked against a frame series (report the
  frames: which screen the run is on at 7100)
- a `[hle-stub]`, halt or unsupported op appears with the packs installed (report the line)
- `check_save_folder` refuses a pack (that item alone: report its words, finish the rest)
- a vendor change or anything under Must not touch would be needed; a build takes over 5 minutes

## Result

Status: DONE, except importing seven packs through the Esc menu. That item is BLOCKED, as the brief's escalation
rule says: `check_save_folder` refuses those seven, and fixing it is a vendor change. Details under "check_save_folder's
verdict" below.

Changed:
- src/profile/pure_profile.cpp: `kSaveFolders` now lists the twelve US pack folders after the profiles. Each has its
  pack's title (Delta 1's "Delat" corrected) and `exported` false. The comment says this list is used only by the save
  transfer and the save screen.
- tools/dlc_install.sh (new), tools/dlc_check.sh (new), tools/purelib/dlc.py (new: the twelve names and titles, the
  PARAM.SFO reader, the folder checks, the app's data directory), tools/purelib/__init__.py (one docstring line).
- config/pad_scripts/gamma_race.txt, delta_race.txt, classic2_race.txt (new).
- docs/dlc.md (a new section "In the port (task 077)"; "What the port needs" and "The plan" updated), docs/savedata.md,
  docs/release.md (a new section "Download packs (task 077)"; the `ms0/` row), docs/windows.md (a rig checklist item),
  docs/tracks.md (a new section "The download packs' leagues (task 077)"), README.md (rows for both tools; the purelib
  row).
- Commits 018064a (profile) and 7249ad1 (tools, routes, docs), plus this Result.

Verify output (`tools/verify_task.sh 077`, last 20 lines):
```
  ok    PROFILE.BIN present
  ok    ICON0.PNG present
        TITLE = 'Wipeout Pure'
        SAVEDATA_TITLE = 'Profile data'
        SAVEDATA_DIRECTORY = 'UCUS98612P0001'
        SAVEDATA_DETAIL = 'User name: NAME1111  \nGold medals awarded: 0\nRanking: Rookie'
  ok    PARAM.SFO SAVEDATA_DIRECTORY is UCUS98612P0001
  ok    PARAM.SFO detail names the pilot NAME1111
        SAVEDATA_FILE_LIST = PROFILE.BIN
  ok    PROFILE.BIN verifies and deciphers (tools/save_interchange.sh --check)
  ok    PROFILE.BIN holds pilot 'NAME1111', tag 'AAA'

run 1 NEW (main_menu.txt, empty stick): PASS: LISTSAVE wrote UCUS98612P0000 with PARAM.SFO, PROFILE.BIN (pilot NAME0000) and ICON0.PNG; MAIN MENU reached
run 2 LOAD (profile_load.txt): PASS: LISTLOAD loaded UCUS98612P0000, MAIN MENU as in run 1, PROFILE > SAVE rewrote it, SET NAME shows NAME0000 (variance 1531; empty stick 0)
run 3 DLC door (+ empty UCUS98612DGAMMAPACK1): PASS: seen by the SAVEDATA scan, its PI.WAD open fails (0x80010002, no such file) and the game moves on; profile loaded, saved and shown (variance 1531); last frame reached
run 4 second profile (two_profiles.txt): PASS: the save list put NAME1111 in UCUS98612P0001, UCUS98612P0000 kept NAME0000; LOAD listed both and loaded UCUS98612P0000 by choice
run 5 restart LOAD (profile_list_load.txt): PASS: the list showed both on the newest; UCUS98612P0001 (NAME1111) loaded and shown (variance 449); both folders hold their own pilots
save round trip: PASS
docs_check: 34 files, 0 findings: PASS
verify 077: PASS
```
Earlier in the same Verify run: `dlc_check: PASS` and `frame regression: PASS, 18/18 scenes pass, shell headless, backend
metal (0m 22s)`. The whole log is out/077/verify.log in the worktree. Verify takes about 15 minutes, mostly
save_roundtrip's five windowed runs. That is longer than the 10-minute limit for a foreground command, so I ran
`tools/verify_task.sh 077` as one detached job and waited for it to finish. No other game ran during it.

The check's table (from the Verify run, headless on Metal; out/dlc_check/summary.txt):
```
check                                                      measured                                                  needs                        result
select run reaches its last flip                           flip 5630                                                 5630                         PASS
PI.WAD opened (twelve folders)                             12 of 12 folders, 164 opens                               12                           PASS
league_select against ref/league_select.png                0.0130 of pixels at tol 24                                >= 0.010                     PASS
team_select against ref/team_select.png                    0.0047 of pixels at tol 24                                >= 0.003                     PASS
race Gamma: HUD, Track Allocated                           HUD in 6 of 6, [guest] Track Allocated 7821KB, flip 7630  >= 4 of 6, the line, 7630    PASS
race Gamma: track_select against ref/track_select.png      0.1271 of pixels at tol 24                                >= 0.050                     PASS
race Delta: HUD, Track Allocated                           HUD in 6 of 6, [guest] Track Allocated 5826KB, flip 7630  >= 4 of 6, the line, 7630    PASS
race Delta: track_select against ref/track_select.png      0.1079 of pixels at tol 24                                >= 0.050                     PASS
race Classic 2: HUD, Track Allocated                       HUD in 6 of 6, [guest] Track Allocated 5003KB, flip 7630  >= 4 of 6, the line, 7630    PASS
race Classic 2: track_select against ref/track_select.png  0.1067 of pixels at tol 24                                >= 0.050                     PASS
boot to MAIN MENU (4700 flips)                             with the packs 2.4 s, 2.4 s; without 2.2 s, 2.2 s         (printed); each run to 4700  PASS
[hle-stub] for a pack-related call                         0 (0 [hle-stub] lines in all)                             0                            PASS
```
- **The `[hle-stub]` lines I looked for:** any `[hle-stub]` line, in every run with the packs (selection, three races,
  two boots). A line counts as pack-related when its call is a file call (`IoFileMgr*` / `::sceIo*`), the save-data
  utility (`::sceUtilitySavedata*`), the console identity the binding check reads (`::sceOpenPSID*`, `::sceWlan*`),
  the save cipher (`::sceChnnlsv*`) or the kernel's hashes (`::sceKernelUtils*`). There were no `[hle-stub]` lines at
  all. Every run reached its last flip, so there was no halt.
- **Negative test:** the check run on the three bad folders below, so that no pack was installed. Result: FAIL. 0 of 12
  folders opened, league_select and team_select both 0.0000 against their references, and each race ran Vineta K
  (Track Allocated 6492KB, TRACK SELECTION 0.0000). The HUD rows still passed, which is why I added the TRACK SELECTION
  row (see Open questions).

The install tool's figures:
- Three hand-made bad folders under out/077/bad: `tools/dlc_install.sh --data-dir out/077/bad_data out/077/bad`
  gave exit 1, and nothing was created:
  ```
    refused   UCUS98612DNOTAPACK     UCUS98612DNOTAPACK is not one of the twelve US packs
    refused   UCUS98612DPAKJAKX      no PI.WAD in it
    refused   UCUS98612DPAKSOCOM3    its PARAM.SFO names the folder UCUS98612DPAKDAXTER
  dlc_install: 0 installed, 0 replaced, 0 skipped, 3 refused; the stick holds 0 of the twelve US packs
  ```
- Installing `$HOME/dlc-packs` into out/077/try/data: `12 installed, 0 replaced, 0 skipped, 0 refused; the stick
  holds 12 of the twelve US packs` (exit 0).
- The same command a second time: twelve `skipped ... already on the stick (--replace replaces it)` lines, then
  `0 installed, 0 replaced, 12 skipped, 0 refused` (exit 0).
- Also tested:
  - `--replace` on one pack folder gives `replaced`.
  - A stick root (`.../ms0`) as PACKS installs all twelve.
  - A `UCES00001DGAMMAPACK1` folder is refused as a European pack.
  - A missing folder, or one with no packs in it, exits 2.

check_save_folder's verdict on the packs, taken from the import flow:
- **How I drove it:** a one-off windowed Metal run (route out/077/import/route2.txt, not committed). HOME pointed at a
  scratch folder whose `PSP/SAVEDATA` held copies of the twelve packs, because the file browser opens at HOME. The key
  presses were:
  1. Escape at the title.
  2. Q, for the System tab.
  3. Down five times, then Return, for Import save….
  4. Return on "Import from this folder".
  5. End, Up, Up, then Return, for Import these saves.
- **Where the names come from:** the screen's own `[saves]` log lines and its shots, not `PURE_MENU_DUMP`. The dump
  prints the save rows as one entry and never reaches this screen.
- **What the screen showed** (out/077/import/shots2/): each pack as "<title> (<folder>)", for example "Classic Pack 1
  (UCUS98612DCLASSICPACK1)" and "Socom FTB Pack (UCUS98612DPAKSOCOMFTB)".
- **What it printed:** `[saves] 12 save folder(s) found in <scratch>/ms0`, then one line per pack:
  - Accepted, `ok`: `UCUS98612DCLASSICPACK3`, `UCUS98612DPAKDAXTER`, `UCUS98612DPAKJAKX`, `UCUS98612DPAKSOCOM3`,
    `UCUS98612DPAKSOCOMFTB`. The import then printed `[saves] import <folder> from ...: done` for each of the five,
    and they appeared on the run's stick.
  - Refused: `UCUS98612DCLASSICPACK1`, `DCLASSICPACK2`, `DDELTAPACK1`, `DDELTAPACK2`, `DGAMMAPACK1`, `DGAMMAPACK2` and
    `DGAMMAPACK3`. Each printed `<garbage> is missing.`, shown on screen as "Cannot be imported: <garbage> is
    missing.".
- **Why the seven fail:**
  - In these seven packs, the first 32-byte entry of PARAM.SFO's SAVEDATA_FILE_LIST holds a word that reads as a PSP
    address (0x08xxxxxx), followed by zeros, where a file name belongs. TEST.BIN is the second entry. In the other five,
    TEST.BIN is the only entry.
  - `check_save_folder` treats every non-empty entry as a file the save must hold. So it looks for a file named by
    those four bytes, and that file does not exist.
  - The pack's protection is not the problem. I ran `tools/save_interchange.sh --check <copy> TEST.BIN` on copies of
    Gamma 1 and Classic 1, as on Jak X. Each gave flag 0x01 (mode 1), "PARAM.SFO hash (SAVEDATA_PARAMS) verified",
    "TEST.BIN hash (SAVEDATA_FILE_LIST) verified", verdict PASS.
  - The game itself reads neither TEST.BIN nor the list. All twelve load in the game when installed with
    tools/dlc_install.sh.

Boot cost: a boot to MAIN MENU (4700 flips, headless, unpaced) took 2.4 s and 2.4 s with the twelve packs, against 2.2 s
and 2.2 s without (Verify run). Two earlier runs of the check gave 2.4 and 2.6 s with the packs, and 2.2 s without each
time.

Open questions:
1. **Seven packs refused by the menu's Import.** This needs a vendor change for its own task: `check_save_folder`
   (save_transfer.cpp) could skip a SAVEDATA_FILE_LIST entry whose 13-byte name is not a printable file name. A PSP
   evidently accepts these folders, since the files came from consoles. Until that change, those seven go in through
   tools/dlc_install.sh or by hand. The docs say so.
2. **The spike's route was wrong.** The brief asked for the spike's double route (the WARNING, then a second pass). On a
   fresh stick no warning appears, and the double route confirms the track at 5450 and the team at 5700. The warning
   came from the spike's own stick:
   - That stick held five profiles (out/dlc/game/ms0 has P0000 to P0004), so SAVE PROFILE YES was cancelled with "no
     free slot".
   - The DOWN presses at 5180 then moved the cursor to NO, and Cross at 5300 picked NO. The warning is the game's answer
     to NO. The spike's frames 4300 to 5600 show SAVE PROFILE, NO, then the WARNING.
   - I reproduced the stuck SAVE PROFILE without packs on a stick with five profiles.

   So the three routes are single passes, checked against frame series of all three (out/077/series/):
   - DOWN presses from 5180, then single_race.txt's confirms (league 5300, track 5500, team 5700, Cross held from 6100).
   - TRACK SELECTION is up by 5350 and the HUD by 6000.
   - The check's shots from 7100 to 7600 fall 14 to 22 s into the race.

   docs/dlc.md and docs/tracks.md explain this.
3. **A row the brief did not ask for.** I added a TRACK SELECTION row to dlc_check: a shot at 5390, which must be at
   least 5% off `ref/track_select.png` (Alpha's). Without it, the race rows also passed with no pack installed, because
   the routes then raced Vineta K (see the negative test).
4. **Back up includes the packs.** The brief says exports and backups leave packs out. Export does (`exported` false).
   But the framework's Back up saves (`saves_to_back_up` uses `all_save_names()`) copies every listed folder, so a
   backup now includes the installed packs (62 MB). The profile's comment and docs/savedata.md say this. Leaving packs
   out of backups would be a vendor change.
5. **The profile grows with the packs.** With the packs on the stick, the game saves a profile of 68874 bytes (68890
   enciphered) instead of 41570. That is presumably the records of the packs' tracks; I did not read the contents. I
   did not try loading such a profile in a game without the packs. This matters for D-012's container.
6. **PROFILE > DELETE may list the packs.** From the code (`list_entries` in hle_savedata.cpp), its list (mode 7) names
   every `UCUS98612*` folder on the stick, so it would list installed packs. I did not try this in a run. docs/savedata.md
   records it.
7. **Docs outside May touch.** docs/verification.md is not in May touch, so its purelib module table and its "Which path
   for which change" table do not mention purelib.dlc or the two tools. docs/decisions.md is also not in May touch:
   docs/dlc.md says D-005 can close, and leaves that to the planning session.
8. **Windows is untested.** On Windows the check takes its shots in the Vulkan window (`port.DRAWING`), paced from 300
   flips before the first shot. The screen rows are weak there, because the Vulkan window already differs from the
   references by 0.062 and 0.042 without packs. docs/windows.md says this.
9. **No PPSSPP references with the packs.** `ref/` has no PPSSPP capture taken with the packs, so the check compares
   against the screens without packs. The main menu shows a DOWNLOAD entry, which nobody has opened.

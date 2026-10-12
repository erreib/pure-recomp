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

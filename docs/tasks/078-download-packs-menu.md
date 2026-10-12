# 078: A "Download packs" section in the Esc menu, and Import accepting every pack

Milestone: DLC (Erik, 2026-10-12; docs/dlc.md, D-005) | Branch: task/078-download-packs-menu | Status: OPEN

## Goal
After task 077 a player installs packs with a tool or by copying folders, and the Esc menu's Import accepts five
of the twelve: the other seven are refused because the first entry of their PARAM.SFO's SAVEDATA_FILE_LIST is not a
file name (a word that reads as a PSP address, then zeros; TEST.BIN is the second entry) and `check_save_folder`
takes every non-empty entry as a file the folder must hold. Erik wants a public release where a user never has to
know that packs are save folders. After this task the System tab has a "Download packs" section that says how many
of the twelve are installed, names each with whether it is present, and offers "Install download packs…", which
opens the existing import flow; Import accepts all twelve; the player's own Saves rows no longer list packs among
the saves, and Back up saves leaves them out. All of it generic in the framework (a profile marks which of its save
folders are content packs), as a vendor patch, with this profile marking the twelve.

## Read first
- CLAUDE.md, docs/dlc.md ("In the port (task 077)": the refusal, the seven names, the tools), docs/decisions.md
  (D-005), docs/savedata.md (the import section), docs/tasks/077-download-packs.md (the Result: how the import
  flow was driven by an input script in a window, what it printed, the HOME trick for the file browser),
  patches/README.md (the row format, patch 0019-game-option-rows and 0020-vulkan-texture-detail as the models of a
  profile-driven, generic feature), docs/upstream.md (the per-patch notes)
- vendor/portablekit/host/profile.hpp (`SaveFolder`: name, description, exported),
  vendor/portablekit/host/save_data/save_transfer.cpp (`names_of_save_folders`, `is_game_save_name`,
  `check_save_folder`: the SAVEDATA_FILE_LIST loop, `saves_to_back_up`, `import_save`),
  vendor/portablekit/host/save_data/save_transfer.hpp, vendor/portablekit/host/ui/save_screen.cpp (`save_rows`,
  `open_browser(Stage::ChooseImport)`, the import screens: how found saves are listed and imported, `names_text`),
  vendor/portablekit/host/ui/menu.cpp (`Menu::system`: the Saves section, `dump_row("[save rows]")`; the texture
  pack rows in `Menu::video` as the model of a section with a status line and an action), the menu's
  `PURE_MENU_DUMP` (how rows are dumped: `dump_row`, `info_row`, `button_row`, `choice_row`)
- src/profile/pure_profile.cpp (`kSaveFolders`), tools/purelib/dlc.py (`PACKS`: the names and titles; this task
  does not change it), tools/menu_check.sh (the System rows expected on both shells), tools/dlc_check.sh,
  tools/dlc_install.sh, docs/verification.md ("Which path for which change": the download packs row; the Esc menu
  row), docs/controls.md (the Esc menu's tabs), docs/release.md ("Download packs (task 077)"), README.md

## Deliverable
One vendor patch, `patches/0021-content-packs.patch` (`tools/patches.sh export 0021-content-packs`), its rows in
patches/README.md, its notes in docs/upstream.md, and the changes outside vendor/. One or two commits.
- **The profile marks content packs**: `SaveFolder` gains `bool content_pack = false;` with a comment (a folder
  the game loads as content, such as a download pack: shown under the content section, not among the saves; left
  out of backups; its PARAM.SFO's file list may hold entries that are not names). `GameProfile` gains
  `const char *content_packs_label = nullptr;` (the section's title, "Download packs" here; nullptr: the game has
  none and nothing changes). src/profile/pure_profile.cpp sets the label and marks the twelve.
- **The section**, in `Menu::system` after the Saves section (before About), when the label is set: `section(label)`;
  an `info_row(label, "N of M installed")` counting the content folders present on the stick (a folder with a
  PARAM.SFO, as `saves_to_back_up` counts); one `info_row` per content folder, its description and "Installed" or
  "Not installed" (a `dump_row("[content pack rows]")` before them so `PURE_MENU_DUMP` lists them as one entry, as
  the save rows are); a `button_row("Install " + lowercase label + "…", ...)` whose help says what to pick (a pack
  folder, or the folder or PSP/SAVEDATA holding them) and which opens the import browser (`open_browser(
  Stage::ChooseImport)` or the equivalent entry point save_screen.cpp exposes: add a small function to its header if
  needed); and, off Android, "Open the saves folder" is already in the Saves section, so nothing more.
- **Import accepts every pack**: in `check_save_folder`'s SAVEDATA_FILE_LIST loop, an entry whose 13-byte name is
  not a plausible file name (a byte outside printable ASCII, or a name that is empty after the first NUL) is skipped
  for a content-pack folder, with a comment naming task 078 and what the seven packs carry; for every other folder
  the check stays as it is. The import screen then lists all twelve as importable; after the import the game loads
  them (the check below).
- **The saves rows and the backup**: `names_of_save_folders` callers that mean the player's saves (`saves_to_back_up`,
  the export's names, the save screen's lists of what is on the stick) exclude content packs; `is_game_save_name`
  still accepts them (Import). Say in the Result which callers you changed and which you left.
- **The texts**: `docs/controls.md` (the System tab's new section), docs/release.md (installing packs: the menu's
  section first, the tool second), docs/dlc.md (the refusal resolved; the section), docs/savedata.md (the import
  section: packs through the Download packs section; backups leave them out), patches/README.md, docs/upstream.md,
  README.md if a row changes. `tools/menu_check.sh`: the System rows gain the section's rows on both shells (the
  label row, `[content pack rows]`, the button; name them as the dump prints them).
- **The check**: `tools/dlc_check.sh` gains a step that proves the import path: with HOME pointed at a scratch
  folder whose `PSP/SAVEDATA` holds the twelve packs (as task 077's Result did by hand), a windowed Metal run drives
  Esc, System, the "Install download packs…" row, "Import from this folder", "Import these saves" through an input
  script (task 077's key presses, adjusted to the new row's position), PASS when the `[saves]` lines show twelve
  `ok` and twelve `import ... done`, and the stick then holds the twelve (then the existing steps run on that
  stick, or on the tool-installed one, your choice: say which). Keep the step under two minutes; skip it with a
  line on Windows if the file browser cannot be driven there, and say so.

## Acceptance criteria
- [ ] `tools/dlc_check.sh --packs "$HOME/dlc-packs"` PASS with the new import step: twelve `ok`, twelve imported
- [ ] `tools/menu_check.sh` and `tools/menu_check.sh --shell vulkan` PASS with the section's rows; a dump with the
      twelve installed reads "12 of 12 installed" and one with none "0 of 12 installed" (figures in the Result)
- [ ] Back up saves on a stick with a profile and the twelve packs copies the profile alone (the `[saves]` line or
      the backup folder's listing in the Result); Export unchanged
- [ ] `tools/frame_regress.sh` PASS 18/18, `tools/save_roundtrip.sh` PASS
- [ ] `tools/patches.sh check` and `python3 tools/docs_check.py` pass; nothing under vendor/ committed

## Verify
`tools/dlc_check.sh --packs "$HOME/dlc-packs" && tools/menu_check.sh && tools/menu_check.sh --shell vulkan && tools/frame_regress.sh && tools/save_roundtrip.sh && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/profile.hpp, vendor/portablekit/host/save_data/save_transfer.cpp and .hpp,
  vendor/portablekit/host/ui/save_screen.cpp and .hpp, vendor/portablekit/host/ui/menu.cpp: only through
  `tools/patches.sh export 0021-content-packs`; commit patches/, never vendor/
- patches/0021-content-packs.patch (new), patches/README.md, docs/upstream.md
- src/profile/pure_profile.cpp
- tools/dlc_check.sh, tools/menu_check.sh, config/pad_scripts/ (a new import route file, if the check needs one)
- docs/controls.md, docs/release.md, docs/dlc.md, docs/savedata.md, README.md,
  docs/tasks/078-download-packs-menu.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/ (beyond a new pad script), src/gpu/, src/hle/, src/host/,
  src/profile/enhancements.*, src/profile/test_hooks.*, tools/dlc_install.sh, tools/purelib/, tools/frame_regress.sh,
  tools/save_roundtrip.sh, ref/, docs/decisions.md, docs/status.md, any vendor file not listed, anything not listed
  above; the packs folder and ~/Downloads (read only)

## Estimated turns
60

## Escalate when
- the import flow cannot be driven by an input script in under two minutes (report what blocks it; the rest of the
  task stands and the step is left as a manual note)
- a refused pack after the relaxation (report the check's words)
- the vendor change would reach into the save-data HLE, the kernel or include/psprecomp/; a build takes over 5
  minutes (a host change rebuilds the host layer only)
- Verify as a whole runs past the foreground limit: run its parts one by one in the foreground, then the full line
  once as the last step, as task 077 did

## Result

Status: DONE. Every part of Verify passes. Verify as one command takes about 22 minutes, and save_roundtrip alone takes
12.6 minutes, so neither fits the 10-minute foreground limit. I ran the parts one by one in the foreground, with
save_roundtrip split into two halves (details under the Verify output).

Changed:
- patches/0021-content-packs.patch (new). It covers six vendor files:
  - host/profile.hpp: `SaveFolder::content_pack` (default false) and `GameProfile::content_packs_label` (default null),
    each with a comment.
  - host/save_data/save_transfer.cpp and .hpp:
    - `names_of_save_folders` now skips content packs.
    - `check_save_folder` skips, for a content pack only, a file-list entry whose name up to its first NUL holds a byte
      outside 0x20..0x7E. The comment names task 078 and what the seven packs carry.
    - New `content_packs(memory_stick)`: the profile's packs, each marked installed when its folder holds a PARAM.SFO.
  - host/ui/menu.cpp: the section in `Menu::system`, after Saves and before About.
  - host/ui/save_screen.cpp and .hpp: `open_import()`, which calls `open_browser(Stage::ChooseImport)`.
- src/profile/pure_profile.cpp: the twelve packs are marked `content_pack`, `.content_packs_label = "Download packs"`,
  and the comment on `kSaveFolders` is updated.
- tools/dlc_check.sh: the import step, which is step 2. tools/menu_check.sh: the section's three System rows on both
  shells. config/pad_scripts/install_packs.txt (new): the route for the import step.
- patches/README.md: the row and the "0021-content-packs" section.
- docs/upstream.md: the dependency row, the note and the offer order. I also moved 0020's note out from under "Ours
  only", where task 076 had put it, so it sits with the other candidates.
- docs/controls.md, docs/release.md (the menu first, the tool second, by hand third), docs/dlc.md (a new section "In
  the menu (task 078)", the refusal marked resolved, the open list and the plan), docs/savedata.md, README.md (the
  dlc_check row and the `PURE_MENU_DUMP` row).
- Commits: d815c0e (patch and profile), e365e97 (check, route and docs), and this Result.

Verify output. These are the last lines of each part, in Verify order. The full line was not run as one command (see
above):
```
[hle-stub] for a pack-related call                         0 (0 [hle-stub] lines in all)                             0                                      PASS
dlc_check: PASS
System: ok (15)
menu_check: PASS
System: ok (15)
menu_check: PASS
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)
run 1 NEW (main_menu.txt, empty stick): PASS: LISTSAVE wrote UCUS98612P0000 with PARAM.SFO, PROFILE.BIN (pilot NAME0000) and ICON0.PNG; MAIN MENU reached
run 2 LOAD (profile_load.txt): PASS: LISTLOAD loaded UCUS98612P0000, MAIN MENU as in run 1, PROFILE > SAVE rewrote it, SET NAME shows NAME0000 (variance 1531; empty stick 0)
run 3 DLC door (+ empty UCUS98612DGAMMAPACK1): PASS: seen by the SAVEDATA scan, its PI.WAD open fails (0x80010002, no such file) and the game moves on; profile loaded, saved and shown (variance 1531); last frame reached
save round trip, half A (runs 1-3): PASS
run 4 second profile (two_profiles.txt): PASS: the save list put NAME1111 in UCUS98612P0001, UCUS98612P0000 kept NAME0000; LOAD listed both and loaded UCUS98612P0000 by choice
run 5 restart LOAD (profile_list_load.txt): PASS: the list showed both on the newest; UCUS98612P0001 (NAME1111) loaded and shown (variance 449); both folders hold their own pilots
save round trip, half B (runs 4-5): PASS
ok: 21 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 34 files, 0 findings: PASS
```
Run times:
- dlc_check: 1 min 16 s in total. The import step's window run took 33.1 s.
- menu_check: 25 s on each shell.
- save_roundtrip: 7 min 5 s for half A and 5 min 30 s for half B.

How save_roundtrip was split:
- I generated two scripts from the committed tools/save_roundtrip.sh, kept in the scratchpad and not committed.
- Half A holds the script's set-up and runs 1 to 3. Half B holds runs 4 and 5, on the same stick and the same out/014.
- Each half keeps the script's own run and check code. Only three things changed: the `cd` line, half B skipping the
  stick reset, and each half printing a summary of its own runs.
- No other game ran during them.

The import step's figures (out/dlc_check/import.log, Metal window, 2026-10-12):
- `[saves] 12 save folder(s) found in out/dlc_check/import/home`, followed by twelve `ok` lines and no refusal.
- Twelve `[saves] import UCUS98612D... from .../import/home/PSP/SAVEDATA/...: done` lines.
- Afterwards the stick held the twelve packs, each file identical to its source (filecmp). It also held the seeded
  profile UCUS98612P0000.
- The run reached flip 2300 of 2300.
- The check's row: `import: the menu's Install download packs…  12 found, 12 ok, 12 imported, flip 2300  PASS`.
- The other steps install the packs with tools/dlc_install.sh, each on a stick of its own, as before. I did not run
  them on the imported stick.

The menu dumps (`[menu] System:` lines):
- In the import run, when the menu opened, nothing was installed yet: `..., Quit game, [save rows], Download packs (0 of
  12 installed), [content pack rows], Install download packs…, Wipeout Pure Native, Game, Data folder, Saves folder,
  Graphics (Metal on Apple M4 Pro), Interface`.
- In the same run, when the menu opened again after the import: `Download packs (12 of 12 installed)`, with the other
  rows the same.
- menu_check on both shells: `Download packs (0 of 12 installed)`. The checkout's game/ms0 holds no pack, and the list
  accepts any count (`*`).
- Fifteen System rows on both shells.

Back up and Export on a stick holding a profile and the twelve packs:
- The import step's backup: `[saves] back up to out/dlc_check/import/data/save-backups/2026-10-12_12-56-58: done`. The
  backup folder holds UCUS98612P0000 only (ICON0.PNG, ICON1.PMF, PARAM.SFO, PIC1.PNG, PROFILE.BIN, SND0.AT3).
- The backup screen read "Copies Profile 1 to a folder." (out/dlc_check/import/shots/backup_screen.png).
- Export, a one-off window run on the same kind of stick (out/078/trial/export.log): `[saves] export to
  .../exporthome: done`. Its `PSP/SAVEDATA` holds UCUS98612P0000 only, as before: the packs were already
  `exported` false.

Callers of the folder list (`names_of_save_folders`, which now skips content packs):
- Changed through it:
  - `exported_save_names`, used by `export_saves` (Export's names). There is no change for this profile.
  - `all_save_names`, used by `saves_to_back_up`, and through that by `back_up_saves`, `backup_conflicts` and
    save_screen.cpp's `backup_screen`, which names what it copies.
- Left as they were:
  - `is_game_save_name`: `check_save_folder` and Import still accept the packs.
  - `save_label`: the import screen still names the packs.
  - `is_exported_save_name`: the "lists no data file" rule, which never applied to packs.
- New: `is_content_pack_name` (used by `check_save_folder`) and `content_packs()` (used by the menu).
- Not in scope and not touched: the save-data HLE's `list_entries` (PROFILE > DELETE).

Open questions:
1. **Windows has not been tried.** The import step runs there in the Vulkan window with HOME and USERPROFILE set. The
   browser uses USERPROFILE on Windows. I did not skip the step there. If the browser cannot be driven on the rig, the
   step will fail there and should be skipped with a line. The header comment and README.md say it is untried.
2. **Verify does not fit in one foreground command.** It takes about 22 minutes, and save_roundtrip is 12.6 minutes of
   that. The halves above are the closest I could get without a background job. save_roundtrip has no single-run
   option (status.md already notes this).
3. **docs/verification.md is outside May touch.** Its download packs row and Esc menu row do not mention the import
   step or the section yet.
4. **Focus after the import screen closes.** Focus goes back to Import save…, the Saves section's first row
   (`focus_row` is consumed in `save_rows`), not to Install download packs…. The route relies on this to reach Back up
   saves…. Returning focus to the row that opened the screen would be a small follow-up.
5. **The import screens use save wording.** The review and imported screens are Import save…'s generic screens: "Save
   to import", "Import these saves", and "Restart now to load the imported save". They work for packs, but the
   wording says saves.
6. **Restart now was not run.** I did not run it after a menu import. The imported packs are byte-identical to their
   sources, and the check's races show that tool-installed packs load.

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

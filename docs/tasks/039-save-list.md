# 039: The save list: a second profile must not overwrite the first (fidelity difference 4)

Milestone: M8 | Branch: task/039-save-list | Status: OPEN

## Goal
Creating a second profile silently overwrites the first, and LOAD offers no choice: the framework answers the game's
savedata LISTSAVE with the first listed name and LISTLOAD with the first save, with no dialog, where the PSP shows its
system save list (`ref/save_dialog.png`) and "Save completed." (`ref/save_completed.png`). The data loss comes first
(small): LISTSAVE with `overwrite=0` must go to the first free slot. Then the choice (medium): a list dialog in the
framework's interface for LISTSAVE and LISTLOAD when more than one save exists, drawn as the PSP's as far as the
interface allows, and answered by the input script in tests.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 4, the evidence, the reference pictures), docs/savedata.md (the save folders
  P0000 to P0004, the round trip, what task 014 found), docs/tasks/014 (Result), docs/ge-backend.md 8.5 (the
  interface runs only in a shell with a window: the headless shell has none, so tests answer the list by script)
- vendor/portablekit/host/hle/hle_savedata.cpp (the modes: AUTOSAVE, AUTOLOAD, LISTSAVE, LISTLOAD, LISTDELETE, the
  status machine, `overwrite`, how the result's file name is chosen), host/ui/ (the menu's widgets; how a screen is
  drawn over the game and takes input; `ui::open_menu_over_game`), host/shell/headless_shell.cpp (no interface:
  what the HLE must do there), host/shell/script_steps.cpp (the script grammar; a new action if the list needs one)
- src/profile/pure_profile.cpp (the save folders in the profile), tools/save_roundtrip.sh, config/pad_scripts/
  (the profile creation route: how the name, tag and save question are answered)

## Deliverable
1. Patch 0015 (`tools/patches.sh export 0015-savedata-list`), part one: LISTSAVE with `overwrite=0` writes to the
   first free slot of the game's list (P0000 to P0004) instead of the first name; LISTLOAD with several saves loads
   the newest unless told otherwise; LISTDELETE deletes the named one. `tools/save_roundtrip.sh` extended: create two
   profiles in a row, restart, LOAD, and both must exist with their own names (the game's own profile screen shows
   the loaded name; the memory stick holds both folders).
2. Part two: a save-list screen in the framework's interface (a window shell) for LISTSAVE and LISTLOAD when more than
   one save (or, for LISTSAVE, one save and a free slot) exists: the list the PSP shows (slot, title, date, from each
   folder's PARAM.SFO), Up/Down and Cross/Triangle on the pad, Enter/Escape on the keyboard, drawn over the paused
   game as the menu is; the chosen slot goes back to the game as the PSP's result; cancel returns the PSP's cancel
   code. Without a window (headless), the HLE keeps the script's answer: a new input-script action `save SLOT`
   (or `save newest`, `save free`) consumed by the next list request, so the sweep and the suite never block;
   with no answer scripted, the newest save (LISTLOAD) or the first free slot (LISTSAVE), as part one.
3. docs/savedata.md (the behaviour, the dialog, the script action), docs/fidelity.md (difference 4's row with the
   result), patches/README.md, README.md (the script action).

## Acceptance criteria
- [ ] `tools/save_roundtrip.sh` passes, including the new two-profile leg (both profiles exist and load by name).
- [ ] In the Metal shell's window, creating a second profile shows the save list, Cross on a free slot saves it, and
      LOAD shows both and loads the chosen one (screenshots of the list in out/039/, named in Result).
- [ ] Headless: `tools/frame_regress.sh` (18 scenes) and `tools/campaign_sweep.py single_race vineta_k --no-damage`
      unchanged (the routes create one profile on an empty stick, no list appears).
- [ ] `tools/patches.sh check` 15 patches (or 13 if 036/037 are not yet merged: say which number you took).

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/save_roundtrip.sh && tools/frame_regress.sh`

## May touch
- vendor/portablekit/host/hle/hle_savedata.cpp, host/ui/ (a new screen file and its hook in layer.cpp/menu.cpp),
  host/shell/script_steps.cpp and headless_shell.cpp (the `save` action), via `tools/patches.sh export 0015-savedata-list`;
  patches/; tools/save_roundtrip.sh; config/pad_scripts/ (a two-profile route for the round trip); docs/savedata.md,
  docs/fidelity.md (difference 4), README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/gpu/, host/kernel/, src/, tools/frame_regress.sh, tools/campaign_sweep.py,
  ref/, patches/0001-0014

## Estimated turns
70

## Escalate when
The game's LISTSAVE/LISTLOAD parameters do not carry what the list needs (report the fields and the PPSSPP trace of
the same call), or the interface cannot be shown while the HLE waits inside a savedata call (report how the status
machine runs: the dialog must be answered over several frames while the game polls `sceUtilitySavedataGetStatus`).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

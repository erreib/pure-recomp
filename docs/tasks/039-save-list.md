# 039: The save list: a second profile must not overwrite the first (fidelity difference 4)

Milestone: M8 | Branch: task/039-save-list | Status: MERGED 2026-10-07 (0aa3802)

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
Status: DONE. I took patch number 0015, as the brief says. Tasks 036 and 037 are not on this branch, so `tools/patches.sh check` reports 13 patches: 0001 to 0012, then 0015.

Changed:
- `patches/0015-savedata-list.patch` (new). It is exported from these vendor files:
  - `host/hle/hle_savedata.cpp`. The list modes are LISTLOAD, LISTSAVE, LISTDELETE, and mode 7 without a save name. Each request takes the first of these that applies:
    1. the input script's `save` answer, when one is queued;
    2. the save list, in a window, when there is a choice to make;
    3. otherwise a default: the newest save to load, the first free slot to save to, only the named save to delete.
    When none of these fits, the request is cancelled (result 1). Nothing is overwritten or deleted. While the list is open the request stays VISIBLE (status 2), and the result is written when the list closes. `PURE_TRACE_SAVEDATA` now also prints buttonSwap, newData and the list itself.
  - `host/ui/save_list.{hpp,cpp}` (new): the list screen.
  - `host/ui/menu.cpp`: draws the list from `draw_over_game`, and keeps the menu from opening while the list is up.
  - `host/shell/script_steps.{hpp,cpp}`, `host/shell/headless_shell.cpp`, `host/ui/input_script.{hpp,cpp}`: the `save ANSWER` action, in both shells.
  - `cmake/PortableKit.cmake`: one line adding `host/ui/save_list.cpp`. This file is not in "May touch", but the new screen file the brief asks for cannot build without it.
- `patches/README.md`: row 0015.
- `tools/save_roundtrip.sh`: new runs 4 and 5. `folder_check` now takes a folder and a pilot name.
- `config/pad_scripts/two_profiles.txt` and `profile_list_load.txt` (new; window only).
- `config/pad_scripts/profile_load.txt`: `2880:save P0000`, because in a window its PROFILE > SAVE now opens the list.
- `docs/savedata.md`, `docs/fidelity.md` (difference 4's row), `README.md` (the `save` action and the round trip's new runs).

Findings:
- **The requests carry everything the list needs.** The list is P0000 to P0004. The game sends focus 0 with an empty save name, buttonSwap 1 (X is Enter) and overwrite 0. The newData field holds a 7177-byte "Empty profile" icon for free slots.
- **The escalation condition did not occur.** While the status stays 2, the game keeps flipping at 30 per second and polling GetStatus. Behind the dialog it draws a grey screen with a blinking memory stick in the top right. So the list is drawn over the live game, not over a held frame. This differs from the brief's "over the paused game", and it matches the PSP, where the game keeps running behind the system dialog.
- **A second NEW profile saves without asking.** Made from the PROFILE menu, it has no SAVE PROFILE question; the game saves as soon as SET TAG is confirmed.
- **PROFILE > DELETE uses mode 7, not LISTDELETE.** It sends mode 7 with no save name, which PPSSPP calls LISTALLDELETE. Before this patch, the framework tried to delete a folder named `UCUS98612`, got 0x80110347, and nothing happened. Mode 7 without a name is now a delete from the list. Headless with no answer, it is cancelled.
- **The game handles cancel.** Backing out of the LOAD list returns to the PROFILE screen; backing out of the DELETE list returns to the PROFILE menu.

Acceptance:
- **Round trip: PASS, all five runs.**
  - Run 4: the list opened on P0001, Cross saved P0001, and P0000 was not written. LOAD listed both saves, and Up then Cross loaded P0000. SET NAME then matched run 2's NAME0000 capture (fraction 0.000).
  - Run 5: after a restart, LOAD listed both saves on the newest, P0001, and Cross loaded it. SET NAME showed NAME1111: it differs from NAME0000 by a fraction of 0.38, with variance 449.
  - Both folders keep their own pilots.
- **Screenshots in `out/039/`, all from the Metal window.**
  - From round trip run 4: `list-save.png` (the save list on the NEW DATA slot), `save-completed.png`, `list-load.png` (both saves, on NAME1111), `list-load-p0000.png` (on NAME0000) and `name-p0000.png`.
  - From run 5: `list-boot.png` and `name-p0001.png`.
  - From a probe run on the final build: `probe-load-list-key-up.png` (keyboard Up; the hints show Enter and Esc), `probe-overwrite-no.png`, `probe-overwrite-yes.png`, `probe-overwrite-completed.png`, `probe-delete-list.png` and `probe-delete-confirm.png`.
- **Headless suite: 18 of 18 scenes pass.** Every delta is +0.0000 except race_hud, at 0.0374 against the table's 0.0379; that scene varies with the AI grid.
- **Sweep, `single_race vineta_k --no-damage`: PASS.** It ended at flip 18340, 3 laps, race time 202.5 s; the audit's run ended at flip 17950, 196.1 s, and the follower runs on real time. Its saves are the same two as before: the AUTOSAVE of DLS001 and the LISTSAVE into P0000. No list appeared.
- **`patches.sh check`: ok, 13 patches.**

Verify output (last 20 lines):
```
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0374   0.10   32    0.0379 -0.0005  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0617   0.12   32    0.0617 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0620   0.11   32    0.0620 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0348   0.09   32    0.0348 +0.0000  PASS
zone_change   5679    0.0649   0.10   32    0.0649 +0.0000  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 25s)
verify 039: PASS
exit 0
```

Open questions:
- **PROFILE > SAVE in a window may not do what a player expects.** The list opens on the first free slot, as the brief asks, so a straight Cross saves a copy in a new slot, and the game's later autosaves go there. Nothing is lost. On a PSP the cursor would sit on P0000 and Cross would ask to overwrite. A remembered "current slot" from the last LISTLOAD or LISTSAVE could be the focus for SAVE; I did not add it.
- **A full stick, headless:** LISTSAVE with all five slots full and no `save` answer is cancelled.
- **What still differs from the PSP's dialog:**
  - the interface's font and button symbols;
  - no fade;
  - mode 7 lists only this game's folders;
  - after "Delete completed." the list closes with result 0, where a PSP goes back to the list.
- **Not exercised:** picking with the mouse. The pad was exercised, and so were the keyboard's Esc, Up and Return.
- **The layout was not checked against the PSP reference pictures.** `ref/save_dialog.png` and `ref/save_completed.png` are not in the checkout's `ref/`. The layout follows PPSSPP's `PSPSaveDialog` and the description in docs/fidelity.md.

## Review
Verify rerun: PASS from the main checkout on the merged build (fourteen patches at the time: 0001 to 0013 and 0015),
2026-10-07: `tools/save_roundtrip.sh` all five runs including the two-profile legs, the headless suite 18/18.
Spot-read: patch 0015's `hle_savedata.cpp` (the three-way answer: a scripted `save`, the list in a window, the
defaults that overwrite and delete nothing; mode 7 as the game's delete; the request VISIBLE while the list is up
and the game drawing behind it, as on the PSP), `host/ui/save_list.cpp`, the `save` action in both shells, the
round trip's new runs and routes.
Merged: 0aa3802 into batch/m2 (patches/README and docs/fidelity.md rows combined by hand). The CMake line for the
new screen file was outside May-touch and unavoidable.
Notes: the brief said "over the paused game"; the worker's finding that the PSP keeps the game running behind the
system dialog is the faithful one and is what landed. Open questions in docs/status.md Follow-ups: SAVE's focus on
the first free slot where a PSP would sit on the current slot, a full stick headless, the dialog's look against
`ref/save_dialog.png`.

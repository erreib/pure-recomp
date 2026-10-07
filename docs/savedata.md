# Save data (task 014, 2026-10-05; the save list, task 039, and the PSP's format, task 045, 2026-10-07)

How Wipeout Pure uses the memory stick on this port, from `PURE_TRACE_SAVEDATA=1` and `PURE_TRACE_IO=1` runs of
`config/pad_scripts/main_menu.txt` (profile NEW), `config/pad_scripts/profile_load.txt` (profile LOAD) and probes of
the PROFILE menu. The framework side is `vendor/portablekit/host/hle/hle_savedata.cpp` (the sceUtilitySavedata
dialog), `host/ui/save_list.cpp` (the save list) and `host/save_data/savedata_store.cpp` (the folders;
`savedata_crypto.cpp` the PSP's protection); the save list (task 039) and the no-key mode (task 045) are patch
0007-savedata-list-and-no-key-mode. `tools/save_roundtrip.sh` checks the round trip,
`tools/save_interchange.sh` the move of saves between the port and PPSSPP (a PSP's stand-in) both ways.

## Folders

Saves live in `<game dir>/ms0/PSP/SAVEDATA/` (`PURE_GAME_DIR` picks the game dir; `game/` by default), one folder per
save, named game name + save name, files flat in the folder as on a PSP memory stick:

| Folder | Written by | Files (bytes) |
|---|---|---|
| `UCUS98612P0000` (`P%04d`, 0000 to 0004) | profile NEW (save question YES) and PROFILE > SAVE: LISTSAVE | `PARAM.SFO` 4912, `PROFILE.BIN` 41586 (41570 bytes of data, enciphered; 41570 plain before task 045), `ICON0.PNG` 6742, `ICON1.PMF` 51200, `PIC1.PNG` 172944, `SND0.AT3` 97604 |
| `PPCD00001DLS001` | first boot, before the PROFILE screen: AUTOSAVE of `DATA1.BIN`, then `DATA2.BIN` through sceIo | `PARAM.SFO` 4912, `DATA1.BIN` 784 (768 enciphered; 768 plain before task 045), `DATA2.BIN` 276 (the game's own file, plain), `ICON0.PNG` 1451 |
| `UCUS98612G%x` | ghosts (time trial); not exercised yet | |
| `UCUS98612D<PACK>` | download packs (`PI.WAD`), e.g. `UCUS98612DGAMMAPACK1`; never written by the game here | |

The game's parameter block is 0x5DC bytes, the firmware 1.x layout with no key field. A PSP writes such a save in the
save-data utility's no-key mode (mode 1, below), and since task 045 so does the port: `PROFILE.BIN` is enciphered,
`SAVEDATA_FILE_LIST` lists it with its hash, and `SAVEDATA_PARAMS` carries the flag 0x01 and PARAM.SFO's hash (task
014 took the missing key field to mean a plain save; PPSSPP's saves showed otherwise, fidelity difference 5). Decrypted,
`PROFILE.BIN` starts with a word 2, the pilot name padded with spaces (`NAME0000  `) and the 3-letter tag (`AAA`). `PARAM.SFO` of a profile: `TITLE` "Wipeout Pure", `SAVEDATA_TITLE` "Profile data",
`SAVEDATA_DIRECTORY` "UCUS98612P0000", `SAVEDATA_DETAIL` "User name: NAME0000 / Gold medals awarded: 0 / Ranking:
Rookie" (three lines). The brief's `DATA/PROFILE.BIN` does not exist: the PSP layout has no subfolder, and
`PROFILE.BIN` sits beside `PARAM.SFO`.

The executable also names the files directly (`ms:UCUS98612P%04d\PROFILE.BIN`, `\PARAM.SFO`, `\ICON0.PNG`), and
`Data\FE\Profile\profile_FULL.PNG`, `profile_EMPTY.PNG`, "Empty profile": most likely the icons and title of the
list entries the PSP's own dialog shows. Strings "Profile Autosaving" and "Ghost Autosaving" exist; see "Autosave" below.

## Modes the game uses

| When | Mode | Request (trace) | Framework answer |
|---|---|---|---|
| First boot, frame ~1850 | AUTOSAVE (1) | game `PPCD00001`, save `DLS001`, file `DATA1.BIN`, 0x300 bytes, overwrite 1, ICON0 1451 | writes the folder, OK |
| Profile NEW, save question YES (frame 4300 in main_menu.txt); a second NEW from MAIN MENU > PROFILE saves at SET TAG's confirm, with no save question | LISTSAVE (5) | game `UCUS98612`, save "", list `P0000..P0004`, file `PROFILE.BIN`, 0xA262 bytes, ICON0 6742, ICON1 51200, PIC1 172944, SND0 97604, newData 7177 (the free slot's icon), focus 0, buttonSwap 1, overwrite 0 | the save list (below); without a choice the first free slot, `P0000` on an empty stick |
| PROFILE screen LOAD (boot) and MAIN MENU > PROFILE > LOAD | LISTLOAD (4) | game `UCUS98612`, save "", list `P0000..P0004`, file `PROFILE.BIN`, buffer 0x40000, focus 0, buttonSwap 1 | the save list with two saves or more; otherwise the only save, `P0000` |
| MAIN MENU > PROFILE > SAVE | LISTSAVE (5) | same block as at NEW | the save list (one save beside four free slots) |
| MAIN MENU > PROFILE > DELETE ("Delete data from your Memory Stick Duo") | 7, which the framework names DELETE and PPSSPP LISTALLDELETE | game `UCUS98612`, save "", no list, file `PROFILE.BIN`, no buffer | the save list of the game's save folders; without a choice, cancelled (before task 039: a delete of the folder `UCUS98612`, which never exists, so 0x80110347 and nothing happened) |

Every request reports status 1, 2, 3, then 4 after ShutdownStart, then 0: without the list the dialog completes in
a few polls; with it the status stays 2 (VISIBLE) while the player chooses, and the game keeps polling and flipping
(below). No other mode appeared (no SIZES, LIST) in these flows.
Besides the dialog the stick is read through sceIo: `ms0:` is walked recursively at start-up (with `disc0:`, before
the first frame), the game lists `ms0:/PSP/SAVEDATA/` once before the intro movie, and it opens
`PPCD00001DLS001/DATA2.BIN` after the title. On the first boot that open fails, the game AUTOSAVEs `DATA1.BIN`,
walks `ms0:` again and creates `DATA2.BIN` with sceIoOpen (flags 0x0202, write and create); on later boots it reads
the 276 bytes back with sceIoRead. After a save (that AUTOSAVE, PROFILE > SAVE) the game walks `ms0:` recursively
again.

## What the dialog shows

On a PSP, LISTLOAD and LISTSAVE are the system's save list: one entry per name in the game's list, with `ICON0.PNG`,
the `SAVEDATA_TITLE` and the `SAVEDATA_DETAIL` ("User name: NAME0000 ..."), or the game's "Empty profile" icon for
a free slot. This is the profile list the player picks from; the game draws no list of its own (choosing LOAD goes
straight from the PROFILE screen to the dialog and, when it closes, to the second profile movie and MAIN MENU).
While the dialog is up the game draws a plain grey screen with a blinking memory stick in the top right corner and
keeps flipping (30 a second) and polling `sceUtilitySavedataGetStatus`; the dialog is drawn over that.

Until task 039 the port drew no dialog and confirmed the first entry: LISTSAVE wrote `P0000` every time, so a second
NEW profile overwrote the first, and LISTLOAD loaded `P0000` whatever else was on the stick (fidelity difference 4).
Since task 039 a list request (LISTLOAD, LISTSAVE, LISTDELETE, and mode 7 without a save name) is answered, in
this order, by:

1. **The input script's `save` answer**, when one is queued (`save P0001`, `save 1`, `save newest`, `save free`,
   `save cancel`; below). It answers the next list request in a window too, without the list.
2. **The save list**, in a shell with a window, when there is a choice: LISTLOAD with two saves or more, LISTSAVE and
   the deletes with any save in the list. The request stays VISIBLE until the player closes it.
3. **The entry a player would want without looking**: LISTLOAD the newest save (by `PARAM.SFO`'s time, which a save
   writes last), LISTSAVE the first free slot, LISTDELETE only the save the game names. With no such entry the
   request is cancelled (result 1) rather than write over or delete a save: LISTSAVE with all five slots full and no
   window, or a delete with no name (the game's PROFILE > DELETE, headless). LISTLOAD with no save is "no data"
   (0x80110307), as before.

So headless, and in a window with nothing to choose, an empty stick behaves as before (the first profile goes to
`P0000`; the suite's and the sweep's routes see no list), a second profile goes to `P0001`, and LOAD loads the newest.
Each answer is logged: `[savedata] LISTSAVE: P0001, the first free slot`, `[savedata] LISTSAVE: the script's answer
"P0000": P0000`, `[savedata] LISTLOAD: the save list is open (2 entries)` and, when it closes, `[savedata] the save
list closed: result 0x00000000`; `PURE_TRACE_SAVEDATA` adds the list (`P0000 (save) P0001 (free) ...`).

### The save list

`host/ui/save_list.cpp`, drawn by the interface over each game frame (`ui::draw_over_game`) as the on-screen keyboard
is, laid out in the PSP's 480x272 pixels after the PSP's own dialog (PPSSPP's `PSPSaveDialog` was read for the
positions; the picture in `ref/save_dialog.png` is described in docs/fidelity.md):

- a banner along the top: Save, Load or Delete;
- the column of entries on the left: the chosen one's icon large (144x80 at 27,97) with a white frame, the others
  smaller above and below it. Each is the save's `ICON0.PNG` (decoded with stb_image and given to ImGui as a texture),
  a free slot the game's own "Empty profile" icon (the request's newData field), dimmed;
- beside it the chosen save's `TITLE` ("Wipeout Pure") over a line, its date, time and size ("2026/10/07   01:02
  366 KB"), its `SAVEDATA_TITLE` ("Profile data") and its `SAVEDATA_DETAIL` (the pilot, gold medals, ranking), or
  NEW DATA for a free slot;
- "X Enter  O Back" along the bottom (the keys, Enter and Esc, when the keyboard was used last).

Up and Down choose; the PSP's Enter picks and its Back (or Triangle) backs out (result 1, which the game takes back
to the PROFILE screen). Which pad buttons those are follows the request's `buttonSwap` (1 in this game: X is Enter)
and the pad mapping (`shell/gamepad.cpp`): X is the south face button (Cross on a PlayStation pad, A on others, `pad
a` in a script) unless the menu's "Confirm button" setting moves it. The keyboard: the arrows, Enter, Esc; the mouse:
click an entry to choose it and again to pick it. Picking a save to write over ("Do you want to overwrite the
data?") or to delete ("This save data will be deleted. Are you sure you want to continue?") asks first, with No
chosen as on a PSP (Left for Yes). Then the work is done and the dialog says "Save completed." (with the new save's
icon, title, date and size), "Load completed." or "Delete completed." until Enter or Back closes it, and the game
gets the result. The list opens on the entry the defaults above would take (the first free slot, the newest save),
so a straight Enter never writes over a save. While it is open the game reads a neutral pad, the menu does not open
(Esc is the list's Back), and the window shows the game's own grey screen behind it.

Differences from the PSP's dialog that remain: the font and the button symbols are the interface's, there is no
fade in or out, mode 7 lists only this game's folders (a PSP lists every save on the stick), and after "Delete
completed." the list closes (result 0) where a PSP goes back to the list until the player backs out.

Consequences:
- The pilot name is not on screen at LOAD with one profile (the list opens only with two). After a LOAD the game
  keeps it in the profile, and SET NAME (MAIN MENU > PROFILE > NEW > YES) is pre-filled with it: "NAME0000" after
  the LOAD, "NAME" on an empty stick. `profile_load.txt` ends on that screen, before NEW saves anything, and
  `tools/save_roundtrip.sh` measures the region variance of the name's last four letters (1545 with the loaded name,
  0 without).
- In a window, PROFILE > SAVE of a loaded profile opens the list on the first free slot; picking the profile's own
  slot writes it back (after the overwrite question). `profile_load.txt` answers it with `save P0000`.

### The script's answer

`save ANSWER` in `PURE_INPUT_SCRIPT` or the live file (both shells; `shell/script_steps.cpp` keeps the queue,
`hle_savedata.cpp` takes from it): ANSWER is a save name of the game's list (`P0001`), a 0-based position in it (`1`;
for mode 7 a position among the game's folders), `newest`, `free` (LISTSAVE only) or `cancel`. One answer per list
request, in the order queued; an answer that names nothing the request can take (a free slot to load from, a name
not in the list) is logged and the request is answered as without one. Queue it a few frames before the press that
makes the request: `2880:save P0000` before `2900:pad a`.

## Autosave

No save happens without the player asking for one, except after a finished race: not after quitting a race from
the pause menu (CONTINUE / RESTART / QUIT), not after leaving SETTINGS or the PROFILE menu (task 014). A finished
race is saved: past a Single Race's results panel, and after each Tournament race but the last, the game shows
PROFILE AUTOSAVED and AUTOSAVEs `P0000/PROFILE.BIN` (41570 bytes of data, as at NEW), and a reboot that LOADs the
profile shows the records and play times the races set (the fidelity audit, task 035, 2026-10-06:
[Saves and records](history/fidelity.md#saves-and-records-item-5)). The game's own save of a loaded profile
(PROFILE > SAVE) works: LISTSAVE writes `P0000` back with the same 41570 bytes and the pilot name intact.

## Download packs (the DLC door)

At boot, before the intro movie, the game lists `ms0:/PSP/SAVEDATA/` and opens `PI.WAD` in every
`UCUS98612D<PACK>` folder it finds. With an empty `UCUS98612DGAMMAPACK1` beside the profile that open fails
(0x80010002, no such file) and the game moves on: nothing else touches the folder, the profile loads and shows,
PROFILE > SAVE still writes `P0000`, the recursive `ms0:` walks list the folder like any other, and the run reaches
its last frame. The folder is not in the game's LISTLOAD list (`P0000..P0004`), so it cannot appear among the
profiles. Real packs (`PI.WAD`, XTEA plus a signature trailer, docs/research.md) are for later.

## The PSP's format: mode 1 (task 045)

A request that carries no game key (this game's 0x5DC-byte block has no key field; a longer block with a zero key is
the same) is written by a PSP in the save-data utility's no-key mode, mode 1, with the console's fixed keys alone, as
PPSSPP's saves of this game show. The framework had all of mode 1 (its reader and its keys, linked from
`crypto_keys_builtin.cpp`, none of it in this repo) but wrote such a save plain. Since task 045:

- `hle_savedata.cpp` marks a request without a key `no_key_mode` when the console's keys are available
  (`savedata_keys_available()`); without them the save stays plain, as before.
- `write_save` enciphers the data file in mode 1: a 16-byte header, then the data at its own length (`PROFILE.BIN`
  41570 + 16 = 41586 bytes, `DATA1.BIN` 768 + 16 = 784, both as PPSSPP's), lists its hash in `SAVEDATA_FILE_LIST`
  (13-byte name, 16-byte hash) and signs `SAVEDATA_PARAMS`: the flag byte 0x01, the mode-1 hash of the whole PARAM.SFO
  at 0x10, and at 0x20 the slot a PSP fills with a hash of its own console key, which no other console checks (the
  framework writes a filler there; PPSSPP's saves carry the same bytes). The other files are written as they were.
- The data file's hash is a CMAC over the stored file in whole 16-byte blocks: a file whose length is not a multiple of
  16 is hashed as if padded with zeros. PPSSPP's `PROFILE.BIN` (41586 bytes) matches its listed hash only that way;
  the framework had only ever written padded files, so its own saves hash as before.
- On the way in (LISTLOAD, LOAD, AUTOLOAD), an encrypted save has PARAM.SFO's hashes checked, then its data file
  against the hash the list keeps for it, then is deciphered. A failed hash is logged (`[savedata] broken save in
  <folder>: PARAM.SFO does not match its hashes in SAVEDATA_PARAMS`, or `PROFILE.BIN does not match its hash in
  PARAM.SFO`) and the request gets 0x80110306 (the data is broken), as a PSP refuses it; a file the save lists no hash
  for has nothing to be checked against and is read as it is. A good load logs, on a line of its own after `loaded
  41570 bytes from ...`: `PROFILE.BIN: mode 1 (no game key), PARAM.SFO's hash verified, the file's hash in
  SAVEDATA_FILE_LIST verified, decrypted`; a mode-1 save: `PROFILE.BIN: mode 1 (no game key), 41586 bytes, its hash
  in SAVEDATA_FILE_LIST, PARAM.SFO signed`.
- A plain save (SAVEDATA_PARAMS flag 0: every save the port wrote before task 045) still loads as it is
  (`PURE_TRACE_SAVEDATA` logs `PROFILE.BIN: plain (SAVEDATA_PARAMS flag 0)`), and the game's next save of it (an
  autosave after a race, PROFILE > SAVE) rewrites it in mode 1, so nobody loses a profile.
- The menu's Import checks a save with the same hashes (`check_save_folder`), so a PSP's or PPSSPP's save imports;
  Export copies a mode-1 save as it is. A plain save from before task 045 is exported plain: Export enciphers a
  plain save only for a game with a key (mode 5), so such a profile goes to a PSP once the game has saved it again.

## Moving saves between a PSP, PPSSPP and the port

A save is one folder, the same on all three: copy the whole folder (`UCUS98612P0000` and its six files; the profile's
slots are `P0000` to `P0004`), never a file of it alone, since PARAM.SFO holds the data file's hash.

| From | To | Copy |
|---|---|---|
| a PSP's memory stick | the port | `PSP/SAVEDATA/UCUS98612P000N` from the stick (USB mode) into `<game dir>/ms0/PSP/SAVEDATA/` (the app's game dir; `game/` in a checkout), or pick the stick's root, its `PSP/SAVEDATA` or the folder in the menu's Import |
| PPSSPP | the port | the same folder from PPSSPP's memory stick (`~/.config/ppsspp/PSP/SAVEDATA/` for the SDL build on macOS; *Memory Stick folder* in its settings otherwise) |
| the port | a PSP or PPSSPP | `<game dir>/ms0/PSP/SAVEDATA/UCUS98612P000N` into the stick's `PSP/SAVEDATA/` (or the menu's Export, which writes a stick's layout) |

The game finds the profile at PROFILE > LOAD (on a PSP and in PPSSPP the system's list, which shows its "User name:"
line; in the port the save list, or the newest save without a window). A folder of the same name on the receiving
side is replaced by the copy: move it aside first if it is to be kept (the menu's Import does that by itself, into
`PSP/SAVEDATA/.backup/`). Renaming a folder to another slot was not tried: PARAM.SFO names the folder too, and its
hash covers that. `PPCD00001DLS001` (the online system's info) need not be copied: every side writes its own at first
boot.

## Running the check

`tools/save_roundtrip.sh` (about 13 minutes, five windowed runs) uses its own stick, `out/014/game/ms0`, emptied
at the start; the checkout's `game/ms0` is not touched. Logs and captures are in `out/014/run{1,2,3,4,5}{.log,/}`.
Runs 4 and 5 (task 039) make the second profile on the stick runs 1 to 3 left (`two_profiles.txt`: LOAD, PROFILE >
NEW, NAME1111, the save list on P0001, Cross; then PROFILE > LOAD, the list of both, Up and Cross on P0000, and SET
NAME shows NAME0000) and restart (`profile_list_load.txt`: the boot LOAD lists both on the newest, P0001, Cross loads
it, SET NAME shows NAME1111), and check that P0000 was not written and that both folders hold their own pilots. The
list's captures are `run4/list-save.png`, `run4/save-completed.png`, `run4/list-load.png`,
`run4/list-load-p0000.png` and `run5/list-boot.png`.

`folder_check` reads the pilot's name from `PROFILE.BIN` as `tools/save_interchange.sh --check` deciphers it, since
the file is enciphered as on a PSP (the change task 045 proposed, applied in its review).

`tools/save_interchange.sh` (about 3 minutes; docs/verification.md, "The save interchange check") moves saves between
the port and PPSSPP both ways on sticks of its own under `out/045/`, and leaves PPSSPP's stick as it found it.
`tools/save_interchange.sh --check FOLDER PROFILE.BIN OUT` writes the decrypted profile of any save folder.

# Save data (task 014, 2026-10-05)

How Wipeout Pure uses the memory stick on this port, from `PURE_TRACE_SAVEDATA=1` and `PURE_TRACE_IO=1` runs of
`config/pad_scripts/main_menu.txt` (profile NEW), `config/pad_scripts/profile_load.txt` (profile LOAD) and probes of
the PROFILE menu. The framework side is `vendor/portablekit/host/hle/hle_savedata.cpp` (the sceUtilitySavedata
dialog) and `host/save_data/savedata_store.cpp` (the folders). `tools/save_roundtrip.sh` checks the round trip.

## Folders

Saves live in `<game dir>/ms0/PSP/SAVEDATA/` (`PURE_GAME_DIR` picks the game dir; `game/` by default), one folder per
save, named game name + save name, files flat in the folder as on a PSP memory stick:

| Folder | Written by | Files (bytes) |
|---|---|---|
| `UCUS98612P0000` (`P%04d`, 0000 to 0004) | profile NEW (save question YES) and PROFILE > SAVE: LISTSAVE | `PARAM.SFO` 4912, `PROFILE.BIN` 41570, `ICON0.PNG` 6742, `ICON1.PMF` 51200, `PIC1.PNG` 172944, `SND0.AT3` 97604 |
| `PPCD00001DLS001` | first boot, before the PROFILE screen: AUTOSAVE of `DATA1.BIN`, then `DATA2.BIN` through sceIo | `PARAM.SFO` 4912, `DATA1.BIN` 768, `DATA2.BIN` 276, `ICON0.PNG` 1451 |
| `UCUS98612G%x` | ghosts (time trial); not exercised yet | |
| `UCUS98612D<PACK>` | download packs (`PI.WAD`), e.g. `UCUS98612DGAMMAPACK1`; never written by the game here | |

The game's parameter block is 0x5DC bytes, the firmware 1.x layout with no key field, so it never asks for
encryption: `PROFILE.BIN` is plain, as it would be on a PSP, and `SAVEDATA_FILE_LIST` (which lists only encrypted
files) is all zeros. `PROFILE.BIN` starts with a word 2, the pilot name padded with spaces (`NAME0000  `) and the
3-letter tag (`AAA`). `PARAM.SFO` of a profile: `TITLE` "Wipeout Pure", `SAVEDATA_TITLE` "Profile data",
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
| Profile NEW, save question YES (frame 4300 in main_menu.txt) | LISTSAVE (5) | game `UCUS98612`, save "", list `P0000..P0004`, file `PROFILE.BIN`, 0xA262 bytes, ICON0 6742, ICON1 51200, PIC1 172944, SND0 97604 | picks the first listed name, `P0000`, writes it, OK |
| PROFILE screen LOAD (boot) and MAIN MENU > PROFILE > LOAD | LISTLOAD (4) | game `UCUS98612`, save "", list `P0000..P0004`, file `PROFILE.BIN`, buffer 0x40000 | picks the first listed save that exists, `P0000`, loads 41570 bytes, OK |
| MAIN MENU > PROFILE > SAVE | LISTSAVE (5) | same block as at NEW | writes `P0000` again, OK |

Every request reports status 1, 2, 3, then 4 after ShutdownStart, then 0: the dialog completes in a few polls. No
other mode appeared (no SIZES, LIST, DELETE) in these flows; PROFILE > DELETE was not exercised (it would delete).
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

This port draws no dialog, windowed or headless: `hle_savedata.cpp` does the work in InitStart and confirms the first
entry, so the screen stays on the game's PROFILE page for the few frames the dialog is "open" and nothing else
appears. Headless and windowed answer the dialog the same way; the difference is that headless runs take no
scripted input (the input script drives the renderer's pad) and stay on Language Selection, so they make no save
at all (even the first-boot AUTOSAVE comes after the title).

Consequences:
- The pilot name is not on screen at LOAD. After a LOAD the game keeps it in the profile, and SET NAME (MAIN MENU >
  PROFILE > NEW > YES) is pre-filled with it: "NAME0000" after the LOAD, "NAME" on an empty stick.
  `profile_load.txt` ends on that screen, before NEW saves anything, and `tools/save_roundtrip.sh` measures the
  region variance of the name's last four letters (1545 with the loaded name, 0 without).
- With several profiles only the first existing slot can be loaded, and LISTSAVE always writes `P0000`, so a second
  NEW profile overwrites the first. A real choice needs a dialog UI in the framework (or an override in the profile).

## Autosave

No save happened without the player asking for one: not after quitting a race from the pause menu (CONTINUE /
RESTART / QUIT), not after leaving SETTINGS or the PROFILE menu. "Profile Autosaving" in the executable is most
likely the save after a race is finished with progress to record; a finished race needs a steered lap (task 012),
so that path is open. The game's own save of a loaded profile (PROFILE > SAVE) works: LISTSAVE writes `P0000` back
with the same 41570 bytes and the pilot name intact.

## Download packs (the DLC door)

At boot, before the intro movie, the game lists `ms0:/PSP/SAVEDATA/` and opens `PI.WAD` in every
`UCUS98612D<PACK>` folder it finds. With an empty `UCUS98612DGAMMAPACK1` beside the profile that open fails
(0x80010002, no such file) and the game moves on: nothing else touches the folder, the profile loads and shows,
PROFILE > SAVE still writes `P0000`, the recursive `ms0:` walks list the folder like any other, and the run reaches
its last frame. The folder is not in the game's LISTLOAD list (`P0000..P0004`), so it cannot appear among the
profiles. Real packs (`PI.WAD`, XTEA plus a signature trailer, docs/research.md) are for later.

## Running the check

`tools/save_roundtrip.sh` (about 7 minutes, three windowed runs) uses its own stick, `out/014/game/ms0`, emptied at
the start; the checkout's `game/ms0` is not touched. Logs and captures are in `out/014/run{1,2,3}{.log,/}`.

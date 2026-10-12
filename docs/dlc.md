# The download packs (DLC)

What the retail executable does with a download pack, read from the code on 2026-10-12 (the planning session;
decompiles under out/dlc/ on the Mac), the plan for supporting them, and what the port does with the twelve US packs
since task 077 ("In the port (task 077)" below: they load unchanged; an install tool and a check). The packs are the
game's data: they live on the player's stick, never in the repository or a release archive (CLAUDE.md), and no key
leaves the executable.

## What the game does

- **Where.** A pack is a save-data folder `UCUS98612D<PACK>` beside the profiles, holding `PI.WAD` (docs/savedata.md,
  "Download packs"). The frontend's root (`FrontendRoot_etc__088b35d8`, FrontendRoot.cpp) lists `ms:\` at boot and
  whenever the memory-stick utility saw the count of pack folders change (`FUN_08897558` counts them;
  `FUN_08898228` state 9 compares and sets `DAT_08aafd14` to reload), and for every folder whose name starts
  `UCUS98612D` it opens `ms:\<folder>\PI.WAD` (`FUN_088a37f0`), checks it (below) and mounts it as the device
  `PI<rest of the name>:` through the WAD file system (`FileSystem_WAD_cpp__088a25f8`, mode 4). The game then reads
  the pack's contents as it reads Data.wad. The port's file layer already serves the folder: with an empty folder the
  open fails with no-such-file and the game moves on (task 014).
- **The check** (`FUN_088a3e90`). The last 256 bytes of PI.WAD are a signature trailer. The game decodes it with two
  key tables in the executable (`DAT_08aaccf4`, `DAT_08aacbf4`, set up by `FUN_088a7ee0`: the region's keys) and
  verifies its checksums (`FUN_088a75fc`), then verifies the payload against it (`FUN_088a3890`). thp.io's write-up
  (https://thp.io/2021/pure-dlc.html) agrees: a region-specific trailer with a checksum of itself, of the payload's
  first bytes and of the whole payload, and the payload enciphered with the region's key. All of it is the game's own
  code; the port runs it as it runs everything else.
- **The console binding** (`FUN_088a7a44`). The trailer carries a 20-byte field (at +0xc4 of the decoded block).
  Zero means unbound: the pack loads on any console. Otherwise it must equal a 20-byte hash (`FUN_088a95a8`, SHA-1 by
  its size) of 26 bytes: the console's 16-byte OpenPSID (`sceOpenPSIDGetOpenPSID`), its 6-byte MAC
  (`sceWlanGetEtherAddr`) and `MPSP`. When it does not match and the game knows the folder, it looks through the
  folder's other files (`FUN_088a7400` picks them by name) for another 256-byte block that passes, which is how a pack
  downloaded in-game was tied to the console that downloaded it. The port answers both calls from the framework's
  HLE (hle_system.cpp, hle_adhoc.cpp), so a bound pack would need the binding console's values, which nobody has; an
  unbound pack needs nothing.
- **The keys and the cipher** (read with the community's converter, https://gitlab.com/thp/wipeout-pure-dlc2dlc,
  and the executable). The two tables `FUN_088a7ee0` hands the decoder are an RSA public key: a 256-byte modulus at
  `DAT_08aaccf4` and the exponent 65537 at `DAT_08aacbf4`. The trailer is a signed block the game recovers with that
  key (`FUN_088a9680`, `FUN_088a9fb0`); only Sony's private key can make one, so a pack cannot be re-signed for
  another region. The payload is an 8-round XTEA stream cipher under a 16-byte key of the pack's own, held in the
  block (the converter's `crypt_with_key`: the keystream from `0x12345678` and the file offset in 8-byte blocks). The
  payload check `FUN_088a3890` streams the whole file through a hash in 8 KB pieces, so a pack with another pack's
  block fails it; the converter's README names the two instructions a cwcheat patch skips for that (US
  0x200A45F4 and 0x200A4690: 0x088A45F4 and 0x088A4690, inside the hash context's set-up `FUN_088a4610`).
- **Regions.** The packs are per region in every respect: the folder's game ID, the RSA key, the per-pack cipher
  keys, and the WAD compression: the European game (UCES-00001, the newest build) packs with zlib, which the US and
  Japanese builds cannot read, so the converter refuses a European source outright. The US packs, by the
  community's key list: `UCUS98612DCLASSICPACK1` to `3`, `DDELTAPACK1` and `2`, `DGAMMAPACK1` to `3`,
  `DPAKDAXTER`, `DPAKJAKX`, `DPAKSOCOM3`, `DPAKSOCOMFTB` (twelve). The set Erik found on 2026-10-12 ("WipEout
  pure Complete DLC Pack") is the European one: nineteen `UCES00001D` folders, each `pi.wad`, `PARAM.SFO`
  (CATEGORY MS, `SAVEDATA_TITLE` the pack's name), `TEST.BIN` (16 bytes, the listed save file), icons. The US game
  never opens them (the name test), and could not read them if it did.
- **The strings.** `Downloaded Ships`, `Downloaded ships not allowed` (ad hoc play with a pack ship against a console
  without it), `Download Check`, `Download Error`: the in-game browser's download flow, dead with Sony's server, not a
  part of loading.

## In the port (task 077)

- **The spike** (the planning session, 2026-10-12). The twelve US packs (on the Mac in `$HOME/dlc-packs`, 62 MB; each
  folder holds `PI.WAD` or `pi.wad`, `PARAM.SFO` (CATEGORY MS, TITLE "Wipeout Pure Download", SAVEDATA_TITLE the
  pack's name), `TEST.BIN` (16 bytes), `ICON0.PNG` and `PIC1.PNG`) on a scratch stick, headless on Metal: the
  frontend opened every PI.WAD, LEAGUE SELECTION listed CLASSIC 2, DELTA and GAMMA under ALPHA, TEAM SELECTION gained
  ICARAS, and a Gamma race on Exostra Run ran with its HUD. Nothing in the port needed changing.
- **The warning was the spike's stick.** The spike met a WARNING ("autosave will be disabled until the profile is
  saved from within the profile menu") and went through the menus twice. Its stick had served several runs and held
  five profiles, so main_menu.txt's SAVE PROFILE YES found no free slot (`[savedata] LISTSAVE: no free slot in the
  list; cancelled, nothing overwritten`) and the question stayed up; the route's DOWN presses at 5180 moved it to NO,
  Cross at 5300 picked NO, the game warned that autosave was off, and Cross at 5450 went on to MAIN MENU, where the
  second pass began. The packs play no part in it: on a fresh stick the profile saves to P0000, no warning comes, and
  a pack's league is picked like any other, with DOWN presses on LEAGUE SELECTION from 5180 and single_race.txt's
  confirms (docs/tracks.md, "The download packs' leagues").
- **The profile grows.** With the packs on the stick the game's profile is 68874 bytes (68890 enciphered) instead of
  41570 (41586), presumably for the records of the packs' tracks (the contents were not read). Loading a profile
  saved with the packs in a game without them was not tried.
- **Installing: `tools/dlc_install.sh [--data-dir DIR] [--replace] PACKS`.** Copies the pack folders it finds in
  PACKS (a pack folder, a folder holding them, or its SAVEDATA or PSP/SAVEDATA) into the data directory's stick,
  `<data dir>/ms0/PSP/SAVEDATA/` (by default the app's: docs/release.md, "Download packs"), each after a check
  (tools/purelib/dlc.py): the name is one of the twelve, PI.WAD (either case) and PARAM.SFO are there, and PARAM.SFO's
  SAVEDATA_DIRECTORY is the folder's name; a European pack (`UCES00001D...`) is refused by its name. A pack already on
  the stick is skipped unless `--replace`. One line a folder (installed, replaced, skipped, refused and why), a
  summary, exit 1 when a folder was refused. Its refusals of three hand-made folders: `UCUS98612DNOTAPACK` "is not one
  of the twelve US packs", a `UCUS98612DPAKJAKX` without PI.WAD "no PI.WAD in it", a `UCUS98612DPAKSOCOM3` holding
  Daxter's PARAM.SFO "its PARAM.SFO names the folder UCUS98612DPAKDAXTER".
- **The Esc menu's Import.** The profile lists the twelve pack folders (src/profile/pure_profile.cpp, `kSaveFolders`:
  each with its pack's title, not exported), so System > Import save… takes a pack folder, or a stick or folder of
  them, and its screen names each pack ("Gamma Pack 1 (UCUS98612DGAMMAPACK1)"). The screen's check
  (`check_save_folder`, the framework's) passes five of the twelve, which it then imports: Classic Pack 3, Daxter, Jak
  X, Socom 3 and Socom FTB. It refuses the other seven (Classic 1 and 2, Delta 1 and 2, Gamma 1 to 3) with "NAME is
  missing.", NAME four bytes of garbage: the first 32-byte entry of their PARAM.SFO's SAVEDATA_FILE_LIST holds a word
  that reads as a PSP address (0x08xxxxxx) where a file name belongs, TEST.BIN being the second entry, and the
  framework takes every non-empty entry for a file the save must hold. The protection is not what fails: their
  PARAM.SFO hashes and TEST.BIN's hash verify with the console's keys (`tools/save_interchange.sh --check FOLDER
  TEST.BIN` passes Gamma 1 and Classic 1 as it passes Jak X). Passing them (an entry that is no file name skipped) is a
  vendor change for a task of its own; until then those seven go in with tools/dlc_install.sh or by hand. The game
  itself reads neither TEST.BIN nor the list.
- **The check: `tools/dlc_check.sh --packs PACKS [--out DIR] [--wait SECONDS]`** (README.md). Every run on a fresh
  stick of its own with the packs installed by tools/dlc_install.sh, headless on Metal: the selection run with
  `PURE_TRACE_IO` (PI.WAD opened in each of the twelve folders; league_select and team_select changed against the
  references, which have no packs), a race on the first track of Gamma, Delta and Classic 2 (the HUD in at least 4 of
  6 shots from 7100 to 7600, the `[guest] Track Allocated` line, and the league's TRACK SELECTION at least 5% off
  Alpha's, `ref/track_select.png`, so a route that missed the pack league and raced Vineta K fails), no `[hle-stub]`
  line for a call a pack's loading could make, and the cost. 2026-10-12: twelve folders of twelve (164 opens),
  league_select 0.0130 (the bar 0.01), team_select 0.0047 (0.003), the HUD in 6 of 6 shots of each race, Track
  Allocated 7821 KB on Exostra Run, 5826 KB on Iridia and 5003 KB on Vohl Square, TRACK SELECTION 0.1271, 0.1079 and
  0.1067 off Alpha's, no `[hle-stub]` line at all: PASS, about 45 s. With no pack installed (the three bad folders) it
  FAILs: 0 of 12 opened, both screens 0.0000, each race on Vineta K (Track Allocated 6492 KB, TRACK SELECTION
  0.0000).
- **The cost.** A boot to MAIN MENU (4700 flips, headless and unpaced) takes 2.4 to 2.6 s with the twelve packs and
  2.2 s without (the check's runs, twice each, 2026-10-12; the spike measured 3.2 s against 2.7 s): the frontend opens
  and checks every pack at start-up.

## What the port needs

Answered by the spike and task 077, with the twelve US packs:

1. The preserved US packs load on the port with no console values: they are unbound, or were re-signed unbound by
   thp.io's converter.
2. Nothing on their path hits a gap in the HLE: the mount, the packs' WAD reads and three pack races run with no
   `[hle-stub]` line.
3. Memory: a pack's track loads into the PSP's 32 MB as the disc's do.

Still open: references of the pack screens from PPSSPP (the check compares against the screens without packs); the
seven packs the menu's Import refuses (above); a profile saved with the packs loaded without them; ad hoc play with a
pack's ship ("Downloaded ships not allowed"), which the port does not offer yet.

## The plan

0. **The European set is not usable** (above). If the US set cannot be found, a fallback exists but is a
   milestone, not a task: the payload deciphered with the published per-pack keys (a third-party file, never
   committed), the zlib entries inflated by a port hook in the WAD reader or the WADs rebuilt with LZSS, the
   signature check answered by a port hook at the two instructions above, and the folders renamed. Not needed: the US
   packs were found.
1. **Erik obtains the US packs**: done 2026-10-12, kept outside the repository as the disc image is. `ref/` holds no
   PPSSPP capture with the packs yet (the Downloads screen, a pack league, a pack track).
2. **A spike on the port**: done 2026-10-12 (above); no HLE gap.
3. **Task 077, the installer and the check**: done: tools/dlc_install.sh, tools/dlc_check.sh, the routes
   (config/pad_scripts/gamma_race.txt, delta_race.txt, classic2_race.txt) and the profile's pack folders, through
   which the save screen's Import takes five of the twelve. Not done: an "Import download pack..." row of its own in
   the Esc menu, the comparison with PPSSPP references, and the seven packs' import (a vendor change, above).
4. **D-005 can close** (the save layout is DLC-ready by construction: sibling folders, and the packs load from them);
   docs/decisions.md is the planning session's to update. D-012's loader entry waits for the expanded version as
   decided.

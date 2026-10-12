# The download packs (DLC)

What the retail executable does with a download pack, read from the code on 2026-10-12 (the planning session;
decompiles under out/dlc/ on the Mac), and the plan for supporting them. Nothing here is implemented yet. The packs
are the game's data: they live on the player's stick, never in the repository (CLAUDE.md), and no key leaves the
executable.

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

## What the port needs

Little, if the packs are unbound: the folders in the data directory's `ms0/PSP/SAVEDATA/`, the open and reads of
PI.WAD (served), the two identity calls (served), the WAD mount and the decode (the game's). The unknowns are what a
real pack does on this port, which only a real pack can answer:

1. whether the preserved US packs (Gamma 1 to 3, Delta, Classic 1 to 3, the four hidden packs; about 63 MB in all,
   docs/research.md) are unbound, or were re-signed unbound by thp.io's converter;
2. whether anything in the loading path the empty-folder test never reached (the mount, the pack's own WAD reads, a
   PARAM.SFO read through the save-data utility for the pack's title) hits a gap in the HLE;
3. memory: a pack's files load into the same 32 MB the PSP had, so the port needs no more.

## The plan

0. **The European set is not usable** (above). If the US set cannot be found, a fallback exists but is a
   milestone, not a task: the payload deciphered with the published per-pack keys (a third-party file, never
   committed), the zlib entries inflated by a port hook in the WAD reader or the WADs rebuilt with LZSS, the
   signature check answered by a port hook at the two instructions above, and the folders renamed. Not planned
   unless the US packs stay out of reach.
1. **Erik obtains the US packs** (the PSP save-data folders, each with PI.WAD and PARAM.SFO) from the preserved
   copies and keeps them outside the repository, as the disc image is. PPSSPP first: the packs in its memory stick's
   `PSP/SAVEDATA/`, the game started, the Downloads screen and a pack track reached. That proves the files before the
   port sees them, and gives the references (`ref/`, ignored) for the checks.
2. **A spike on the port**: one pack folder on a scratch stick, a headless run with `PURE_TRACE_IO`, the opens, reads
   and the mount followed; then a window run to the Downloads screen. Any HLE gap found becomes a task.
3. **Task: the installer and the check.** an install tool (dlc_install, under tools/) copies pack folders into the data directory's
   stick (validating the folder name and PI.WAD's presence), the Esc menu gets an "Import download pack..." row like
   the texture pack's when the shell work is cheap, and a check (dlc_check, under tools/) boots with the packs, reaches the
   Downloads screen and a pack track's race HUD, and compares with the PPSSPP references. Docs: this file, the
   release notes (where packs go), docs/savedata.md.
4. **D-005 closes** (the save layout is DLC-ready by construction: sibling folders), and D-012's loader entry waits
   for the expanded version as decided.

# 045: Saves in the PSP's own format (fidelity difference 5)

Milestone: M8 | Branch: task/045-savedata-no-key-mode | Status: OPEN

## Goal
A PSP (and PPSSPP) encrypts Wipeout Pure's saves in the save-data utility's no-key mode (mode 1): the game's
parameter block is the firmware 1.x layout with no game key, so the data file is enciphered with the console's fixed
keys, its hash kept in PARAM.SFO's SAVEDATA_FILE_LIST and the SAVEDATA_PARAMS hashes filled in. The framework does all
of this when a game key is given and writes a plain file when none is, so a save from a PSP or PPSSPP does not load in
the port and a port save would not load on a PSP. The framework's reader already understands mode 1 and its builtin
keys file (linked into our build; nothing of it is in our repo and nothing of it may ever be) has the keys. This task
makes the writer use mode 1 when the game gives no key, verifies mode-1 saves on the way in, and proves the interchange
both ways with PPSSPP, as patch 0019.

## Read first
- CLAUDE.md (keys: never commit, never copy a key value anywhere, never print one), docs/savedata.md, docs/fidelity.md
  (item 5 "Saves and records" and difference 5), docs/tasks/014 and 039 (Results), docs/ppsspp.md (the driver: its
  memstick, routes, screenshots)
- vendor/portablekit/host/hle/hle_savedata.cpp (the parameter block, the key field, where `files.key` is set and the
  plain path), host/save_data/savedata_crypto.hpp and .cpp (modes, hashes, the cipher; `savedata_keys_available`),
  savedata_store.cpp (the read path's mode handling, including Mode1), save_transfer.hpp (import and export),
  host/crypto_keys.hpp (the seam; read `crypto_keys_builtin.cpp` only to know it is linked, never quote it)
- The published description of the save-data protection, read only: the PSP save-data encryption as documented by
  the homebrew SaveTool and PPSSPP's hardware notes if they cover it (the modes' flag byte, the hash of PARAM.SFO,
  the file hash); PPSSPP's source may not be read or copied

## Deliverable
1. Patch 0019 (`tools/patches.sh export 0019-savedata-no-key-mode`): when the game's request has no key (the 0x5DC
   block, or a zero key) and the keys are available, the data file is written in mode 1 with its hash in
   SAVEDATA_FILE_LIST and SAVEDATA_PARAMS's flag and hashes as a PSP writes them; a mode-1 save is verified on the way
   in (a failed hash is reported in the log and the save is refused as a PSP would, unless the request does not
   check); a plain save (flag 0, every save the port has written until now) still loads, so nobody loses a profile;
   without the keys the behaviour is today's. Import and export keep working with mode-1 saves. No key value appears
   in any file, log or doc of ours; the patch adds no key material.
2. The check, repeatable, `tools/save_interchange.sh`: (a) a profile saved by PPSSPP (the driver's frontend route
   through profile creation and the save; the save folder kept under ref/saves/ppsspp/, git-ignored, its files'
   SHA-256 in ref/README.md) copied into a fresh port memory stick loads: the port run headless with `PURE_TRACE_SAVEDATA`
   and the input script's `save` answer, the main menu reached with that profile's name (a shot compared with the
   suite's main_menu reference, or the game's own profile-name line); (b) a profile saved by the port (the round trip's)
   copied into PPSSPP's memstick loads in PPSSPP: the driver's route to the main menu with a screenshot that shows the
   profile name; (c) the port's save against PPSSPP's for the same profile name: PARAM.SFO's fields and the flag byte
   equal, both files verify under the framework's own hash check, the decrypted contents compared and their
   differences listed (timestamps and the like are expected; anything else is reported). PASS when (a) and (b) load
   and (c) verifies both.
3. `tools/save_roundtrip.sh` unchanged and passing; task 039's save-list check still passing (its Verify line).
4. docs/savedata.md (the format now written, the interchange procedure for a player: where to copy a PSP save),
   docs/fidelity.md (item 5 and row 5 resolved with the check's figures), docs/verification.md (the check),
   patches/README.md (the row), README.md (the tool's row).

## Acceptance criteria
- [ ] `tools/save_interchange.sh` passes both directions; `tools/save_roundtrip.sh` passes; `tools/patches.sh check`
      passes (18 patches); `tools/frame_regress.sh --only race_hud` unchanged.
- [ ] A plain save written by the previous build still loads (the script checks one).

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/save_roundtrip.sh && tools/save_interchange.sh && tools/frame_regress.sh --only race_hud`

## May touch
- vendor/portablekit/host/hle/hle_savedata.cpp, host/save_data/ (not crypto_keys_builtin.cpp, never) via
  `tools/patches.sh export 0019-savedata-no-key-mode`; patches/; tools/save_interchange.sh (new); tools/ppsspp/routes/;
  ref/README.md; docs/savedata.md, docs/fidelity.md, docs/verification.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/crypto_keys_builtin.cpp, host/gpu/, host/kernel/, src/, config/,
  tools/save_roundtrip.sh, tools/frame_regress.sh, tools/campaign_sweep.py, earlier patches

## Estimated turns
50

## Escalate when
The mode-1 writer needs key material the builtin keys do not hold (report which slot or index by name only), a PPSSPP
save fails the hash check under the scheme the framework implements (report the hash inputs by description, never
values), or the game's request turns out to carry a key after all (report the block's layout).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

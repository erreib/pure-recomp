# 045: Saves in the PSP's own format (fidelity difference 5)

Milestone: M8 | Branch: task/045-savedata-no-key-mode | Status: MERGED (1bbd6bd, 2026-10-07; PARTIAL resolved by the round-trip fix ff53240)

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
Status: PARTIAL. Deliverables 1, 2 and 4 are done, and `tools/save_interchange.sh` passes both directions. Deliverable 3 cannot pass as briefed: `tools/save_roundtrip.sh` (Must not touch) reads the pilot's name from `PROFILE.BIN` as plaintext in its `folder_check`, and mode 1 enciphers that file. So 7 of its 73 checks fail, one for each folder it checks, all of them the line "PROFILE.BIN holds pilot". The other 66 pass: every load, save, save-list step and SET NAME capture. Verify stops at that step. A ten-line change to `folder_check` is proposed under Open questions; I tested it against the round trip's own stick and it gives 0 failures. I did not apply it.

Changed:
- `patches/0019-savedata-no-key-mode.patch` (new; touches `host/hle/hle_savedata.cpp`, `host/save_data/savedata_store.{hpp,cpp}`, `host/save_data/savedata_crypto.{hpp,cpp}`):
  - **Request without a key** (the 0x5DC block, or a zero key). When `savedata_keys_available()` is true, the request sets `SaveFiles::no_key_mode`.
  - **Writing.** `write_save` then writes mode 1. The data file is the 16-byte header plus the data at its own length (41586 bytes for the 41570-byte profile, as PPSSPP writes it). Its hash goes in `SAVEDATA_FILE_LIST`. `SAVEDATA_PARAMS` gets flag 0x01 and the mode-1 hash of PARAM.SFO. `write_flags()` reports which mode a request gets.
  - **Data-file hash.** `data_file_hash` now hashes a file whose length is not a multiple of 16 as if it were padded with zeros to one. The framework's own files were always padded, so their hashes do not change.
  - **Loading.** `load_save` checks PARAM.SFO's hashes before the data file's, for every encrypted save. It also reports the flag and whether the file's listed hash was checked.
  - **Log lines.** `do_load` and `do_save` print mode-1 lines of their own; the existing `loaded ...`/`saved ...` lines keep their form. A failed hash logs `broken save in ...` and the load returns 0x80110306.
  - **Plain saves and no keys.** Plain saves still load. Without the keys, behaviour is as before.
  - No key material is in the patch: every key is fetched with `crypto_keys()` by slot.
- `patches/README.md`: row 0019.
- `tools/save_interchange.sh` (new): (a), the plain save, the port's own profile ("born"), (b) and (c).
  - `--port-only` skips (b) and exits 3.
  - `--check FOLDER FILE [OUT]` runs one save folder through the framework's `load_save` and hash checks and writes the decrypted file.
  - `--make-ppsspp-save` remakes PPSSPP's reference save.
  - The checker is built into `out/045/savecheck` from the vendor save-data sources plus the linked `crypto_keys_builtin.cpp`. It prints no key and no hash value.
- `tools/ppsspp/routes/save_dialog.txt` (new): closes PPSSPP's "Save completed." after `save_yes.txt`. That route referred to this file, which did not exist.
- `tools/ppsspp/routes/profile_load.txt` (new): LOAD → the load dialog → Enter → "Load completed." → Back → MAIN MENU → PROFILE > NEW > YES → SET NAME.
- `ref/README.md`: "Saves (task 045)" section (how each save was made, and the SHA-256 of all 16 files).
- Reference saves (git-ignored), in `ref/saves/` and also copied to the main checkout's `ref/saves/`:
  - `ref/saves/ppsspp/UCUS98612P0000`: PPSSPP's NAME0000/AAA, made by `frontend.txt` + `save_yes.txt` + `save_dialog.txt`.
  - `ref/saves/ppsspp/PPCD00001DLS001`: PPSSPP's first-boot autosave.
  - `ref/saves/port-plain/UCUS98612P0000`: a plain save from batch/m2 at aa9128a (`main_menu.txt`, headless).
- Docs:
  - `docs/savedata.md`: the format now written; the player's procedure for moving a save between a PSP, PPSSPP and the port; what the round trip's folder check meets.
  - `docs/fidelity.md`: item 5 and row 5 resolved, with the figures.
  - `docs/verification.md`: a new section on the check.
  - `README.md`: the tool's row.

The check's figures (`tools/save_interchange.sh`, 2026-10-07, PASS twice, in out/045/full1.txt and full3.txt):

**(a) PPSSPP to the port.**
- The framework's checker verifies PPSSPP's save: PARAM.SFO hash OK, PROFILE.BIN listed hash OK, 41586 bytes in, 41570 bytes decrypted.
- In the port, headless `profile_load.txt`:
  - LISTLOAD logs `loaded 41570 bytes` and `PROFILE.BIN: mode 1 (no game key), PARAM.SFO's hash verified, the file's hash in SAVEDATA_FILE_LIST verified, decrypted`.
  - MAIN MENU differs from `ref/main_menu.png` by 0.011.
  - SET NAME's digit-region variance is 1531 (NAME0000; the empty-stick control is 0).
- The game's PROFILE > SAVE wrote P0000 back in mode 1 (41586 bytes). Its PARAM.SFO reads "User name: NAME0000", and the save verifies.

**Plain save from the previous build.** It loads as flag 0, shows the same MAIN MENU (0.011) and SET NAME (1531), and the game's next save rewrites it in mode 1, which verifies.

**(b) The port to PPSSPP.** Using (a)'s round-trip save, PPSSPP's load dialog lists it ("User name: NAME0000"), then shows "Load completed.".
- MAIN MENU at 3720 is 0 pixels from `ref/main_menu.png`.
- SET NAME at 4560 has variance 1525 and is pixel for pixel the port's SET NAME from (a) (fraction 0.000000).
- In the digit region it differs from the empty stick's SET NAME by 0.436.
- PPSSPP left the save unchanged, and the stick was left as it was found (only `PPCD00001DLS001`).

**(c) Side by side.** Both sides verify under the framework's checks in every pair.
- **PARAM.SFO** (all pairs): both 4912 bytes, with the same keys, formats, lengths and values. The only differences are the two hashes that cover the random header: the file's hash in `SAVEDATA_FILE_LIST` and SAVEDATA_PARAMS 0x10. The flag byte is 0x01 on both, and the 0x20 "console" slot is the same bytes.
- **Media files** (all pairs): ICON0, ICON1, PIC1 and SND0 are byte-equal.
- **The port's own NEW profile against PPSSPP's.** 71 of 41570 decrypted bytes differ, all inside 69 words that hold user-RAM addresses. Each is 0x200 higher in the port (for example 0x08ECAF10 against 0x08ECAD10): the profile stores pointers into the game's heap verbatim, and the port's heap sits 512 bytes higher. There are no timestamps or counters, and nothing else differs.
- **The round trip's save against PPSSPP's.** The same 71 bytes differ, so the game rewrites those pointers on every load.
- **PPCD00001DLS001.** DATA1.BIN is identical once decrypted. DATA2.BIN, which the game writes itself through sceIo, differs in 273 of 276 bytes; it is reported, not checked.

Escalation conditions:
- **Key material:** none needed beyond the builtin keys. Mode 1 uses the KIRK slots for its hash, header and stream, all present.
- **The game's request:** it carries no key (size 0x5DC, every request).
- **PPSSPP's hash check (needs your review):** PPSSPP's `PROFILE.BIN` initially failed the framework's file-hash check as written.
  - PARAM.SFO's hash and DATA1.BIN (784 bytes, a multiple of 16) matched as written.
  - PROFILE.BIN (41586 bytes) matched only when hashed as the stored file zero-padded to 41600 bytes: header plus ciphertext plus 14 zero bytes, under the mode-1 CMAC with no game key.
  - Other inputs did not match: the bare file, the header-less data, or the ciphertext of the zero-padded plaintext.
  - The scheme (key slot, masks, cipher) is the framework's unchanged; only how the input is padded differed. I took that as the documented aligned-length hashing rather than a scheme failure and fixed it inside May touch. Please check that this is the reading you want.

Other runs:
- `tools/frame_regress.sh` (task 039's Verify remainder): 18/18 pass, headless Metal.
- `--only race_hud`: 0.0148.
- `tools/patches.sh check`: ok, 18 patches.
- The framework's own `tests/savedata_tests.cpp`, built by hand in the scratchpad (not in the build): 81 ok, 0 failures with the patch, including the mode-5 import and export cases.

Verify output (`tools/verify_task.sh 045`, last 20 lines; it stops at save_roundtrip.sh):
```
        UCUS98612P0001: ICON0.PNG 6742, ICON1.PMF 51200, PARAM.SFO 4912, PIC1.PNG 172944, PROFILE.BIN 41586, SND0.AT3 97604
  ok    PARAM.SFO present
  ok    PROFILE.BIN present
  ok    ICON0.PNG present
        TITLE = 'Wipeout Pure'
        SAVEDATA_TITLE = 'Profile data'
        SAVEDATA_DIRECTORY = 'UCUS98612P0001'
        SAVEDATA_DETAIL = 'User name: NAME1111  \nGold medals awarded: 0\nRanking: Rookie'
  ok    PARAM.SFO SAVEDATA_DIRECTORY is UCUS98612P0001
  ok    PARAM.SFO detail names the pilot NAME1111
        SAVEDATA_FILE_LIST = PROFILE.BIN
  FAIL  PROFILE.BIN holds pilot 'ÖYÔpf.ã\\Oj´', tag 'Çè\x8eø'

run 1 NEW (main_menu.txt, empty stick): FAIL (1 checks, see above)
run 2 LOAD (profile_load.txt): FAIL (1 checks, see above)
run 3 DLC door (+ empty UCUS98612DGAMMAPACK1): FAIL (1 checks, see above)
run 4 second profile (two_profiles.txt): FAIL (2 checks, see above)
run 5 restart LOAD (profile_list_load.txt): FAIL (2 checks, see above)
save round trip: FAIL (7 checks)
verify 045: FAIL (exit 1)
```

Open questions:
- **Incident on PPSSPP's shared stick (needs the coordinator).** At 10:58 my second interchange run copied the port's save onto PPSSPP's stick just as the scorecard worker's PPSSPP started (pid 15907, launched 10:58:03, log under `agent-a95655a8ebcce75af/ref/scorecard/...`). The save sat on the stick for about 1.5 minutes of that run, until I stopped my run at 10:59:37 and its trap moved the save out. That scorecard run may have seen a `UCUS98612P0000` at boot or at the PROFILE screen, so it is worth re-running. The script now copies the save only right before its own launch, once PPSSPP is free, and takes it out again if the launch is refused (8ec462b). The later run (full3) waited for PPSSPP with the stick clean.
- **save_roundtrip.sh.** Proposed change (out/045/save_roundtrip.proposed.diff): `folder_check` runs `rm -f "$OUT/$folder.plain"; tools/save_interchange.sh --check "$SAVE/$folder" PROFILE.BIN "$OUT/$folder.plain"`, adds an ok/FAIL on its verdict, and reads the pilot from the decrypted file. It also rewords the "list stays empty" comment. Tested against the round trip's stick: P0000 → 'NAME0000'/'AAA' and P0001 → 'NAME1111'/'AAA', 0 failures. The diff:
  ```
  --- tools/save_roundtrip.sh	2026-10-07 09:45:39
  +++ tools/save_roundtrip.sh (proposed)	2026-10-07 10:25:11
  @@ -76,9 +76,12 @@
   # $FOLDER, $NAME). Exit code = failures.
   folder_check() {
     local folder=${1:-$FOLDER} pilot=${2:-$NAME}
  -  python3 - "$SAVE/$folder" "$folder" "$pilot" <<'EOF'
  +  # Since patch 0019 PROFILE.BIN is enciphered as on a PSP (mode 1): the framework's load path deciphers it.
  +  rm -f "$OUT/$folder.plain"
  +  tools/save_interchange.sh --check "$SAVE/$folder" PROFILE.BIN "$OUT/$folder.plain" > "$OUT/$folder.check.txt" 2>&1
  +  python3 - "$SAVE/$folder" "$folder" "$pilot" "$OUT/$folder.plain" "$OUT/$folder.check.txt" <<'EOF'
   import os, struct, sys
  -folder, expect_dir, expect_name = sys.argv[1:4]
  +folder, expect_dir, expect_name, plain, report = sys.argv[1:6]
   fails = 0
   def ok(m): print("  ok    " + m)
   def bad(m):
  @@ -115,13 +118,14 @@
   print("        SAVEDATA_DETAIL = " + repr(sfo.get("SAVEDATA_DETAIL", "")))
   (ok if sfo.get("SAVEDATA_DIRECTORY") == expect_dir else bad)(f"PARAM.SFO SAVEDATA_DIRECTORY is {expect_dir}")
   (ok if f"User name: {expect_name}" in str(sfo.get("SAVEDATA_DETAIL", "")) else bad)(f"PARAM.SFO detail names the pilot {expect_name}")
  -# SAVEDATA_FILE_LIST names encrypted files only. The game's request is 0x5DC bytes (no key field), so its saves
  -# are plain and the list stays empty; PROFILE.BIN is checked as plaintext below.
  +# SAVEDATA_FILE_LIST names encrypted files only: PROFILE.BIN since patch 0019 (mode 1, as a PSP writes it),
  +# nothing in a plain save of an earlier build. PROFILE.BIN is checked as the framework deciphers it.
   listed = sfo.get("SAVEDATA_FILE_LIST", b"")
   listed = [listed[i:i + 13].split(b"\0")[0].decode("latin-1") for i in range(0, len(listed), 32) if listed[i:i + 1] not in (b"", b"\0")]
   print("        SAVEDATA_FILE_LIST = " + (", ".join(listed) if listed else "empty (plain save)"))
  -if "PROFILE.BIN" in files:
  -    prof = open(os.path.join(folder, "PROFILE.BIN"), "rb").read()
  +(ok if "verdict PASS" in open(report).read() else bad)("PROFILE.BIN verifies and deciphers (tools/save_interchange.sh --check)")
  +if "PROFILE.BIN" in files and os.path.exists(plain):
  +    prof = open(plain, "rb").read()
       name = prof[4:15].split(b"\0")[0].decode("latin-1").strip()
       tag = prof[15:19].split(b"\0")[0].decode("latin-1")
       (ok if name == expect_name else bad)(f"PROFILE.BIN holds pilot {name!r}, tag {tag!r}")
  ```
  Once it is applied, Verify can pass as written. Task 039's Verify line meets the same seven checks.
- **Export.** A plain save from before patch 0019 is still exported plain: `encrypt_plain_save` only enciphers when the game has a key (mode 5). Such a profile becomes PSP-ready at the game's next save (an autosave, or PROFILE > SAVE). Teaching Export mode 1 would need a remembered "this game saves without a key".
- **Mode 5.** I left it as it was: still padded to 16 bytes, with no oracle to check against. A PSP most likely stores mode-5 data unpadded too.
- **The heap 0x200 higher than PPSSPP's** at profile time is a small layout difference in the port's allocator or start-up, not a save problem. Not chased.
- **Save headers.** Each save's 12-byte header seed comes from `random_device`, as before. Two port saves of the same profile therefore differ in ciphertext and hashes, as on a PSP.


## Review
Verify rerun: PASS from the main checkout at ff53240 (2026-10-07), in two parts because the scorecard worker held the
machine: `tools/verify_task.sh 045` ran patches check (18), the build, the save round trip (PASS, every folder check
with the deciphered profile) and the interchange (a, plain, b, c all PASS, verdict PASS on every pair) and was refused
at the last step by the one-game guard; `tools/frame_regress.sh --only race_hud` then passed on its own (0.0148).
PPSSPP's memory stick holds only PPCD00001DLS001 afterwards.

Spot-read: patch 0019 (mode 1 chosen only when the keys are available and the request has no key; the data file at
its own length with the 16-byte header; PARAM.SFO's hashes checked before the file's; a failed hash returns
0x80110306; plain saves load as flag 0; no key material, every key by slot through `crypto_keys()`), the hash
alignment change (a file not a multiple of 16 hashed as zero-padded: the framework's own files were always padded so
nothing changes for them, and PPSSPP's file verifies only this way), tools/save_interchange.sh (the stick restored by
a trap; the checker built from the vendor sources, printing no key or hash value). Files outside May touch: none.

Merged: 1bbd6bd into batch/m2; the worker's proposed change to tools/save_roundtrip.sh applied from the main checkout
as ff53240 (the brief had put that tool off limits, which is why the worker reported PARTIAL).

Notes: accepted the aligned-length hashing as the documented reading: the scheme and keys are untouched and both
directions verify. Export of a pre-0019 plain save stays plain until the game's next save rewrites it in mode 1
(follow-up). The 69 heap pointers the profile stores verbatim sit 0x200 higher in the port than in PPSSPP: a
start-up or allocator layout difference, harmless for saves, recorded as a follow-up. The incident on the shared
PPSSPP stick (10:58) was reported to the scorecard worker, which redoes the affected reference.

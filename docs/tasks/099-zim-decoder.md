# 099: The HD texture pack on Vulkan: a ZIM decoder with zstd

Milestone: HD pack (D-024) | Branch: task/099-zim-decoder | Status: OPEN

## Goal
The Vulkan renderer draws NR74W's HD texture pack. Today the framework's pack loader parses the pack's `textures.ini`
and finds its keys, but every image is a ZIM file (PPSSPP's container, zstd-compressed RGBA8) and the loader decodes
PNG only, so each hit ends in `[texpack] cannot use ...`. After this task the loader decodes ZIM, the build carries
Zstandard's decoder as a pinned source download, and a check run with the pack's folder counts the replacements drawn
on the race and menu routes. D-024 records the choices; the Metal backend's loader is task 100.

## Read first
- docs/decisions.md, D-024 (the format facts, the dependency's shape, what was not chosen).
- vendor/portablekit/host/gpu/texture_pack.cpp: `TexturePack::decode` (line 595 to 650) and `Replacement`
  (texture_pack.hpp 45 to 76); `load_ini`'s `[hashes]` branch (408 to 424) for how a file name reaches `decode`.
- vendor/portablekit/cmake/FFmpeg.cmake, `_portablekit_ffmpeg_fetch` (80 to 105): the download helper's shape.
- vendor/portablekit/docs/SOURCE_PROVENANCE.md, "Third-party components" (the table a dependency joins).
- packaging/THIRD_PARTY_NOTICES.md (the notice a dependency gets; the read-mes name the notices).
- tools/sprite_pack.sh, the header (lines 1 to 50) and the check's reader (277 to 300): the `[texpack]` lines it
  counts and the PASS rules; `--pack DIR` is the mode this task extends.
- patches/README.md, the table's shape and the section of 0012-texture-decode-exports (a host/gpu patch).
- docs/release.md, "The texture pack (task 074)" (where a pack goes in the data directory, the Texture pack row).

## Facts
- The pack: `~/Downloads/WipEout-Pure-HD-Texture-Pack` on this Mac (a shallow clone; 872 MB; 1331 `.zim` under
  `in_game/`, `main_menu/`, `font/`, `intro/`; `textures.ini` 5645 lines, `[options]` version 1, hash xxh64,
  ignoreAddress, ignoreMipmap; `[games]` lists eight editions, UCUS98612 among them; `[hashes]` 4172 keys of 24 hex
  digits, 73 of them with an empty value). It is derived art: never copied into the checkout, out/, a patch or a
  task file; the check takes its folder on the command line.
- Every ZIM in it: header `ZIMG`, width, height, flags as little-endian 32-bit words (16 bytes), flags 5120 on all
  1331 (ZSTD_COMPRESSED 4096 and ETC1_MEDIUM 1024; format bits 0 = RGBA8888), no HAS_MIPS. The payload is one zstd
  frame whose decompressed size is width x height x 4. Python's `zlib` refuses them all (the first two bytes are
  `28 b5`, zstd's magic), which is how the survey told zstd from zlib.
- The format in general (PPSSPP's ZIMLoad, read for facts): format mask 15 (0 RGBA8888 4 bytes, 1 RGBA4444 and 2
  RGB565 2 bytes, GL's bit order: 4444 has R in bits 12 to 15, A in 0 to 3; 565 has R in 11 to 15, B in 0 to 4);
  HAS_MIPS 16 (levels largest first, contiguous, `floor(log2(min(w, h))) + 1` of them, at most 12); GEN_MIPS 32,
  DITHER 64, CLAMP 128 (hints, ignored); ZLIB_COMPRESSED 256 (a zlib stream with its 2-byte header);
  ZSTD_COMPRESSED 4096; ETC1 flags 512, 1024, 2048 (quality hints; no ETC1 pixel format exists in the loader). Any
  format other than 0, 1, 2 is refused. Neither compression flag: the payload is raw and must be exactly the size.
- stb_image in the loader already exposes `stbi_zlib_decode_malloc_guesssize_headerflag(buffer, len, guess,
  &outlen, parse_header=1)` for the zlib case. zstd's API: `ZSTD_decompress(dst, dstCapacity, src, srcSize)` returns
  the size or an error (`ZSTD_isError`); `ZSTD_getFrameContentSize` can cross-check the header's size.
- zstd 1.5.7: https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz, SHA-256
  eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3, 2434947 bytes; licence `LICENSE` (BSD) and
  `COPYING` (GPLv2) at its root; the decoder is `lib/common/*.c` plus `lib/decompress/*.c` with `lib/` and
  `lib/common/` on the include path, `ZSTD_DISABLE_ASM=1` so `huf_decompress_amd64.S` is not needed. The Mac has
  `/opt/homebrew/opt/zstd` but the build must not use it (the rig has none; the bundles are self-contained).
- The loader's limits: `kMaxImageSide` 8192, `kMaxDecodedBytes` 256 MB of decoded pixels in flight, the renderer's
  GPU budget `PURE_TEXTURE_PACK_MEMORY` (MB, default 1024), `kMaxResident` 4096 images. The pack's largest images
  are 4096x4096 (64 MB each as RGBA8) and 1920x1080 (155 of them, the menus' backgrounds).
- The probe of 2026-10-20 (`tools/sprite_pack.sh --pack ~/Downloads/WipEout-Pure-HD-Texture-Pack --out
  out/hdpack-probe`, the current loader, the Vulkan window on the Mac, 3 min 28 s): the keys match. The pack opened
  with 4170 keys on both routes; the race route hit 179 keys (126 `cannot use NAME.zim: unknown image type`, the
  decoder's gap; 52 `missing or unreadable`, files the ini names that the pack does not hold), the menu route 11.
  The check FAILed on three rules: "2549 named files missing" (the reupload holds 1331 files for 4170 keys: a
  fact of the pack, to be counted and reported, not a FAIL for `--pack`), "0 drawn" (the decoder) and the two
  scenes "differ from the capture without the pack in under 1%" (no replacement drawn yet). The renderer logs a
  budget line each traced window: `[texpack] frame F: N draws replaced in 60 frames, M images on the GPU (K MB)`,
  the measurement's source. Logs: out/hdpack-probe/check/on/*.log.
- `PURE_TRACE_TEXTURE_PACK=1` prints each lookup (`[texpack] 0x... WxH ...`, texture_pack.cpp 514) and each decode
  (`[texpack] decoded NAME WxH`, 644).

## Deliverable
- `cmake/Zstd.cmake` in this repository: the framework compiles host/gpu/texture_pack.cpp straight into the game's
  executable target (`portablekit_add_game` in vendor/portablekit/cmake/PortableKit.cmake, the source list at line
  47, `add_library`/`add_executable` of `${target}` near 409), so one `target_link_libraries(<the executable>
  PRIVATE pure_zstd_decoder)` after `portablekit_add_game()` in CMakeLists.txt gives texture_pack.cpp the include
  path and the symbols; no framework CMake changes. The file downloads and verifies the tarball into the build directory (the FFmpeg helper's shape: `.part`
  then rename, `TLS_VERIFY ON`, the SHA-256 checked, a stamp so a reconfigure does not download again), extracts it,
  and adds the decoder sources as a static library `pure_zstd_decoder` (or `portablekit_zstd`) with
  `ZSTD_DISABLE_ASM=1`, warnings from it silenced, linked into the host library that holds texture_pack.cpp. Both
  presets build it (arm64 and the rig's win-x64 with clang-cl).
- `patches/0033-zim-textures.patch`: host/gpu/texture_pack.cpp's `decode` dispatches on the first four bytes:
  `ZIMG` to a new `decode_zim(bytes, width, height, pixels, error)` in the same file (the header, the format, the
  flags, the three payload cases, level 0 of a mip chain, RGBA8 rows out, the same `kMaxImageSide` rule and
  `[texpack] cannot use NAME: REASON` messages: "not a ZIM format", "zstd: ...", "short payload"); anything else to
  stb_image as today. `[texpack] decoded` keeps its shape. The patch's CMake lines link the decoder library. Under
  100 lines of decoder, the rest is wiring.
- `tools/sprite_pack.sh --pack DIR`: already runs the routes with a pack; its PASS rules count PNG uploads by
  `.png` (lines 35 to 44, 277 to 300): accept `.zim` names too, and print the count of distinct images decoded and
  the replacements drawn per route; the "named files missing" rule becomes a count printed with the first three
  names, a FAIL only when every named file is missing (the HD pack names 2549 it lacks and still replaces). Rename
  nothing; the HD pack is checked with the same command.
- A measurement in Result: on the race route and the main-menu route, the `[texpack]` totals (keys, images decoded,
  replacements), the peak of the `images on the GPU (K MB)` budget line, the load time of the first race with the pack against without (the `[perf]` or frame lines the
  routes already produce).
- Rows: patches/README.md (row and section), docs/upstream.md (a candidate: the decoder is of use to every port),
  docs/vendor-map.md, packaging/THIRD_PARTY_NOTICES.md (zstd's notice, URL and SHA-256 like FFmpeg's and SDL's),
  the two read-mes if they list the libraries by name (check), docs/release.md "The texture pack" (ZIM accepted;
  the HD pack named with its address and "derived art, imported by the player"), docs/developing.md's table for
  `tools/sprite_pack.sh` (`--pack` reads ZIM packs too).

## Acceptance criteria
- [ ] `tools/build.sh profile` builds on the Mac with the decoder downloaded once; a second configure downloads
      nothing (the stamp).
- [ ] A unit of proof without a window: a 20-line C++ or Python stand-in is not wanted; instead
      `PURE_TRACE_TEXTURE_PACK=1` on the check's runs shows `[texpack] decoded` lines for `.zim` names and no
      `cannot use` line for a ZIM file (a `cannot use` for a missing file the ini names is reported, not fixed).
- [ ] `tools/sprite_pack.sh --pack ~/Downloads/WipEout-Pure-HD-Texture-Pack` PASSes: the pack opened with its
      4172 keys on each run, at least 10 distinct images decoded, replacements drawn on the race and the menus,
      race_hud's HUD found.
- [ ] The menus' backgrounds and the HUD are visibly the pack's in the check's captures (the worker looks at
      out/sprite_pack/check/on/*.png or the suite's captures and says what it saw; a 1920x1080 menu background
      replacing a 480x272 one is unmistakable).
- [ ] `tools/release_check.sh` PASSes the notices change; `tools/docs_check.py` PASS; `tools/patches.sh check` ok
      with 33 patches.
- [ ] No file of the pack, and no image derived from it, enters the repository, patches/ or docs/.

## Verify
`tools/build.sh profile && tools/patches.sh check && tools/docs_check.py && tools/sprite_pack.sh --pack ~/Downloads/WipEout-Pure-HD-Texture-Pack --out out/099/check`

The last command needs the screen (the Vulkan window, 1 to 4 minutes): the brief books it, Erik's screen is in
front and uncovered during the run (docs/approach.md rule 4). Run the headless parts first.

## May touch
- vendor/portablekit/host/gpu/texture_pack.cpp and the CMake file that builds it (exported as
  patches/0033-zim-textures.patch; never commit vendor/)
- cmake/Zstd.cmake (new), CMakeLists.txt (one include and one link line)
- tools/sprite_pack.sh
- patches/README.md, docs/upstream.md, docs/vendor-map.md, docs/developing.md, docs/release.md,
  packaging/THIRD_PARTY_NOTICES.md, packaging/macos/README.txt, packaging/windows/README.txt
- docs/tasks/099-zim-decoder.md (Result)

## Must not touch
- vendor/portablekit/include/psprecomp/, tools/regen.sh, the corpus; any other vendor file
- src/gpu/ (the Metal backend is task 100)
- docs/status.md, docs/decisions.md (the planning session's)
- config/, generated/, game/, disc/

## Estimated turns
40

## Escalate when
- The pack's keys do not match on the Vulkan renderer (no `[texpack] decoded` line after the decoder works, or
  lookups print keys the ini lacks): stop with the trace's first 40 lookup lines in Result; the key rule, not the
  decoder, is then the question.
- The download helper cannot live outside the framework's CMake without a change to the framework's target
  definitions beyond adding one link line: say which file and line, BLOCKED.
- zstd's sources do not build under clang-cl with `ZSTD_DISABLE_ASM=1` alone (the rig's preset is not run here;
  judge by the Mac build and the sources' `#if` guards, and list any doubt as an open question for the rig).
- The check needs a game-data file in the repository, or a capture of the pack's art in docs/: it must not.

## Result
Status: DONE

Changed:
- `cmake/Zstd.cmake` (new): downloads zstd 1.5.7 into `build/<preset>/_deps/downloads` the first time only. It writes a
  `.part` file, uses `TLS_VERIFY ON`, checks the SHA-256 `eb33e51f...6fa3`, then renames. It extracts only `LICENSE`,
  `COPYING` and `lib/` into `_deps/zstd`, behind a `pure.stamp` holding the version and SHA-256. It builds
  `lib/common/*.c` and `lib/decompress/*.c` as the static `pure_zstd_decoder`, with `ZSTD_DISABLE_ASM=1`,
  `XXH_NAMESPACE=ZSTD_` and warnings off (`-w`, or `/w` under MSVC/clang-cl). `zstd.h` is a PUBLIC SYSTEM include.
- `CMakeLists.txt`: `include(cmake/Zstd.cmake)` and `target_link_libraries(PureNative PRIVATE pure_zstd_decoder)`
  after `portablekit_add_game()`. No framework CMake was changed.
- `patches/0033-zim-textures.patch` (host/gpu/texture_pack.cpp only; it applies to the pin alone, tried with
  `git apply --check`):
  - `decode` now dispatches on the file's first four bytes: `ZIMG` goes to the new `decode_zim`, anything else to
    stb_image as before.
  - `decode_zim` covers the 16-byte header, formats 0, 1 and 2 to RGBA8 (anything else gives "not a ZIM format the
    loader reads (format N)"), and raw, zlib (`stbi_zlib_decode_malloc_guesssize_headerflag`) or zstd
    (`ZSTD_decompress`) payloads. With HAS_MIPS it keeps level 0 of the chain. It applies `kMaxImageSide`.
  - Its errors are "short header", "too large", "zstd: <name>", "zlib: ...", "short payload" and "payload longer
    than the image".
  - A ZIM's rows move into the replacement without the padding copy when no `[hashranges]` applies.
  - The `cannot use` and `decoded` lines are now each written as one string. In the probe's log, two loader threads
    had run these lines together. Their shape is unchanged.
- `tools/sprite_pack.sh` (`--pack`):
  - The "named files missing" rule is now a count of distinct named files, with the first three names. It is a FAIL
    only when every named file is missing.
  - The check prints per route the keys found, images decoded and uploaded (`.png` or `.zim`), draws replaced, the
    peak of the budget line, and the missing files.
  - It FAILs when a route draws no replacement, or when a `cannot use` line names a file the pack holds. A missing
    file is counted, not a rule.
  - The rule "reduced capture within the reference limit" stays a rule only for a pack of the game's own art (every
    entry is `<key> = <key>.png`, what the build writes). For new art it is printed and does not decide the result.
    Without this, the HD pack would FAIL here: race_hud's reduced capture is 0.1955 against a limit of 0.1.
  - The header documents all of this.
- `patches/README.md`: the row and the section. Also `docs/upstream.md` (a dependency row, a candidate section and
  its place in the order), `docs/vendor-map.md`, `docs/developing.md` (the sprite_pack row) and `docs/release.md`
  ("Other packs": ZIM accepted, the HD pack named with its address, derived art imported by the player).
- `packaging/THIRD_PARTY_NOTICES.md`: a Zstandard 1.5.7 section with the URL, the SHA-256 and the BSD licence text
  quoted in full, and the Windows paragraph names it. The two read-mes name "Zstandard's decoder" next to Dear ImGui.
- This task file. Commits ad8cd90, 19aaeee, efed827, af6352d, aaa184c and the Result commit.

Verify output (last 20 lines; the headless parts first, then the one window run; `tools/verify_task.sh` was not run
because it would open the window a second time):
- `tools/build.sh profile`: builds. The first configure printed `pure: downloading ...zstd-1.5.7.tar.gz`, and the
  archive's `shasum -a 256` matches the pin. `tools/build.sh configure` run again downloaded nothing (no
  "downloading" line; the stamp and archive times were unchanged). After deleting `_deps/zstd`, it re-extracted from
  the cached archive without downloading.
- `tools/patches.sh check`: `ok: 32 patch(es) reproduce vendor/portablekit at 8b0c3fe`. That is 32 files numbered up
  to 0033, because 0025 was removed in task 095.
- `tools/docs_check.py`: `docs_check: 39 files, 0 findings: PASS`.
- `tools/release_check.sh` (not part of Verify): `keys PASS` (the new SHA-256s are allowed) and every check except
  `home` passes. `home FAIL` comes from 6 findings that are already on batch/m2 and not from this task:
  patches/0029-windows-file-url.patch lines 10, 33 and 56, and patches/README.md lines 78, 612 and 613, all in 0029's
  `C:/Users/...` examples.
- `tools/sprite_pack.sh --pack ~/Downloads/WipEout-Pure-HD-Texture-Pack --out out/099/check` (Vulkan window, one
  run, 3 min 29 s):
```
  run main_menu: run_boot exit 0, frame 4730 reached: yes, 49 s, paced from flip 4400
  run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 54 s, paced from flip 5716
the Vulkan window, pack on (tools/frame_regress.sh --out .../out/099/check/check/on) ...
  run main_menu: run_boot exit 0, frame 4730 reached: yes, 48 s, paced from flip 4400
  run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 55 s, paced from flip 5716
the pack: 4170 keys (at least 40), hash xxh64, 3876 files named, 2546 of them missing (main_menu/menu/unlock_background.zim, main_menu/previews/ships/02_auricom/frame1.zim, main_menu/previews/ships/02_auricom/frame2.zim), new art: PASS
opened by the Vulkan renderer, route main_menu.txt: 4170 textures from .../out/099/check/check/data/textures/UCUS98612: PASS
opened by the Vulkan renderer, route main_menu.txt+single_race.txt: 4170 textures from .../out/099/check/check/data/textures/UCUS98612: PASS
  route main_menu.txt: 11 keys found in the pack, 11 images decoded, 11 uploaded, 49974 draws replaced, peak 11 images on the GPU (267 MB), 0 named files missing or unreadable
  route main_menu.txt+single_race.txt: 182 keys found in the pack, 127 images decoded, 127 uploaded, 209469 draws replaced, peak 124 images on the GPU (599 MB), 54 named files missing or unreadable
drawn: 127 distinct images of the pack uploaded for draws (at least 10), 127 decoded, 259443 draws replaced in the traced 60-frame windows (some on each route): PASS
refused: 0 lines for images the pack holds; 54 files the ini names missing or unreadable (counted, not a rule: in_game/adverts/00_others/01_vineta_k/fx300_text.zim, in_game/adverts/00_others/01_vineta_k/staten_park.zim, in_game/adverts/01_vineta_k/ag_systems_landscape.zim): PASS

each scene in the Vulkan window: the capture with the pack against the one without at tol 24 (at least 1%), both reduced to 480x272 by their blocks' centre pixels against the scene's reference at the scene's tol and limit (tools/frame_regress.sh), and the race HUD (tools/hud_check.py):
scene           size on vs off  off red.  on red.  limit  tol  HUD  result
main_menu    960x544    0.0275    0.0401   0.0485   0.05   24    -  PASS
race_hud     960x544    0.2350    0.0650   0.1955    0.1   32  yes  PASS

sprite pack check: 2/2 scenes pass, 4170 keys, 127 drawn (3m 29s)
sprite_pack: PASS
```
(".../" stands for this worktree's path.)

Measurement (logs: out/099/check/check/{on,off}/*.log; `PURE_TRACE_TEXTURE_PACK=1` on the "on" runs):
- Main-menu route (main_menu.txt): the pack opened with 4170 keys. 367 lookups found 11 keys in the pack. 11 images
  were decoded and uploaded: intro/sce copyright 2048x256 and presents 4096x512, main_menu_elements 2048x1024, the
  ocra_s12 font 4096x2048, the fx300_s12 font 4096x4096, and 6 more. 49974 draws were replaced in the traced
  windows. Budget peak: `frame 4680: 1320 draws replaced in 60 frames, 11 images on the GPU (267 MB)`. No `cannot
  use` line.
- Race route (main_menu.txt+single_race.txt, Vineta K): the pack opened with 4170 keys. 623 lookups found 182 keys.
  127 distinct images were decoded and uploaded, 102 of them `in_game/`, uploaded between frames 5708 and 6011 as
  draws first sampled them. 209469 draws were replaced. Budget peak: `frame 6000: 28564 draws replaced in 60 frames,
  124 images on the GPU (599 MB)`, under the 1024 MB default. 54 `cannot use NAME: missing or unreadable` lines, all
  for files the ini names that the reupload lacks. No `cannot use` line for a ZIM the pack holds (the probe had 126
  `unknown image type`).
- Load time of the first race, with the pack against without: the route has no `[load]` line in the race's load and
  no `[perf]` line, because the check sets no `PURE_PERF`. The figure available is the run's wall time to the race
  HUD (unpaced to flip 5716, paced after it): 54 s without the pack, 55 s with it, and `run_boot exit 0 after 54.6s`
  for both. Main menu: 49 s without, 48 s with. Decoding runs on the loader threads, and no stall shows at this
  resolution.
- Decoder throughput (a throwaway program in the session's scratch directory, not committed, linking the built
  `libpure_zstd_decoder.a`): all 1331 ZIMs of the pack decode at width x height x 4. That is 1422.3 Mpx in 1405 ms
  of `ZSTD_decompress` on one thread of this Mac.
- Captures (looked at: out/099/check/check/{on,off}/shots/*.png):
  - main_menu with the pack: the menu font (SINGLE PLAYER, MULTIPLAYER, ...), the header bars, the WIPEOUT katakana,
    the logo and the footer (W:P, V5.0, //2197) are clearly the pack's: crisp edges where the originals are soft,
    and the header's small text can be read. The background is white with and without the pack, and none of the 155
    1920x1080 images was looked up on either route. So the brief's "1920x1080 menu background" was not seen in these
    scenes; the main menu draws no textured background for the pack to replace.
  - race_hud with the pack: the track surface (sharper grid squares with red and white markings), the chevrons on
    the right-hand barrier, the crowd, the sky and the KM/H gauge's label are the pack's. The HUD was found by
    hud_check, and its digits look much the same.
  - One opponent ship on the left is red with the pack and blue without. I did not find out whether this is the
    pack's livery or a different grid.
- Clean-up: the check copies the pack into out/099/check/check/data/textures (868 MB, git-ignored). I deleted that
  copy after the run. No file of the pack, and no image made from it, is in a commit; the captures stay in out/.

Open questions:
- D-024 asks for a row in the framework's SOURCE_PROVENANCE table. That file is under vendor/ and listed as Must not
  touch, so it was not written. docs/upstream.md's 0033 section says an upstream request would carry the row, the
  download in the framework's CMake and the link into `portablekit_host_check`. That target also compiles
  texture_pack.cpp, but only with `PSPRECOMP_BUILD_TESTS`, which is off here.
- The bundles ship no `zstd-LICENSE.txt`, so the BSD text is quoted in THIRD_PARTY_NOTICES.md, which both bundles
  ship. tools/bundle.sh could pass `--license zstd=<build>/_deps/zstd/zstd-1.5.7/LICENSE` to the packer, and
  tools/bundle_windows.sh could copy it the same way. Both scripts are outside May touch.
- The rig (win-x64, clang-cl) has not been built. From the guards in the sources: `ZSTD_ASM_SUPPORTED` needs
  `__GNUC__`, which clang-cl does not define, and `ZSTD_DISABLE_ASM=1` turns the BMI2 assembly off anyway, so
  `huf_decompress_amd64.S` is never referenced. The doubt is DYNAMIC_BMI2's `__attribute__((target))` paths under
  clang-cl. zstd's CI builds with ClangCL, so I expect them to build. The rig's first configure also downloads the
  archive from GitHub.
- The check's reference rule now applies only to own-art packs (see Changed). The brief's acceptance list leaves that
  rule out for `--pack` with the HD pack, but the planning session should confirm the change.
- Counts that differ from the brief: the brief says 4172 keys, while the ini's [hashes], case-folded, hold 4170
  distinct keys, which is what the loader and the check count. The brief says 2549 missing named files; the check
  counts 2546 distinct missing files out of 3876 named. The brief says 33 patches; `patches.sh check` reports 32,
  because 0025 is gone.
- Window checks this change still needs: the same `tools/sprite_pack.sh --pack DIR` on the rig with the pack copied
  there (Vulkan on Windows). A menu route deeper into Single Race (track or ship select) would show the 1920x1080
  backgrounds. The Metal loader is task 100.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

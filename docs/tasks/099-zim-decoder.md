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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

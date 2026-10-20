# 101: The crowd survey: the crowd's textures, draws and stands extracted from a race frame

Milestone: Crowd (status, Next: 3D crowd and people models) | Branch: task/101-crowd-survey | Status: OPEN

## Goal
Erik wants to start on 3D crowds and needs the material in his hands first: the original crowd texture of the first
course (Vineta K) beside the HD pack's version, the geometry the crowd is drawn on (the stands, the crowd quads
themselves, with their scale and placement in the world), and the person figure that appears in Time Trial. This task
builds the extraction tool the whole substitution arc will reuse (a recorded frame's draws as an OBJ scene with its
textures), uses it on the race recording and on a new Time Trial recording, and writes down what the crowd is: how
many draws, what primitives, billboards or static quads, where they sit and how big they are. The outputs are
derived from the game's data and stay under out/ (never committed); the facts go in Result and docs/research.md.

## Read first
- docs/status.md, Next: the "3D crowd and people models" and "3D backgrounds" entries (what the survey serves).
- src/tools/ge_record_format.hpp, the header comment (lines 1 to 66: the record kinds; a Draw holds a DrawCall with
  decoded vertices in object space, the four 4x4 matrices, the texture state; Memory records hold the texels).
- src/tools/ge_replay.cpp: the options (650 to 690), the lanes (430 to 466) and `apply`'s `Kind::Draw` (488 to 494:
  the hook, a `RecordedDraw` with `draw.call` and the lane's `GuestMemory`).
- vendor/portablekit/host/gpu/ge_state.hpp: `Vertex` (41 to 46), `DrawCall` (230 to 270: `primitive`, `vertices`,
  `indices`, `through`, `texture`, `world`, `view`, `projection`), `TextureState` (the address, format, size).
- vendor/portablekit/host/gpu/texture_pack.hpp: `compute_texture_pack_key` (112), `format_texture_pack_key`,
  `TexturePackOptions`, `TextureDumper` (209 to 230: `dump(memory, texture, max_seen_v, options, pixels)` writes
  `<key>.png` once per key); vulkan_renderer.cpp 4349 to 4356 (how the renderer calls it, `kDumpOptions`).
- vendor/portablekit/host/gpu/texture_decode.hpp (`decode_texture(memory, state, pixels)`, patch
  0012-texture-decode-exports: a texture's level 0 as RGBA8 words).
- docs/ge-effects.md, the frame structure (the opaque world, the sky cube, the signal, the translucent draws).
- tools/gerec/replay_check.sh 80 to 90 (how a recording is made: `PURE_GE_BACKEND=record`, `PURE_GE_RECORD`,
  `PURE_GE_RECORD_AT`, `PURE_GE_RECORD_FRAMES`, `PURE_GE_RECORD_INNER=vulkan`) and docs/developing.md's row for them.
- tools/frame_regress.sh 60 to 80 (the scene table: `race_hud` on main_menu.txt+single_race.txt at flip 6046,
  `tt_hud` on main_menu.txt+time_trial.txt at 5890; the routes in config/pad_scripts/).

## Facts
- Recordings: out/gerec/race.gerec (24 MB) and race_warm.gerec (65 MB) are the single-race route on Vineta K
  (re-recorded 2026-10-19; `tools/gerec/gerec_dump.py FILE --summary` lists the frames and draw counts). No Time
  Trial recording exists: make one on config/pad_scripts/main_menu.txt+time_trial.txt around flip 5890 (the
  `tt_hud` scene), 3 frames, in the Vulkan window (`PURE_GE_RECORD_INNER=vulkan`), out/101/time_trial.gerec.
- The HD pack (~/Downloads/WipEout-Pure-HD-Texture-Pack) holds one crowd image, `in_game/tracks/00_shared/crowd.zim`,
  under nine keys in its textures.ini (lines 2739, 2932, 3224, 3342, 3506, 3696, 4630, 4738, 4814: nine originals
  across the tracks or editions share it). The keys are the framework's: `format_texture_pack_key` of
  `compute_texture_pack_key` with the pack's options (xxh64, ignoreAddress, ignoreMipmap), the same the texture
  dumper names its PNGs with. Which of the nine Vineta K uses is for the tool to say.
- A ZIM image is `ZIMG`, width, height, flags (little-endian u32), then a zstd frame of width x height x 4 RGBA8
  bytes (all of this pack; D-024). `/opt/homebrew/bin/zstd -d` decodes a frame from stdin; Python 3.13 here has
  no zstd module. A PNG writer needs only `zlib` and `struct`.
- `DrawCall.vertices` are decoded floats in object space (`through` false) or screen space (`through` true); the
  world matrix takes object space to world space, the view to eye space. The matrices are 4x4 column-major as the
  GE holds them (the Vulkan renderer's `vertex.position * world` order: read `ge.vert` or vulkan_renderer.cpp to
  be sure of the convention before writing it down; say which in Result).
- ge_replay runs inside PureNative (`PureNative --replay FILE.gerec ...`, docs/developing.md 18); its lanes are
  backends (null, vulkan, metal); a null lane keeps a `GuestMemory` the Memory records fill, so a tool mode needs
  no renderer: the GuestMemory is there to decode textures and compute keys from.
- Game data never enters the repository: the OBJ, PNG and JSON this task writes are derived from the disc and
  live under out/101/ only; no capture or image of them goes into docs/ or a commit. The task file's Result
  names paths and numbers.

## Deliverable
- `PureNative --replay FILE.gerec --extract FRAME --out DIR [--keys K1,K2,...]` (src/tools/ge_replay.cpp; a new
  src/tools/ge_extract.cpp if it grows past 200 lines): on a null lane, for frame FRAME (the recording's own
  numbering as `--frames` takes it), writes
  - `DIR/frame.obj` and `DIR/frame.mtl`: one `o draw_NNNN_<key>` object per non-through draw, vertices in world
    space (the world matrix applied, the view left out so the scene stands still in the track's frame), `vt` with
    v flipped for OBJ, faces from the primitive (triangles, strips, fans, and sprites as two triangles from the
    GE's sprite rule: two vertices per sprite, the quad spanned in screen space after transform, which the Vulkan
    renderer expands somewhere near its draw path: find it and do the same in object space, noting that a sprite's
    orientation is screen-aligned); `usemtl <key>` per draw; the MTL maps each key to `textures/<key>.png`.
    Lines and points are skipped and counted.
  - `DIR/textures/<key>.png`: every texture the frame's draws bind, through `TextureDumper` with the pack's options
    (xxh64, ignoreAddress, ignoreMipmap) so the names are the HD pack's keys.
  - `DIR/frame.json`: the frame number, the view and projection matrices of the first non-through draw (and a list
    of distinct view matrices with the draw ranges they cover), and per draw: index, key, primitive, vertex and
    index counts, through, texture format and size, world-space bounds (min and max), the blend and alpha-test
    state in short, and a `billboard` guess (true when the draw's world matrix differs from the frame's others and
    its rotation part matches the inverse view rotation, which is what a screen-facing quad looks like).
  - `--keys` writes only the draws whose key is listed (`frame.obj` holds just those; the JSON and textures are
    still the whole frame's).
- `tools/zim_to_png.py FILE.zim OUT.png`: the header read, the payload through the `zstd` executable on PATH (or
  `zlib` for flag 256, raw otherwise), the PNG written with stdlib; exit 2 with a message when `zstd` is missing.
- The extraction, under out/101/ (the worker runs it):
  - `out/101/race/`: `--extract` of the `race_hud` frame of out/gerec/race.gerec (the frame nearest flip 6046,
    or the recording's middle frame if its numbering differs: say which), the whole scene.
  - `out/101/crowd/`: the same frame with `--keys` of the crowd key(s) Vineta K uses (found by matching the
    frame's texture keys against the ini's nine).
  - `out/101/crowd_original.png` (a copy of the crowd key's PNG from the dump) and `out/101/crowd_hd.png`
    (`tools/zim_to_png.py` on the pack's crowd.zim).
  - `out/101/time_trial.gerec` recorded as above, then `out/101/time_trial/` (`--extract` of its middle frame)
    and, once the person figure's textures are found (look at the dump's PNGs: a human figure, a pilot, a marshal,
    whatever stands by the track in Time Trial; if nothing human appears in that frame, say so and record 3 frames
    later in the route, up to twice), `out/101/person/` with `--keys` of those and `out/101/person_*.png`.
- The survey, in Result and as a dated entry in docs/research.md ("The crowd, surveyed (task 101)"): for Vineta K's
  race frame, the crowd's draw count, primitive, vertices per draw, whether the quads face the camera (the
  billboard guess and the world matrices) or stand fixed on the stands, their world-space extent against the
  track's width (the track's draws' bounds), the texture's size and format and how many crowd figures one texture
  holds (look at the PNG), which stands draws sit next to the crowd draws in draw order and what textures they
  bind, the HD crowd image's size, and what the Time Trial figure is (its draws, textures, vertex count, whether it
  is a model or a sprite). Also the GE features the crowd draws use (the alpha test for cut-outs, blending, the
  texture function, lighting, fog, the depth test and write) as the hook will have to reproduce or replace them.
- docs/developing.md: a row for the `--extract` mode and one for `tools/zim_to_png.py`; docs/ge-backend.md's
  ge_replay section mentions `--extract`.

## Acceptance criteria
- [ ] `PureNative --replay out/gerec/race.gerec --extract <frame> --out out/101/race` exits 0, the OBJ loads (a
      Python read of its face indices against its vertex count: every index in range; `tools/obj_check.py` if you
      write one, else the check inline in Result), the MTL names only PNGs that exist, and the JSON lists every
      draw of the frame.
- [ ] out/101/crowd/frame.obj holds only crowd draws and their count equals the JSON's count of draws with the
      crowd key.
- [ ] crowd_original.png and crowd_hd.png exist and are looked at: Result says their sizes and what they show.
- [ ] The Time Trial recording exists and its person figure is found, extracted and described, or Result says
      what was looked at and that no human figure appears in the recorded frames.
- [ ] `tools/build.sh profile` builds; `tools/gerec/replay_check.sh` is not rerun (nothing in the replay path
      changes for the existing modes: say so), `tools/docs_check.py` PASS.
- [ ] Nothing derived from the game is in a commit: `git status` shows no file under out/, and no image is added
      under docs/.

## Verify
`tools/build.sh profile && tools/docs_check.py && build/arm64/bin/PureNative --replay out/gerec/race.gerec --extract $(python3 tools/gerec/gerec_dump.py out/gerec/race.gerec --summary | python3 -c "import sys,re; f=[int(m) for m in re.findall(r'(?m)^\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+', sys.stdin.read())]; print(f[len(f)//2] if f else 1)") --out out/101/verify && python3 -c "import re,sys; t=open('out/101/verify/frame.obj').read(); nv=len(re.findall(r'^v ',t,re.M)); bad=[i for i in map(int,re.findall(r'(?m)^f\s+(\d+)',t)) if i<1 or i>nv]; print('obj ok' if nv and not bad else 'obj bad'); sys.exit(0 if nv and not bad else 1)"`

(If `--summary`'s frame lines read differently, adapt the frame pick in the Verify line and say so in Result.) (Adapted by the worker, task 101: gerec_dump.py is not executable, so it runs through `python3`, and the summary's
frame rows read `   6014    906    906 ...`, with no `frame N`, so the pick takes the table's first column.) The
Time Trial recording needs the Vulkan window for one short run (about a minute): Erik's screen is booked for it.

## May touch
- src/tools/ge_replay.cpp, ge_replay.hpp, a new src/tools/ge_extract.cpp (and its CMakeLists.txt line)
- tools/zim_to_png.py (new), tools/obj_check.py (new, optional)
- docs/developing.md, docs/ge-backend.md, docs/research.md
- docs/tasks/101-crowd-survey.md (Result)

## Must not touch
- vendor/ (no patch in this task: the dumper, the key and the decoder are used as exported), include/psprecomp/,
  tools/regen.sh, the corpus
- src/gpu/ (no backend change: this is a survey), config/, docs/status.md, docs/decisions.md
- out/gerec/*.gerec (read only; the new recording goes under out/101/)

## Estimated turns
40

## Escalate when
- `compute_texture_pack_key` or `TextureDumper` cannot be called from the replay tool without a vendor change:
  say which symbol and why, BLOCKED (a patch is the planning session's call).
- The recording's draws do not carry what the OBJ needs (vertices empty for raw-vertex draws, matrices zero):
  report which draws and how many, write what can be written, PARTIAL.
- The Time Trial route does not reach a race in the window run (the scene table's flip 5890 is the HUD): report
  the run's last flip and the log's tail, and extract the race frame only.

## Result
Status: DONE. The Verify line passes after I fixed its frame pick (see "Verify"). The one window run the brief allowed
went to the Time Trial recording. The person figure in that frame is the start line's pit marshal, `pitguy.zim`. It
was found, extracted and described below. If that is not the figure Erik means, the recipe below records his.

Changed:
- `src/tools/ge_extract.cpp` (new, 502 lines) and `src/tools/ge_extract.hpp` (new; the header the new .cpp
  needs, not named in "May touch"): `pure::extract::FrameExtract`, which gets each Draw of the frame along with the
  lane's guest memory and writes `frame.obj`, `frame.mtl`, `textures/<key>.png` and `frame.json`.
  - Keys come from `compute_texture_pack_key` with {Xxh64, ignore_address, ignore_mipmap}. `max_seen_v` follows the
    renderer's rule for a texture it has not seen before. Texels come from `decode_texture`, and the PNGs are
    written by `TextureDumper`. Every function was called as exported, with no vendor change.
  - The dumper drops images once more than 256 are waiting, so it is recreated after every 128 textures, and its
    destructor drains the queue.
  - Vertices go to world space as `world * (x, y, z, 1)`. Strips, fans and triangles are turned into faces as the
    renderer does it, and faces whose indices repeat are skipped. Sprites are expanded the way the renderer's
    Sprites case does it, in object space.
  - `frame.json` holds:
    - the view and projection of the first transformed draw;
    - `main_view`, `main_view_matrix` and `main_projection`: the camera, meaning the view most draws use (in the race
      frame the first transformed draw belongs to a billboard render-to-texture round, not to the camera);
    - every distinct view with its draw ranges and count, and `usual_world`;
    - `textures`: each key's format, size, address, whether its PNG exists, and the draws that use it;
    - per draw: index (from 1, as `--cut` counts), record, key, primitive, counts, through, clear, raw, target,
      vertex type and address, texture state, world-space or screen-space bounds, blend, alpha test, depth, stencil,
      lighting, fog, cull, vertex colours, orthographic, view, the world matrix, `facing_error`, `facing_view` and
      `billboard`.
- `src/tools/ge_replay.cpp`:
  - New options: `--extract FRAME` and `--keys` (with usage text).
  - Parse checks: `--extract` needs `--out`, and is refused together with `--backend` other than null, `--compare`,
    `--cut`, `--a`/`--b` or `--first-diff`. `--keys` needs `--extract`.
  - `Replay::extract()` replays every earlier frame into a null `Lane`. It then applies the frame's records one by one
    and hands each Draw to the extractor. A frame missing from the recording exits 2.
  - `run()` branches to `extract()` before any lane is made, so the existing modes run the same code as before.
- `CMakeLists.txt`: `src/tools/ge_extract.cpp` added to PureNative's sources (one line).
- `tools/zim_to_png.py` (new): reads the header, decodes zstd (flag 4096) through the `zstd` executable, zlib (256) or
  raw, converts formats 0, 1 and 2 to RGBA8, and writes the PNG with tools/png.py. Exits 2 when zstd is not on PATH and
  1 for a file it cannot read.
- `docs/developing.md`: a `src/tools/ge_extract.cpp` row (the `--extract` mode) and a `tools/zim_to_png.py` row.
- `docs/ge-backend.md`, section 7: the `--extract` usage line, two option rows, and a paragraph on what the mode writes
  and its conventions.
- `docs/research.md`: the dated entry "The crowd, surveyed (task 101, 2026-10-20)".
- `docs/tasks/101-crowd-survey.md`: the Verify line's frame pick (see below) and this Result.
- Commits: d507947 (`--extract`), e71fe56 (zim_to_png.py), 4ffbce4 (the camera's view in frame.json), fa4e61c (the
  docs), and the Result commit.
- Nothing under out/ is committed, and no image is added under docs/. The worktree's `out/gerec` is a symlink I made
  to the main checkout's `out/gerec`, so the Verify line finds the recordings (worktree_init does not link out/).

Verify:
- I changed the Verify line before running it, as the brief allows:
  - `tools/gerec/gerec_dump.py` is not executable. Called directly it fails with "permission denied", the pick then
    prints 1, and `--extract 1` exits 2 because the recording holds frames 6014 to 6016 only. It now runs through
    `python3`.
  - The `--summary` frame rows read `   6014    906    906 ...` with no `frame N` in them, so the old regex matched
    nothing. The pick now takes the table's first column. The middle frame is 6015.
- `tools/gerec/replay_check.sh` was not rerun. Nothing in the replay path changes for the existing modes:
  `run()` branches to `extract()` only when `--extract` is given, and the parser only gained options.
- `tools/docs_check.py`: PASS (39 files, 0 findings).

Verify output (all of it; under 20 lines):
```
verify 101: tools/build.sh profile && tools/docs_check.py && build/arm64/bin/PureNative --replay out/gerec/race.gerec --extract $(python3 tools/gerec/gerec_dump.py out/gerec/race.gerec --summary | python3 -c "import sys,re; f=[int(m) for m in re.findall(r'(?m)^\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+', sys.stdin.read())]; print(f[len(f)//2] if f else 1)") --out out/101/verify && python3 -c "import re,sys; t=open('out/101/verify/frame.obj').read(); nv=len(re.findall(r'^v ',t,re.M)); bad=[i for i in map(int,re.findall(r'(?m)^f\s+(\d+)',t)) if i<1 or i>nv]; print('obj ok' if nv and not bad else 'obj bad'); sys.exit(0 if nv and not bad else 1)"
[0/2] Re-checking globbed directories...
[1/4] Checking the build version
[2/4] Building CXX object CMakeFiles/PureNative.dir/vendor/portablekit/host/ui/menu.cpp.o
[3/4] Linking CXX executable bin/PureNative
docs_check: 39 files, 0 findings: PASS
[render] GE backend null: draws nothing, presents black
[replay] extracted frame 6015 to out/101/verify: 905 draws (11 through, 0 undecoded, 0 lines and 0 points skipped), 894 objects and 61692 faces in frame.obj, 140 textures, 140 PNGs
[render] null backend: 2 frames, 1811 draws submitted, 0 block transfers, 0 uploads in 0.191054 s
obj ok
verify 101: PASS
```

Acceptance checks (a Python reading of each OBJ, MTL and JSON; every face corner checked, not only the first index):
- **out/101/race**, frame 6016:
  - Why this frame: it is the `race_hud` scene. The table in tools/frame_regress.sh puts `race_hud` at 6016; the
    brief says 6046. 6016 is also the recording frame nearest 6046. The recording holds 6014 to 6016.
  - Exit 0. 65756 `v` and 65756 `vt`, 185082 face references, 0 out of range, 895 objects.
  - The MTL maps 138 PNGs and every one exists. The JSON lists 906 draws, the same as `draws_total` and as the
    frame's draw count in gerec_dump.py.
  - No draw has raw (undecoded) vertices, and no lines or points were skipped.
- **out/101/crowd**: `--keys 00000000062cb021471694d4,00000000b8da6d727d4e9d6b` (the crowd and its background).
  6 objects, the same as the JSON's 4 draws with the crowd key plus its 2 with the background key. 1247 vertices,
  0 indices out of range, 2 maps that both exist.
- **out/101/time_trial**, frame 5890: 592 objects, 0 bad indices, 123 maps that all exist, 603 draws in the JSON.
- **out/101/person**: 6 objects (draws 149 to 154, the JSON's 6 draws with the pit marshal's key), 0 bad indices.
- `git status` shows only this task file before the last commit; nothing under out/ is tracked.

The survey (docs/research.md has the same with more detail):
- **Coordinates.**
  - Matrices are 4x4 column-major: element (row, column) is at `[column * 4 + row]` and is applied as M * v, with the
    translation in elements 12 to 14. This is how ge_state.cpp's `store_3x4` writes them, and what ge.vert's
    `push.transform * vec4(pos, 1)` and the renderer's `multiply` read.
  - The camera is view 1 of the 6 views in the race frame, used by 759 of the 895 transformed draws.
  - All scenery shares one world matrix, a uniform scale of 2293.69 with no rotation or translation (s16 positions,
    vertex type 0x13F). The OBJ is therefore in the track's frame.
  - y is up: the sky cube's top face is at y 90.
  - The start straight runs along x. Its road spans z -127.1 to -85.9, so it is **41 units wide**. The Feisar is
    10.5 units long.
- **The crowd's texture**, Vineta K:
  - Key `00000000062cb021471694d4`, textures.ini line 2739.
  - CLUT4 **64x64**, 4 mip levels, at 0x041BB440. Alpha is only 0 or 255; 1650 of the 4096 texels are transparent.
  - Four rows of 16 texels each. Every row is a line of full-length standing people seen from the front, in casual
    clothes; the HD version shows they are photographs.
  - **About 56 figures**: about 17, 15, 11 and 13 per row, each about 4 texels wide.
  - Stored upside down, with the heads towards v = 1. On the quads, the higher corners take the larger v, so the
    people stand upright.
  - The HD `crowd.zim` is **256x256** RGBA8888 (zstd, flags 5120): the same figures in the same layout, at 4x.
- **The crowd's draws.**
  - **4 per frame.** Race frame: 471, 472, 615 and 616. Time Trial: 340, 341, 466 and 467.
  - Triangle strips without indices, of **368, 147, 381 and 113 vertices**. That is 1001 strip triangles, 411 of
    them non-degenerate: about 205 quads joined by degenerate triangles.
  - Each quad samples one row of figures: a v span of 0.25, and a u span of 0.5 or 1 that runs past 1 with the
    wrap.
  - Quads are **2.24 to 2.52 units tall** and 5.3 to 12.9 wide (median about 6.6), so a figure is about 0.85 units
    wide.
- **Billboards or fixed: fixed.**
  - The crowd draws use the scenery's world matrix, and their billboard guess is false.
  - None of their triangles faces the camera within 5 degrees (`facing_view` 0).
  - Their world-space positions are the same in frame 6008 (race_warm.gerec) and frame 6016, while the draw order
    changes between the two.
  - The quads stand vertical and face the track, turned by up to about 30 degrees to follow the stands' curve.
  - Nothing in the camera's view is a billboard by its matrix. The guess is true for 119 draws, all in the
    identity-rotation views of the render-to-texture rounds and the HUD.
- **Placement**: two grandstands facing each other across the start straight.
  - Stand A (471, 472): x 32.3 to 178.1, y 38.2 to 47.1, z -164.2 to -133.3, 6.2 units beyond the road's edge.
  - Stand B (615, 616): x 33.7 to 178.7, y 38.4 to 46.9, z -81.2 to -54.3, 4.7 units beyond the edge.
  - Each stand is **146 units long (3.6 road widths)**. Its rows rise 9 units, starting 5 units above the road.
- **The stands' draws beside the crowd, in draw order.**
  - Stand A (468 to 490):
    - a 4x4 CLUT4 texture that is not in the pack, `000000002c9b9d934249a820`: 469-470 with alpha test GREATER
      0x10, and again at 475-476 with ALWAYS;
    - `effect_04` (473-474) and `texture_e2` (477);
    - **478 `crowd_background`**, key `00000000b8da6d727d4e9d6b`, CLUT4 64x64: a speckled far-away crowd on the
      stand's sloped tiers;
    - `grandstand_exterior` (479-480), `texture_e1`, `texture_r`, `grandstand_small` (484) and `grandstand_big_arch`
      (487-490).
  - Stand B (612 to 625): the same 4x4 texture, `grid_1` (614), the crowd, the 4x4 texture again,
    `grandstand_exterior` (620), `marble_wall/wall_4` and `grandstand_small` (622-625). Its `crowd_background` is
    drawn much earlier, at 276.
  - textures.ini maps the background's key to `in_game/tracks/01_vineta_k/environment/crowd_background.zim`. That
    file is not in the pack, so the background is drawn with the original texture.
- **GE features of the crowd draws** (what a hook has to reproduce or replace):
  - alpha test **GREATER 0x7F** (the cut-out) and **no blending**;
  - texture function **modulate** with the texture's alpha, mipmapped (min filter 7, mag filter 1), UVs from map mode
    0;
  - **fog on**, lighting off;
  - a vertex colour: white on stand A, 0xFFB7B0A8 (a shade) on stand B;
  - **depth test GREATER with depth writes**, culling counter-clockwise;
  - stencil ALWAYS with reference 0x04 (the bloom mask), alpha writes on;
  - drawn in the opaque part of the frame.
- **Camera flashes**, draw 864:
  - Binds `camera_flash.zim` (CLUT4 64x64).
  - One quad in stand A at (119.6, 43.8, -139.9).
  - Additive blending, add(SA, FIX 0xFFFFFF), with depth test and no depth writes, drawn in the translucent part.
- **The person figure**, Time Trial frame 5890 (the same draws are 169 to 174 in the race frame):
  - `pitguy.zim`, key `00000000d5085be1dbd7e4c3` (textures.ini line 2752, one of the file's six keys). CLUT4
    **32x64**, 3 mip levels.
  - The image: one figure in a dark armoured suit and a helmet with a yellow visor, standing, seen from the front,
    stored upside down like the crowd.
  - **Six draws, one quad (4 vertices) each**: a flat cut-out, neither a model nor a sprite primitive.
  - **2.03 units tall**, about 1 wide.
  - They stand **on top of the start line's structure**, feet at y 39.41 (the `startline_rail` tops), 6.4 units
    above the road. Three are beside each edge of the start straight (z -84.6 to -86.0 and -127.3 to -130.3).
  - Their orientation is fixed, facing +x (the direction the race comes from) within about 37 degrees. They are not
    billboards.
  - Same GE state as the crowd. In the recorded picture they are the small figures on the booth at the left of the
    straight.
  - The HD `pitguy.zim` is 128x256.
  - No other human figure is in that frame: the pack names all but 23 of its 126 textures, and I looked at those
    23. They are solid colours, palettes, render targets, fonts and the HUD.

Window checks: one Vulkan window run, the Time Trial recording (197 s, Erik's screen booked):
`tools/run_boot.py --script out/101/time_trial.route.txt --frames 5902 --shell vulkan` with
`PURE_GE_BACKEND=record PURE_GE_RECORD_INNER=vulkan PURE_GE_RECORD_AT=5889 PURE_GE_RECORD_FRAMES=3`, on a fresh stick
(`port.fresh_stick`), using main_menu.txt+time_trial.txt with the `shot` steps dropped, as replay_check.sh records.
The run saved frames 5889 to 5891 with 603 draws each. The change needs no other window check.

Paths for Erik to open (git-ignored, in this worktree; copy out/101 to the main checkout before the worktree goes):
- Crowd textures:
  - `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/crowd_original.png` (64x64)
  - `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/crowd_hd.png` (256x256)
  - `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/crowd_background_original.png`
    (64x64; there is no HD version of it)
- The crowd geometry, its 6 draws on the two stands:
  `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/crowd/frame.obj`
- The whole race scene, for the stands around the crowd:
  `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/race/frame.obj` (with
  `frame.mtl`, `textures/` and `frame.json`)
- The person:
  - geometry, the 6 pit marshal quads:
    `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/person/frame.obj`
  - `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/person_pitguy.png` (32x64)
  - `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/person_pitguy_hd.png` (128x256)
- The Time Trial frame:
  - scene: `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/time_trial/frame.obj`
  - recorded picture:
    `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/time_trial_images/frame_5890.png`
  - recording: `/Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a31ad5f3c82a69ecf/out/101/time_trial.gerec`
    (21.6 MB)

A played session to reach another figure, if the pit marshal is not the one Erik means (from the repository root,
in the Vulkan window):
1. Play and dump. Every texture the game uploads lands in `played_dump/<key>.png`, a shot is taken every 15 frames,
   and the pad and the frames are logged:
   ```
   python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; port.fresh_stick("out/101/played.game")'
   python3 tools/run_boot.py --window --shell vulkan --backend vulkan --seconds 1200 --max-lines 400000 \
     --shots out/101/played_shots --every 15 \
     --env PURE_GAME_DIR=$PWD/out/101/played.game --env PURE_TEXTURE_DUMP=$PWD/out/101/played_dump \
     --env PURE_TRACE_PAD=1 --env PURE_FRAME_LOG=1 --env PURE_PERF=log out/101/played.log
   ```
   - `--backend vulkan` is needed because the texture dumper is the Vulkan renderer's. The Metal backend, which is the
     default on macOS, has none.
   - Press F8 when the figure is on screen. With `PURE_PERF` set, F8 prints `[mark] N`.
2. Read the frame number. The Performance overlay (F3) and the `[perf]` line do not show one: the line carries fps,
   game rate, speed, frame times, guest, render and wait times, lists, draws, present mode, size, refresh and GPU
   time. Two ways to get it instead:
   - The `[pure] frame N` line just before the `[mark]` line in out/101/played.log.
   - The name of a shot showing the figure, `out/101/played_shots/frame_N.png`. These names use the backend's
     presented-frame count, the same counter `PURE_GE_RECORD_AT` uses.
   In tool runs the two counters agree: race_hud's flip 6016 is race.gerec's last frame.
3. Turn the pad log into a script: `python3 tools/pad_record.py out/101/played.log out/101/played_route.txt --to N`.
4. Replay it and record around the figure, on a fresh stick again so that a saved time cannot add a ghost question:
   ```
   python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; port.fresh_stick("out/101/figure.game")'
   python3 tools/run_boot.py --script out/101/played_route.txt --frames <N+15> --shell vulkan \
     --env PURE_GAME_DIR=$PWD/out/101/figure.game --env PURE_GE_BACKEND=record --env PURE_GE_RECORD_INNER=vulkan \
     --env PURE_GE_RECORD=$PWD/out/101/figure.gerec --env PURE_GE_RECORD_AT=<N-4> --env PURE_GE_RECORD_FRAMES=9 \
     out/101/figure.record.log
   python3 tools/gerec/gerec_dump.py out/101/figure.gerec --summary --images out/101/figure_images
   build/arm64/bin/PureNative --replay out/101/figure.gerec --extract <the frame showing it> --out out/101/figure
   build/arm64/bin/PureNative --replay out/101/figure.gerec --extract <that frame> --out out/101/person2 --keys <its key>
   ```
   - Nine frames rather than three, in case the replayed route drifts a few frames from the played one. Time Trial has
     no AI ships, but the pad is replayed per flip.
   - To find the figure's key, match its PNG from step 1's dump against `textures` in the new frame.json.

Open questions:
- Is the pit marshal the figure Erik means? He described a person standing on a structure beside the track, seen
  while driving. The marshals stand on the start line's booths at the left of the straight in the recorded tt_hud
  picture. A figure further along the track would need the played session above.
- A "record now" key would take two pieces:
  - A vendor patch giving the UI layer one more key event, the way F8's `[mark]` works (patch 0032-trace-marks,
    host/ui/layer.cpp).
  - About 30 lines in `src/tools/record_backend.cpp`, so that `PURE_GE_RECORD_AT=key` passes calls through until that
    event and then records the next M frames. It already writes the whole of VRAM when a recording begins, so it can
    start mid-run.
- textures.ini names `in_game/tracks/01_vineta_k/environment/crowd_background.zim` for the crowd background's key, but
  the pack folder has no such file. Its HD version is missing, so with the pack installed the background should draw as the
  original (not checked in a window).
- Sprites are expanded in object space, as the Vulkan renderer does it, which is not screen-aligned when the draw's
  rotation is not the camera's. No transformed sprite in the race frame lies in the camera's view: the 28 there are
  the HUD's, under orthographic projections. So this does not affect the crowd.
- `tools/gerec/gerec_dump.py` has no executable bit, although other tools/ scripts are run directly. The Verify line
  now runs it through `python3`. Setting the bit would be a one-line mode change outside this task's "May touch".

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

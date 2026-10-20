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
`tools/build.sh profile && tools/docs_check.py && build/arm64/bin/PureNative --replay out/gerec/race.gerec --extract $(tools/gerec/gerec_dump.py out/gerec/race.gerec --summary | python3 -c "import sys,re; f=[int(m) for m in re.findall(r'frame (\d+)', sys.stdin.read())]; print(f[len(f)//2] if f else 1)") --out out/101/verify && python3 -c "import re,sys; t=open('out/101/verify/frame.obj').read(); nv=len(re.findall(r'^v ',t,re.M)); bad=[i for i in map(int,re.findall(r'(?m)^f\s+(\d+)',t)) if i<1 or i>nv]; print('obj ok' if nv and not bad else 'obj bad'); sys.exit(0 if nv and not bad else 1)"`

(If `--summary`'s frame lines read differently, adapt the frame pick in the Verify line and say so in Result.) The
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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

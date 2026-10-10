# 063: A target sampled as a texture takes the GE's wrap mode (the billboard screens)

Milestone: M8 fidelity (difference 15) | Branch: task/063-fb-texture-wrap | Status: MERGED (08b57e2, 2026-10-10)

## Goal
The track-side advert screens show a flat colour with vertical bars where PPSSPP (and a video of the game) show the
advert's picture: docs/fidelity.md difference 15. Each advert is drawn into a 128x128 16-bit target (four rounds a
frame, docs/ge-effects.md item 2) and the screen is then drawn with that target as its texture, with the texture
scale v = -1, offset 0 and the wrap mode REPEAT (`tools/gerec/gerec_dump.py` on out/gerec/race_1x.gerec, draws
#26, #43, #63, #76 of frame 6016: u and v in [0, 0.992], scale (1, -1), offset (0, 0), wrap (0, 0)). The GE's REPEAT
takes the coordinate modulo 1, so -v becomes 1 - v: the advert, upside down. Both backends instead clamp a target
texture's coordinate at the target's edge (Metal: the sampler for a target texture is clamp on both axes,
src/gpu/metal_draw.mm "sampler = ... | 4u | 8u"; Vulkan: `push.texture_params[0] = 1.0f` drops the wrap flags for a
framebuffer texture and `frag_uv_rect` clamps, vendor/portablekit/host/gpu/vulkan_renderer.cpp around line 6700 and
shaders/ge.frag), so -v clamps to 0 and the screen shows the advert's first row stretched into bars. After this task
both backends apply the GE's wrap in the texture's own coordinate space before placing the texture in the target
image, and the screens show the adverts.

Evidence to read first, in the main checkout (read-only): /Users/erreib/dev/pure-recomp/out/billboard/:
ppsspp/f07600.png (PPSSPP, race time 0:03.4, the orange advert with its sunburst and text at about x 182-208,
y 118-138), shots2/g6490.png (the port, 0:03.9, the same screen as flat bands at about x 176-212, y 106-135),
crop_pp_big.png and crop_port_big.png (both enlarged), and ppsspp2/q*.png (PPSSPP every 20 frames from 7580, the
port's flips 6430 to 6710 are shots2/g*.png; the adverts differ between the two, the cycle is seeded from the clock).

## Read first
- CLAUDE.md, docs/fidelity.md (difference 15), docs/ge-effects.md (item 2), docs/metal-backend.md ("Targets",
  "Textures", "Texture mapping modes": `uv_remap` already places a texture inside the image for modes 1 and 2),
  docs/ge-backend.md section 6 (the Draw record's TextureState: scale, offset, wrap_s, wrap_t)
- src/gpu/metal_draw.mm (draw(): the `find_framebuffer_texture` branch and `uv_transform`), src/gpu/shaders/ge.metal
  (ge_vertex's `out.uv`, `sample_texture`), src/gpu/metal_pipelines.mm (the sampler table's address modes)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (the framebuffer-texture branch after `framebuffer_source`,
  `wrap_flags`, `uv_transform`), vendor/portablekit/host/gpu/shaders/ge.vert (`frag_uv_rect`) and ge.frag (the wrap
  block in main()), patches/README.md (how a vendor change becomes a patch)
- tools/gerec/metal_check.sh, tools/frame_regress.sh, tools/png.py (read_png)

## Deliverable
1. **Metal.** For a draw whose texture is a target (`source != nullptr`): the vertex shader hands on the texture's
   own coordinate (st * scale + offset, nothing else), and the fragment shader applies the GE's wrap per axis in
   that space (REPEAT: fract; CLAMP: clamp to [0, 1], then to the half-texel inside the edge as the Vulkan shader
   does), then places it in the image (`uv_remap`-style: * texture size / 480x272 + the texel origin). The sampler
   stays clamp on both axes (the image is the whole target). Ordinary textures are untouched (the sampler wraps
   them as today). A new fragment-uniform flag or the existing `uv_remap` path, as you judge; a pipeline key
   change is acceptable only if unavoidable (it changes config/metal_pipelines.txt: say so).
2. **Vulkan**, as a vendor patch `0015-vulkan-fb-texture-wrap`: for a framebuffer texture keep the wrap flags, pass
   the texture's own scale and offset, and in ge.frag apply fract or the clamp per axis before the placement into
   the copy's sub-rectangle (replacing the `frag_uv_rect` clamp for this case; the clamp stays for ordinary
   textures). `tools/patches.sh export 0015-vulkan-fb-texture-wrap`; a row in patches/README.md.
3. **tools/billboard_check.sh** (new): runs the race route headless on Metal to flip 6490 (as tools/frame_regress.sh
   runs main_menu.txt+single_race.txt: an empty memory stick, PURE_GAME_DIR, the scratch data directory) with a
   shot at 6490, takes a rectangle strictly inside the orange screen's surface (choose it from the capture; about
   x 182-208, y 112-130), and prints two numbers over it: the mean absolute luminance difference between vertically
   adjacent pixels and between horizontally adjacent ones (tools/png.py). Before the fix the vertical number is
   near the screen's shading alone (measure it: it is the "before"); after, the advert's picture gives a vertical
   number of the same order as the horizontal one. PASS when the vertical number is at least a threshold you set
   from the measurements with a margin (state the before, after and PPSSPP-side numbers in the Result; measure
   PPSSPP's on ppsspp/f07600.png's screen for the order of magnitude). `--backend vulkan --shell vulkan` runs the
   same in the Vulkan window. Exit 0 on PASS.
4. docs/fidelity.md difference 15: state "fixed (task 063)" with the mechanism in one sentence; docs/metal-backend.md
   "Textures": one paragraph on the wrap for a target texture; docs/ge-effects.md item 2: "(flipped)" was right, say
   the GE's REPEAT does it.

Order: Metal first (commit), the check (commit), then Vulkan (commit), docs (commit).

## Acceptance criteria
- [ ] `tools/billboard_check.sh` PASS on Metal headless and with `--backend vulkan --shell vulkan`; the Result shows
      the before and after crops (paths) and the numbers.
- [ ] `tools/frame_regress.sh` 18/18 headless; the race scenes may move by the billboards' pixels only (say by how
      much; race_hud's limit is 0.10); `tools/gerec/metal_check.sh` PASS (Metal and Vulkan agree after both fixes).
- [ ] race_1x.gerec frame 6016 replayed and cut after draw #26, before and after, on both backends: the billboard's
      footprint changed from bars to a picture, the rest of the frame identical (ge_replay --cut, --out; state the
      pixel counts).
- [ ] No ordinary texture changes: a capture of the frontend (`lang`, `title`, `main_menu`) is pixel-identical before
      and after on Metal headless (`tools/refactor_check.sh --before` on the starting commit, then after: the three
      frontend scenes 0 differing pixels; the race scenes are expected to differ).

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/billboard_check.sh`

## May touch
- src/gpu/metal_draw.mm, src/gpu/metal_backend.hpp, src/gpu/metal_types.hpp, src/gpu/shaders/ge.metal,
  src/gpu/metal_pipelines.mm (only if the sampler table must change), config/metal_pipelines.txt (only if the key
  changes)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/shaders/ge.vert, ge.frag: through
  `tools/patches.sh export 0015-vulkan-fb-texture-wrap` (commit patches/, never vendor/), patches/README.md
- tools/billboard_check.sh (new), docs/fidelity.md (row 15), docs/metal-backend.md ("Textures"), docs/ge-effects.md
  (item 2), docs/verification.md (one row for the new check)

## Must not touch
- vendor/portablekit/include/psprecomp/, the GE state (ge_state.*), src/host/, src/profile/, tools/frame_regress.sh,
  tools/gerec/, ref/, the texture decode, the dither and 16-bit paths (task 040), anything not listed above

## Estimated turns
50

## Escalate when
The wrap cannot be applied without changing what ordinary textures sample (the frontend scenes move); the Vulkan
copy's sub-rectangle is not where the shader can wrap into it (report what `framebuffer_descriptor` hands over);
the screen after the fix shows the advert but mirrored or offset by a row against PPSSPP's (a half-texel or flip
polarity question: report both pictures and stop, do not tune by eye); a pipeline key change that invalidates the
pre-warm list beyond adding keys.

## Result
Status: DONE

Changed (branch task/063-fb-texture-wrap from e12e789, four commits in the brief's order):
- 5699c44 Metal: src/gpu/shaders/ge.metal, src/gpu/metal_draw.mm, src/gpu/metal_types.hpp, src/gpu/metal_backend.hpp.
  - For a target sampled as the texture the vertex function now hands on the texture's own coordinate:
    `uv_transform` is no longer folded, and modes 1 and 2 no longer apply `uv_remap`.
  - The fragment function's new `place_in_target` applies the GE's wrap per axis in that space, then places the result
    in the 480x272 image. REPEAT is `fract`; CLAMP clamps to [0.5/size, 1 - 0.5/size] in the texture's own texels.
  - `uv_remap` moved from VertexUniforms (now 240 bytes) to FragmentUniforms (now 240 bytes, with a `wrap` uint4: x
    target, y/z clamp s/t), so `set_texture_map` lost its source parameters.
  - The target's sampler stays clamp on both axes, and the sampler table is unchanged. No pipeline key change, so
    config/metal_pipelines.txt is untouched. Ordinary textures take the old path.
- aa706ce tools/billboard_check.sh (new). It runs the race route headless on Metal (or `--backend vulkan --shell
  vulkan`) to flip 6490 with a shot there. Over x 169-180 y 119-131 (inside the orange screen, left of the strut that
  crosses it), it prints the mean absolute luminance step between vertically and horizontally adjacent pixels.
  PASS: vertical >= 8.
- fc18f4b patches/0015-vulkan-fb-texture-wrap.patch (new; vendor host/gpu/vulkan_renderer.cpp, shaders/ge.vert,
  ge.frag) with its row and section in patches/README.md. `tools/patches.sh check`: ok, 15 patches reproduce the pin.
  - For a framebuffer texture the wrap flags stay, and `uv_transform` stays the texture's own.
  - `texture_params.x` gains `kPushPlaced` (2^20). A target has no mip levels, so bits 5-19 stay clear.
  - The object block is written for every target draw (`lit || mapped || placed`), with `uv_remap` = the copy's
    sub-rectangle. ge.vert hands it on in `frag_uv_rect`, replacing the through-mode tile clamp for this case, and
    `map_texture` no longer applies it.
  - ge.frag: `fract` or the half-texel clamp per axis, then `uv * rect.xy + rect.zw`. The texture's size is
    `frag_uv_rect.xy * viewport.xy`.
  - `framebuffer_descriptor` hands over the whole target's copy (target_extent, sampled 0..1). The texture's
    sub-rectangle is (x, y, w, h) / 480x272 of it, so the shader can wrap into it (no escalation).
- a1e44e7 docs: fidelity.md difference 15 ("fixed (task 063)"), metal-backend.md "Textures" (one paragraph and a
  pointer in the "From a target" bullet), ge-effects.md item 2 ("(flipped)" is the GE's REPEAT taking -v modulo 1),
  verification.md (a row for billboard_check). `tools/docs_check.py`: 0 findings.
- This Result.

Numbers, by acceptance criterion:
- **billboard_check** (vertical / horizontal):

  | Run | Before | After |
  |---|---|---|
  | Metal headless | 2.00 / 20.25 | 18.70 / 12.45 |
  | Vulkan window | 1.70 / 24.57 | 18.92 / 11.46 |
  | PPSSPP | | 25.59 / 26.74 |

  - The PPSSPP figure is from /Users/erreib/dev/pure-recomp/out/billboard/ppsspp/f07600.png, x 181-187 y 121-127
    (inside its screen, left of its strut). Over its whole screen with the strut: 24.76 / 20.43.
  - The threshold is 8, four times the bars' figure and under half of the picture's.
  - Crops (the rectangle, 8x) under /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-add0c6966f7211031/out/billboard_check/:
    - before-metal/crop.png, after-metal/crop.png (also metal-headless/crop.png, the Verify run);
    - before-vulkan/crop.png, after-vulkan/crop.png.
  - The whole shots are in `shots/b6490.png` beside each crop.
  - The capture puts the screen at x 167-198 y 117-133 at race time 0:03.9 in both shells, not at the brief's estimate
    of x 182-208.
- **frame_regress**: 18/18 headless on Metal. Only the billboards' pixels moved:
  - race_hud: 145 px, fraction 0.0148 to 0.0148.
  - tt_hud: 595 px, 0.0113 to 0.0112.
  - fp_hud: 590 px, 0.0115 to 0.0116.
  - The zone scenes: 0 px.
  - The diff images (out/refactor/*.diff.png in the worktree) show red only on the two screens of each scene.
- **The Vulkan window suite** (`--shell vulkan --backend vulkan`): 18/18 PASS (19m 48s): race_hud 0.0466, tt_hud 0.0492 and fp_hud 0.0475, every scene within 0.01 of the vulkan column (out/regress_vulkan in the worktree).
- **metal_check**: PASS, after both fixes.
  - team: 0/130560 px at tol 24, both frames.
  - race_1x frame 6016: 2/130560 at tol 24, the same as the main checkout's last run.
- **race_1x frame 6016 replayed with `--cut 27`** (cut after draw #26), before and after, on both backends, `--out`.
  Captures and footprint crops are in the worktree's out/cut063/ (cut27_footprint.png: Metal top, Vulkan bottom,
  before left, after right).
  - Draw #26's footprint (where it changes the cut after #25): 126 px, x 201-216 y 126-133.
  - Metal: 15 px changed, all inside the footprint, 0 outside. Vulkan: the same 15 px, 0 outside.
  - At the cut, Metal and Vulkan are pixel-identical both before and after (0 px).
  - The picture: before, flat red. After, the PIRANHA advert's yellow logo at x 209 y 129-130 and its text row at
    y 131-132. PPSSPP's ref/vineta_k_start.png (the same moment) has the logo on the same pixels. The advert in
    PPSSPP's own VRAM (`ppdmp.py tex` draw 26, out/cut063/pp_tex26.png) has the logo in the middle and the text in the
    lower third, as the port's screen shows.
  - Not mirrored, not flipped. A one-row offset cannot be seen at this size (128 rows over 7 screen rows), so there was
    nothing to tune.
  - The sunburst advert's close view at flip 6530 (out/billboard_seq/after-metal/shots) has the sun at the top right with
    rays down and a glyph on the left, as PPSSPP's q7660.
- **No ordinary texture changes.**
  - `tools/refactor_check.sh --before` was run on e12e789 before any edit. After: lang, title and main_menu have 0
    differing pixels, and so do the other 12 non-race scenes plus zone_hud and zone_change. Counts are the same in
    every route (86 [metal] lines).
  - On Vulkan, team.gerec replays to 0 px change between the build without 0015 and with it.
- **The whole race frame on Vulkan.**
  - race_1x frame 6016 changes by 380 px: 36 on the billboards (Metal's 36) and 344 elsewhere, at most 4 levels.
  - All 344 now equal Metal's pixels: the bloom's coordinates are now interpolated in the texture's own space, as on
    Metal. Vulkan against Metal at tol 0 goes from 523 px to 179.

Verify output (last 20 lines):
```
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)
billboard_check: backend metal, shell headless, shot at flip 6490, out /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-add0c6966f7211031/out/billboard_check/metal-headless
billboard_check: run_boot exit 0, frame 6500 reached: yes, 6 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-add0c6966f7211031/out/billboard_check/metal-headless/run.log
rectangle x 169-180 y 119-131 of /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-add0c6966f7211031/out/billboard_check/metal-headless/shots/b6490.png (480x272), crop /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-add0c6966f7211031/out/billboard_check/metal-headless/crop.png
vertical 18.70 horizontal 12.45 (mean absolute luminance difference of adjacent pixels)
billboard_check: PASS, vertical 18.70 against the threshold 8
verify 063: PASS
```

Open questions:
1. A stale clause in docs/metal-backend.md "Texture mapping modes", which is outside May touch ("Textures" only):
   "A target sampled as a texture keeps its place in the image applied (`uv_remap`, what `uv_transform` folds in for
   mode 0)". `uv_remap` is now a fragment uniform applied after the wrap for every mode, and `uv_transform` no longer
   folds it in.
2. Vulkan above internal scale 1: a through-mode draw that samples a target (the bloom's blur tiles) loses
   `clamp_through_quad`'s tile clamp, as the brief's "replacing the frag_uv_rect clamp" implies. race_warm frame 6016
   (2x) moves 38701 px: 35772 by 1 level, and 508 by more than 4 outside the billboards, at most 11 levels along a
   blur-tile seam (x 638-639). Keeping both would need a second flat varying.
3. REPEAT and bilinear at the wrap seam: within half a texel of the texture's edge the sampler blends with the pixel
   beyond the texture in the target's image, not with the far edge's texel as the GE does. For the billboards that
   only happens when a screen is about 128 px tall or more. Not tuned.
4. No `<prefix>_NO_...` off switch for the new wrap, unlike patches 0011-0014. The brief did not ask for one.

## Review
Verify rerun: from the main checkout after the merge and patch 0015 applied to the vendor tree (15 patches reproduce
the pin), 2026-10-10: PASS (frame suite 18/18 headless; billboard_check Metal vertical 18.70 / horizontal 12.45).
The gate: `--shell metal --backend metal` 18/18 (19m 48s); `--shell vulkan --backend vulkan` 18/18 (20m 0s; race_hud
0.0466, tt_hud 0.0491, fp_hud 0.0470 against the column's 0.053, 0.048, 0.056); `billboard_check --backend vulkan
--shell vulkan` PASS (13.76 / 7.69); `tools/hud_check.sh` 61/61; `tools/gerec/metal_check.sh` PASS.
Spot-read: ge.metal's `place_in_target` (fract for REPEAT, the half-texel clamp in the texture's own texels for
CLAMP, then uv * size + origin) and the Vulkan patch's equivalent in ge.frag; the sampler table untouched; the
cut-27 proof (15 px, all inside draw #26's footprint, Metal and Vulkan identical) is the right evidence that only
the placement changed. The main checkout's capture of flip 6490 shows the sunburst advert on the orange board.
Merged: `git merge --no-ff` into batch/m2, 08b57e2; the stale "Texture mapping modes" sentence (open question 1)
fixed at the merge (dd19dc7).
Notes: the Vulkan whole-frame change of 344 px outside the billboards is the bloom's coordinates now interpolated
in the texture's own space, which brings Vulkan to Metal's pixels (523 to 179 differing at tol 0): a gain.
Follow-ups recorded in docs/status.md: the through-mode tile clamp lost on Vulkan above internal scale 1 (open
question 2, E3's territory); bilinear at the REPEAT seam blends with the target's neighbour pixel rather than the
far edge (open question 3; a screen 128 px tall or more); no off switch for the wrap (open question 4).

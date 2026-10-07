# 037: Mipmaps (fidelity difference 2)

Milestone: M8 | Branch: task/037-mipmaps | Status: MERGED 2026-10-07 (91a7980)

## Goal
Distant textures shimmer: crowds, the track surface, windows. 70 to 87% of the race's textured draws name mip levels
(TEXADDR1 to 7, TEXSIZE1 to 7) and a level rule (TEXLEVEL mode and bias, TEXLODSLOPE), and the framework's GE state
ignores all of them, so every backend samples level 0. This task carries the levels in the state (a vendor patch),
uploads them in the Metal backend, and selects the level as the GE does.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 2: Blue Ridge's grandstands, the evidence), docs/metal-backend.md (the
  texture cache: content key, `decoded_texture`, the samplers' filter bits; "Where it differs"), docs/tasks/036 (Result:
  how patch 0013 extended `TextureState` and the record format; follow the same shape)
- vendor/portablekit/host/gpu/ge_state.hpp and .cpp (`TextureState`: address, buffer width, size, format, swizzle,
  filters: `min_filter`/`mag_filter` carry the GE's mipmap filter bits already), host/gpu/texture_decode.hpp and .cpp
  (`decode_texture` decodes level 0; what it needs per level: address, buffer width, size)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: texture levels, the LOD rule: TEXLEVEL mode 0 auto from
  the derivatives, 1 constant from the bias, 2 slope with TEXLODSLOPE and the bias; the per-level sizes halve;
  up to 8 levels)
- src/gpu/metal_backend.mm (`decoded_texture`, the content hash, the sampler table), src/gpu/metal_shaders.h
  (`ge_fragment`'s sampling)

## Deliverable
1. Patch 0014 (`tools/patches.sh export 0014-texture-mip-levels`): `TextureState` carries the level count the GE
   gives, each level's address, buffer width, width and height (the GE's per-level registers), and the level rule
   (`level_mode`, `level_bias`, `lod_slope`); `ge_state.cpp` sets them; the record format gains them at the end;
   `gerec_dump.py` parses them. The Vulkan backend stays on level 0 (a comment); its suite is unchanged.
2. The Metal backend: a texture with levels is a mipmapped `MTLTexture`, each level decoded with the framework's
   decoder from its own address (the content hash covers every level's texels and the palette); the sampler's
   mip filter follows the GE's bits (`min_filter` bit 2: nearest or linear between levels); the level rule: mode 0
   lets Metal pick the level from the derivatives (the GE's auto mode is the same idea; the bias applies through
   `lodBias`-equivalent or a shader `bias`), mode 1 a constant level from the bias (`sample` with `level()`), mode
   2 the GE's slope formula from the distance (`bias` per draw computed as the docs give it, applied in the shader).
   Textures the GE names one level for are unchanged.
3. The check: Blue Ridge's first race frame against its PPSSPP reference (`ref/blue_ridge_hud.png` from the audit's
   reference table, with the route the audit used for it, or `race_hud` on Vineta K if Blue Ridge has no port
   route yet: say which) before and after, and the shimmer gone in a 60-flip sequence of Blue Ridge's straight (the
   per-frame fraction between consecutive frames drops; report the numbers).
4. docs/metal-backend.md (mipmaps: upload, the level rule, the cache key), docs/fidelity.md (difference 2's row with
   the result), patches/README.md, README.md if a switch is added (`PURE_NO_MIPMAPS` for A/B).

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (headless Metal) passes with no scene more than 0.003 above its measured value, and
      the race scenes at or below theirs.
- [ ] Blue Ridge's first race frame against PPSSPP improves by at least 0.01 (0.053 at tol 32 in the audit).
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` unchanged; `tools/patches.sh check` 14 patches;
      `tools/hud_check.sh` 61 of 61; the texture cache's count of decodes in a race does not grow by more than the
      levels (report the exit line before and after).

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh && tools/hud_check.sh --shell headless`

## May touch
- vendor/portablekit/host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp, texture_decode.hpp and .cpp (a
  per-level entry point if needed), vulkan_renderer.cpp (a comment), via `tools/patches.sh export 0014-texture-mip-levels`;
  patches/; src/gpu/; tools/gerec/gerec_dump.py; docs/metal-backend.md, docs/fidelity.md (difference 2), README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/hle/, host/shell/, src/host/, src/profile/, src/tools/, tools/frame_regress.sh,
  config/, ref/, patches/0001-0013

## Estimated turns
70

## Escalate when
The GE's level rule for mode 2 cannot be matched to the reference within the shimmer check (report the pictures for
the candidate formulas), or a level's address lies outside guest memory or inside a render target (report which
texture; draw level 0 for it).

## Result
Status: DONE

What was done:
- **Patch 0014** (`0014-texture-mip-levels`): `TextureState` now carries the mip levels.
  - The fields: `level_count` (TEXMODE 0xC2 bits 16..18, plus one), and `levels[7]` of `TextureLevel` (address, row
    length, width, height) from TEXADDR1 to 7, TEXBUFWIDTH1 to 7 and TEXSIZE1 to 7. The level rule is `level_mode`
    and `level_bias` (TEXLEVEL 0xC8: mode in bits 0..1, signed bias in 1/16 levels in bits 16..23) and `lod_slope`
    (TEXLODSLOPE 0xD0).
  - The 23 commands left the ignored list: 40 distinct remain, from 63.
  - The record format writes the levels at the end of a Draw (`Writer::put_levels`, 100 bytes). A Draw that ends
    before them reads as one level, and `kVersion` stays 1.
  - `gerec_dump.py` lists `levels N auto|slope bias B slope S`.
  - The Vulkan renderer is unchanged; a comment says it samples level 0.
  - The register layout is the PSP SDK's. The rule is PPSSPP's hardware notes' ("Mip level selection", "A float-bits
    logarithm"); no PPSSPP code was read.
- **Metal**:
  - When `min_filter` bit 2 is set, a texture is a mipmapped `MTLTexture` with the GE's level count. Each level is
    decoded with `decode_texture` from a `TextureState` copy that holds that level's address, row length and size,
    so the framework needed no per-level entry point. A level must halve the one before, lie in guest memory and
    overlap no render target; otherwise the texture is drawn at level 0 alone and logged once. No run hit this.
  - The content key hashes every level's place and texels, then the palette.
  - The sampler's mip filter follows `min_filter` bit 1.
  - `sample_texture` in the shader computes the GE's D with the GE's float-bits log16:
    - auto: log16(g) - log16(q), where g is the largest of the s/t screen gradients in texels
    - constant: the bias
    - slope: 16 + log16(slope) - log16(q) + bias
    - q is `position.w` (1/w) times the texture matrix's q. D is clamped to the levels, and the shader samples with
      `level(D/16)`.
  - `PURE_NO_MIPMAPS=1` is the A/B switch. It reproduces the 18 suite captures and the Blue Ridge frame of the build
    before the task pixel for pixel.
- **How the game uses levels** (PPSSPP's dumps):
  - Every mipmapped draw uses min filter 7, except three a frame that use filter 1.
  - Every level halves the one before.
  - In Blue Ridge's frame, 830 of 949 textured draws have levels: 224 in auto mode with bias 0, and 606 in slope mode
    with a per-draw bias (-90 to 89). The slope is always 1/256.
  - No draw uses constant mode or a CLUT per level.

The check, all headless Metal at tol 32. Blue Ridge's reference was not in the main checkout's `ref/`, so I made it
again with `ref/README.md`'s run J command into `out/ppsspp/`. The PNG and the GE dump are byte-identical to the
README's hashes. The port frame uses the audit's route (main_menu.txt + single_race.txt, DOWN at 5380, 5410 and 5440,
flip 6016), not `race_hud`.

| Fraction against PPSSPP | Before | After |
|---|---|---|
| Blue Ridge, first race frame | 0.0392 | 0.0247 (-0.0145) |
| Blue Ridge at tol 16 | 0.0912 | 0.0487 |
| Blue Ridge, right grandstand (300,60) 180x90 | 0.1418 | 0.0920 |
| race_hud | 0.0262 | 0.0149 |
| tt_hud | 0.0229 | 0.0112 |
| fp_hud | 0.0232 | 0.0116 |
| zone_hud | 0.0122 | 0.0121 |
| zone_change | 0.0353 | 0.0353 |
| the 13 frontend scenes | | unchanged pixel for pixel |

The audit's 0.0534 for Blue Ridge predates task 036. Moving the slope rule's D by -48 to +48 sixteenths gave these
results:
- At tol 32: 0.0388, 0.0374, 0.0323, 0.0298, **0.0247** (offset 0), 0.0237 (+8), 0.0256, 0.0352, 0.0526.
- At tol 16: the documented rule (offset 0) is the best, 0.0487.
- So mode 2 matches the reference within half a level, and nothing escalated.

The shimmer sequence: 60 consecutive flips of Blue Ridge's start straight (6340 to 6399, Cross held). Each frame
against the next, at tol 32:

| Region | Before (mean, min to max) | After |
|---|---|---|
| whole frame | 0.0845 (0.0650 to 0.1149) | 0.0603 (0.0426 to 0.0926) |
| right grandstand (300,60) 180x90 | 0.1902 (0.1625 to 0.2466) | 0.1124 (0.0793 to 0.1887) |
| left grandstand (0,60) 180x90 | 0.1248 (0.0975 to 0.1546) | 0.0586 (0.0321 to 0.0862) |
| track (0,130) 480x80 | 0.0745 (0.0559 to 0.1007) | 0.0596 (0.0424 to 0.0874) |

The mean absolute change per frame went from 7.30 to 5.88 levels.

Decode counts: the textures decoded do not change. The added levels are reported separately. The suite's race
route, exit line before and after:
```
[metal] 6046 frames, 372713 draws, 8970 passes, 646 textures decoded, 1983 framebuffer textures, 44158 texture-mapped draws, 0 target copies, 0 uploads, 5 targets, 628 GPU waits (228.691 ms) in 4.11683 s
[metal] 6046 frames, 372713 draws, 8970 passes, 646 textures decoded, 1983 framebuffer textures, 44158 texture-mapped draws, 192857 mipmapped draws (596 mip levels decoded after the first), 0 target copies, 0 uploads, 5 targets, 686 GPU waits (275.283 ms) in 4.20755 s
```
- Blue Ridge to flip 6020: 612 textures before and after, plus 525 levels.
- Time Trial: 566 textures, plus 361 levels.
- Zone: 433 textures, plus 52 levels.

Acceptance:
- Suite 18/18. No scene is above its measured value; the race scenes are 0.011 lower and zone_hud 0.0001 lower.
- Blue Ridge improves by 0.0145.
- `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18, every scene within 0.0005 of its vulkan column
  (19m 48s).
- `tools/patches.sh check`: 14 patches.
- `tools/hud_check.sh`: 61 of 61, both headless (Verify) and in the Metal shell's window.

Changed: patches/0014-texture-mip-levels.patch (vendor host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp, a
comment in vulkan_renderer.cpp), patches/README.md, src/gpu/metal_backend.mm, src/gpu/metal_shaders.h,
tools/gerec/gerec_dump.py, docs/metal-backend.md ("Mipmaps" with the rule, upload, shader, check and recordings;
the switch, the sampler and uniform notes, the Vulkan differences, "Verify numbers / Task 037"), docs/fidelity.md
(difference 2's row), README.md (`PURE_NO_MIPMAPS`, the `PURE_METAL_LOG` tag).

Verify output (last 20 lines; `tools/verify_task.sh 037` at 914c201, 2026-10-07):
```
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0229 -0.0117  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0232 -0.0116  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0121   0.09   32    0.0122 -0.0001  PASS
zone_change   5679    0.0353   0.10   32    0.0353 +0.0000  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 25s)
hud_check: shell headless, backend metal, 61 shots from flip 6200 to 7700, out /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-ad2cab7a0a0c8b8fd/out/hud/headless
hud_check: run_boot exit 0, frame 7710 reached: yes, 13 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-ad2cab7a0a0c8b8fd/out/hud/headless/run.log
6200:H 6225:H 6250:H 6275:H 6300:H 6325:H 6350:H 6375:H 6400:H 6425:H 6450:H 6475:H 6500:H 6525:H 6550:H 6575:H 6600:H 6625:H 6650:H 6675:H 6700:H 6725:H 6750:H 6775:H 6800:H 6825:H 6850:H 6875:H 6900:H 6925:H 6950:H 6975:H 7000:H 7025:H 7050:H 7075:H 7100:H 7125:H 7150:H 7175:H 7200:H 7225:H 7250:H 7275:H 7300:H 7325:H 7350:H 7375:H 7400:H 7425:H 7450:H 7475:H 7500:H 7525:H 7550:H 7575:H 7600:H 7625:H 7650:H 7675:H 7700:H
hud_check: 61 of 61 shots have the HUD
verify 037: PASS
```

Open questions:
1. **Recordings miss the levels' texels.** `record_backend.cpp` is outside May touch, and it records only the bytes
   of level 0. A recording made since patch 0014 therefore replays mipmapped draws with levels 1 and up read from
   ge_replay's zeroed memory.
   - Blue Ridge frame 6016 recorded through Metal replays 0.0913 off its own picture at tol 32.
   - Recorded and replayed with `PURE_NO_MIPMAPS=1`, it is exact.
   - The fix is one loop in `RecordBackend::submit` that records `texture_bytes` of each level. Until then, replay
     new recordings with `PURE_NO_MIPMAPS=1`.
2. **The Blue Ridge reference is outside ref/.** It was missing from the main checkout's `ref/` (the brief said it
   was there). It now exists only as `out/ppsspp/blue_ridge_hud.{png,ppdmp}` in this worktree, because `ref/` is
   Must not touch. Blue Ridge also has no route in `config/pad_scripts/`, so it is not a suite scene. The PPSSPP run
   also left its usual copy of the dump in `~/.config/ppsspp/PSP/SYSTEM/DUMP/UCUS98612_0044.ppdmp`.
3. **The suite's metal column is stale for the race scenes.** They moved by -0.011, which is under the 0.03 drift
   flag. Re-baselining needs `tools/frame_regress.sh`, which is Must not touch. The new values are race_hud 0.0149,
   tt_hud 0.0112, fp_hud 0.0116 and zone_hud 0.0121.
4. **Rules the notes do not settle.** The game exercises only the second, in three draws a frame:
   - The auto mode's bias: the notes' formula has none, and every auto draw in the game has bias 0.
   - A min filter without bit 2 on a texture with levels: I draw level 0, going by the SDK's names (three draws a
     frame).
   - The GE takes q once per 4-pixel span; I take it per pixel.
   - A CLUT per level (TEXMODE bit 8) is not carried.
5. **What still differs on Blue Ridge.** The AI grid differs, and the BLUERIDGE banner is brighter and wider in
   PPSSPP's frame. The banner may still be a level question for that one draw: in the offset scan the right
   grandstand region kept improving up to +32 while the whole frame got worse. I did not look into it.
6. **Files outside May touch that are now out of date:**
   - `tools/fidelity_audit.py`'s `METAL_EXIT_RE` has not matched the exit line since task 036 inserted "texture-mapped
     draws". This task keeps the line's start and adds its counts after that.
   - `docs/ge-backend.md` section 6 (the Draw record) is outside May touch. The record format header is updated.

## Review
Verify rerun: PASS from the main checkout on the merged build (fifteen patches, 0001 to 0015), 2026-10-07: the
headless suite 18/18 with the race scenes at the re-baselined values exactly (race_hud 0.0149, tt_hud 0.0112, fp_hud
0.0116, zone_hud 0.0121), `tools/hud_check.sh --shell headless` 61 of 61. The Blue Ridge reference the worker remade
(byte-identical to ref/README.md's hashes) was copied into the main checkout's `ref/`.
Spot-read: patch 0014 (`TextureLevel` x7 and the level rule in `TextureState`, the Draw record's 100 bytes appended;
the Vulkan comment), the Metal upload of levels through per-level `TextureState` copies and the content hash over
every level, the shader's float-bits log16 rule for auto and slope modes, `PURE_NO_MIPMAPS`.
Merged: 91a7980 into batch/m2 (patches/README.md rows 0014 and 0015 ordered by hand); the suite's Metal column
re-baselined (f3a5add); `tools/fidelity_audit.py`'s exit-line regex updated for the new counts (e5a184b).
Notes: the record backend records only level 0's texels, so recordings made since patch 0014 replay mipmapped draws
from zeroed memory: folded into task 040's patch 0017 (record every level). Blue Ridge still has no port route, so
it is not a suite scene (follow-up: the scenes without routes). The rules the notes do not settle (auto mode's bias,
a non-mip min filter on a texture with levels, q per 4-pixel span, a CLUT per level) are listed in
docs/metal-backend.md; the game exercises only the second, on three draws a frame.

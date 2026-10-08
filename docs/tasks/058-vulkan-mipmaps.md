# 058: Vulkan: mip levels at the GE's rule

Milestone: W3 (docs/windows.md step 3) | Branch: task/058-vulkan-mipmaps | Status: OPEN

## Goal
The Metal backend since task 037 uploads the mip levels a draw names and samples at the level the GE's rule
picks; the Vulkan renderer uploads and samples level 0 alone. Port the levels and the rule into the Vulkan
renderer as a vendor patch. Task 040 measured what this is worth: race frame 6016 compared Metal-to-Vulkan is
0.0219 at tol 24 with mipmaps as the only difference.

## Read first
- docs/metal-backend.md, "Mipmaps" ("The registers and the rule", "How the game uses them", "Upload")
- docs/tasks/037-mipmaps.md (how the Metal side was measured; the rule's edge cases)
- src/gpu/metal_textures.mm (`mip_levels`, the level rule — the reference; read, do not touch)
- src/gpu/shaders/ge.metal (the level in the fragment shader)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (texture upload and samplers), shaders/ge.frag
- tools/gerec/metal_check.sh's note (task 040): when recordings are re-made, `PURE_NO_MIPMAPS=1` must be beside
  `PURE_NO_TEXMAP=1` — after this task and 057 those switches stop being needed on the Vulkan side; the note
  changes meaning. Update the docs that carry it.
- patches/README.md

## Deliverable
A vendor patch (export as 0012-vulkan-mipmaps): the levels uploaded (the GE names their addresses and strides),
the sampler's mip filter from the GE's filter bits, the level chosen by the same rule Metal implements, and
draws that name one level unchanged.

## Acceptance criteria
- [ ] race frame 6016 replayed from this machine's race_warm recording: the mip-dependent draws sample the level
      the rule picks (verify with one cut draw, as "Checking a draw" does, against the same draw on Metal's
      documented behaviour)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18, the race scenes moved toward the Metal
      column; no non-race scene moved more than 0.003
- [ ] `tools/gerec/replay_check.sh` passes
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/, out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/, config/, tools/

## Estimated turns
30

## Escalate when
The recording format does not carry a level's bytes (a GE state or recorder change would be needed); a vendor
host rebuild exceeds 5 minutes.

## Result
Status: DONE

Changed:
- patches/0012-vulkan-mipmaps.patch (new; vendor host/gpu/vulkan_renderer.cpp, shaders/ge.frag), plus its row and
  section in patches/README.md.
  - `mip_levels` is a port of Metal's. It returns the GE's level count when `min_filter` bit 2 is on and every level
    halves the one before, lies in guest memory and overlaps no render target. Otherwise it returns 1 and names the
    texture once (`[render] texture ... drawn at level 0 alone`). No run printed that line.
  - The texture image gets that many mip levels. Each level is decoded with `decode_texture` from `texture_level(state,
    n)` and uploaded into its own mip level. A level decodes in the background when level 0 does (one `DecodeJob` per
    level, and `PendingTexture` carries the level); otherwise it decodes at once. `transition`, `upload_texture` and
    `create_image` take the level. The cache key and the per-list memo cover every level's key and place.
  - Mipmapped textures use their own samplers, `mip_sampler` and `mip_sharp_sampler` (linear between levels,
    `VK_LOD_CLAMP_NONE`). The single-level samplers are unchanged. `set_sharp_textures` rewrites them by level count.
  - The rule. The push constants are full, so `texture_params.x` gets bits 5-6 for the rule (1 auto, 2 constant,
    3 slope), bit 7 for linear between levels (`min_filter` bit 1), and bits 8 and up for the draw-constant part of D
    plus 2048. That part is 0 for auto, the bias for constant, and 16 + log16(slope) + bias for slope.
  - `mip_lod` in `ge.frag` is Metal's `sample_texture`. It adds log16(g) for auto (g is the largest screen gradient
    of st = uv x 1/w, in level-0 texels) and subtracts log16(q) for auto and slope, where q = `gl_FragCoord.w` x the
    texture matrix's q. Both use the same float-bits log16. D is clamped to 0..16 x (levels - 1). The nearest mip
    filter takes level (D + 8) >> 4. The texel is `textureLod`. A clamped wrap clamps at the half-texel of the
    coarser level sampled.
  - One deliberate addition. At internal scale s > 1, the auto rule's constant adds round(16 x log2 s), which is +16
    at the suite's 2x. This keeps g per PSP pixel, as on the GE and on Metal at 1x.
  - `PURE_NO_MIPMAPS=1`, via `portablekit::env("NO_MIPMAPS")` (the name Metal reads), restores the old path.
  - Host rebuild: 11 s. No include/psprecomp/ change. `tools/patches.sh check`: 12 patches reproduce the pin.
- docs/metal-backend.md: three statements said the Vulkan backend samples level 0, and this patch makes them false.
  The "Mipmaps" intro and the Recordings note now say the A/B switches are no longer needed. The "differs on purpose"
  bullet now gives the internal-scale term.
- docs/status.md:
  - A resolved row.
  - Task 040's follow-up rewritten: `metal_check.sh` should drop `PURE_NO_TEXMAP=1` on its next re-record, not add
    `PURE_NO_MIPMAPS=1`. That is a tools/ change, which I did not make.
- docs/fidelity.md: difference 2 names the Vulkan renderer.

Evidence, per acceptance criterion:
- **The cut draw.** Recordings were made with the 0011 build on this machine. The first replay_check passed (498 s).
  In race_warm frame 6016 (884 draws), the right grandstand crowd is #417: clut4 64x64, 4 levels, slope, bias 28,
  slope 1/256. I found it by cutting with mipmaps on and off over PSP (300,105)-(470,145).
  - The draw's own pixels (cut 418 against cut 417) are 20133 px at 960x544, PSP (283,100)-(479,150).
  - Mipmaps on against `PURE_NO_MIPMAPS=1`: 14900 of those pixels differ, 3159 by more than 32, mean 25.8. The crop
    (out/ab/draw_418_off_on.png) shows the distant rows softened and the near rows unchanged. That is what task 037
    documents for Metal on the Blue Ridge grandstands.
  - The level itself. A throwaway build of ge.frag, since reverted, wrote each mipmapped pixel's D and -log16(q). A
    script then recomputed Metal's documented slope rule from that q: D = clamp(16 + log16(1/256) + 28 - log16(q),
    0, 48) = clamp(G - 84, 0, 48). It matched all 20133 pixels, with no mismatch. D runs 0 to 25 (up to level 1 +
    9/16), and the draw uses the linear mip filter.
  - The auto rule was not checked this way: every auto draw in the frame is blended, which garbles the debug colours.
- **Off path byte-identical.** I kept a copy of the 0011-only binary. It and this build with `PURE_NO_MIPMAPS=1`
  replay all 9 frames of race_warm (the level-0 recording) to identical BMPs (cmp).
- **The suite.** 18/18. The race scenes moved toward the reference:

  | Scene | Task 057's run | This run |
  |---|---|---|
  | race_hud | 0.0590 | 0.0480 |
  | tt_hud | 0.0707 | 0.0622 |
  | fp_hud | 0.0721 | 0.0623 |
  | zone_hud | 0.0478 | 0.0461 |
  | zone_change | 0.0518 | 0.0501 |

  The 13 non-race scenes match task 057's fractions to the 4th decimal (no move above 0.003).
- **replay_check.** The race recordings made before the patch hold level-0 pictures: on that recording, frame 6016
  with mipmaps differs by 0.0154 at tol 32. So race.gerec and race_warm.gerec were made again with this build; the
  old ones are kept in out/gerec_level0/. `tools/gerec/replay_check.sh`: PASS (411 s). Step 2, race_warm frames
  6014-6016: 0 px at tol 4. Frontend and title: 0 px at tol 0.
- `python tools/docs_check.py`: PASS (33 files, 0 findings).

Verify output (last 20 lines), `tools/verify_task.sh 058`:
```
main_menu    4700    0.0330   0.05   24     0.033 +0.0000  PASS
race_hud     6016    0.0480   0.10   32     0.067 -0.0190  PASS
single_player   4765    0.0251   0.05   24     0.025 +0.0001  PASS
class_select   4990    0.0452   0.07   24     0.045 +0.0002  PASS
league_select   5185    0.0614   0.08   24     0.062 -0.0006  PASS
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0622   0.12   32     0.096 -0.0338  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0623   0.11   32     0.095 -0.0327  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0461   0.09   32     0.065 -0.0189  PASS
zone_change   5679    0.0501   0.10   32     0.082 -0.0319  PASS

moved more than 0.03 from the vulkan measured value: tt_hud fp_hud zone_change (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (20m 13s)
verify 058: PASS
```

Open questions:
1. tt_hud, fp_hud and zone_change are flagged as having moved more than 0.03. All three moves are downward, toward
   the reference. Per task 056's review the column is not re-baselined here; it is re-measured at step 3's exit.
2. "Toward the Metal column" is judged against the reference. There is no Metal run on this machine.
3. The internal-scale term for the auto rule (+16 at 2x) is a choice, made so that g is per PSP pixel. Metal draws
   at 1x and needs no such term. It is named in docs/metal-backend.md. Without it, auto draws would sample one level
   sharper than the GE at 2x.
4. README.md's `PURE_NO_MIPMAPS` row still says "The Vulkan backend samples level 0 either way". README.md is outside
   May touch, so a follow-up should correct it. Its `PURE_NO_TEXMAP` row has the same stale wording since task 057.
5. tools/gerec/metal_check.sh still sets `PURE_NO_TEXMAP=1` for its race A/B and has the old comment. tools/ is
   outside May touch, so the change is recorded in status.md.
6. The auto rule's level was not checked pixel by pixel, because its draws are blended. The constant rule is used by
   no draw of the game.

## Review
Verify rerun: from the main checkout after the merge (12 patches reproduce the pin), 2026-10-08: PASS, 18/18 in
20m 14s; the moved flags are downward, as the Result predicts.
Spot-read: patch 0012 (604 lines) ports Metal's mip_levels and sample_texture faithfully; the per-pixel slope
check over the grandstand draw is the series' strongest evidence; the internal-scale term (+16 at 2x) is a
reasoned, documented choice and accepted.
Merged: the merge commit after 8fc535a into batch/m2.
Notes: the two out-of-scope follow-ups (README's stale level-0 rows, metal_check.sh's NO_TEXMAP) were done at
the merge (commit 626531e) and the task-040 follow-up row is resolved. The auto rule stays unverified pixel by
pixel (its draws are blended), as on Metal. The column re-measure stays parked at step 3's exit.

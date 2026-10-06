# 019: Depth write-back for the lens flare's CPU read

Milestone: M3 fidelity | Branch: task/019-lens-flare-depth-readback | Status: OPEN

## Goal
After the sky cube the game raises GE SIGNAL 0x0200; its handler reads the depth buffer with the CPU around the sun
(a 4x4 area, every other pixel; 0 means open sky) to decide how much lens flare to draw (docs/ge-effects.md, task
008). Our port performs the read, but the renderer keeps depth in per-target Vulkan images and never writes it back
to guest VRAM, so the game reads whatever is in guest memory (zeros) and the flare is never occluded. Make that read
return the rendered depth: at the SIGNAL (or at every GE list sync while a depth target exists), write the depth
target back into guest memory in the PSP's Z16 layout for at least the region the game reads.

## Read first
- CLAUDE.md, docs/ge-effects.md (the lens-flare section: which SIGNAL, which addresses 0x04110000/0x44110000, the
  16+1 loads per frame task 008 saw with `PSPRECOMP_TRACE_VRAM_READS`), docs/research.md (PPSSPP's compat flag
  `SoftwareRasterDepth` exists for exactly this game), patches/0004-0007 (how renderer patches are made),
  vendor/portablekit/host/gpu/vulkan_renderer.cpp (`write_back_frame`, `read_back_framebuffer`, how a target's
  colour is written back; the depth image format D32_SFLOAT_S8_UINT since 0006), host/hle/hle_media.cpp (the GE
  callback/SIGNAL delivery and `sceGeListSync`), PPSSPP's GE docs on the depth buffer layout (Z16, 512 stride here)

## Deliverable
1. A depth write-back: on the SIGNAL that the game uses for the flare (identify it in the HLE: the GE callback id
   and the signal value), read the current depth target back (a small region around the sun is enough if the read
   addresses can be predicted from the game's loads; otherwise the whole 512x272 Z16 buffer, which is 272 KB) and
   store it into guest VRAM at the depth buffer's address in Z16 (16-bit, PSP depth = z * 65535, matching the
   viewport's depth mapping used by the vertex shader). Cost: one read-back per frame; keep it off when no game
   reads the depth (`PURE_NO_DEPTH_READBACK=1` as the off switch, on by default only for this profile if the
   framework has a per-game hook; otherwise document the switch).
2. Evidence: `PSPRECOMP_TRACE_VRAM_READS` or a probe shows non-zero depth values at the read addresses when a
   building covers the sun, and zero (far) when the sky is open; the flare intensity differs between the two.
3. Patch 0008 via `tools/patches.sh export`, README rows, a section in docs/ge-effects.md.

## Acceptance criteria
- [ ] A race frame where the sun is behind geometry (find one on Vineta K by captures every 60 frames with the
      follower) shows a dimmer or absent flare with the write-back on than off; the open-sky frame 6016 keeps its flare
      and stays within 0.08 of ref/vineta_k_start.png at tol 32 (it is 0.067 now).
- [ ] Frame time: the race's average fps with the write-back on is within 10% of off (`PURE_FRAME_LOG` timing).

## Verify
`tools/patches.sh check && python3 tools/imgdiff.py out/019/hud.png ref/vineta_k_start.png --tol 32 --max-frac 0.08`

## May touch
- vendor/portablekit/host/gpu/ and host/hle/hle_media.cpp via `tools/patches.sh export 0008-<slug>` only, patches/,
  docs/ge-effects.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/, config/, patches/0001-0007

## Estimated turns
60

## Escalate when
The game's read addresses cannot be tied to a SIGNAL (report the trace), or the write-back costs more than 10% of
frame time with the region limited (report numbers).

## Result
Status: DONE

Changed:
- `patches/0008-depth-write-back-at-signal.patch` (new, from `tools/patches.sh export`): `host/gpu/vulkan_renderer.cpp`,
  `host/gpu/vulkan_renderer.hpp`, `host/hle/hle_media.cpp`
- `patches/README.md` (row 0008), `README.md` (rows `PURE_NO_DEPTH_READBACK`, `PURE_TRACE_DEPTH_READBACK`)
- `docs/ge-effects.md`: new section "The depth write-back for the lens flare (patch 0008, task 019)", a pointer to it
  from task 008's lens-flare section, and the task 019 commands under Reproducing

SIGNAL and read addresses (throwaway trace of every guest load from the depth buffer's bytes in any VRAM mirror, with
values, plus a line per GE signal; not committed, it lives in `src/guest_memory.cpp`):
- SIGNAL `0x0E020200` + END, behaviour 2, signal id 0x0200, on the list's callback (signal function 0x088ECCAC). One
  per race frame from frame 5707, none in the frontend; the only other interrupts are FINISH (id 0). All 874 loads of
  the depth bytes to frame 6020 come right after a 0x0200 signal, before the next signal.
- From frame 5966, every frame, 16 halfword loads through the 0x04600000 mirror: 0x04722902 + 0x800 i + 4 j on the
  grid = depth rows 74/76/78/80, columns 129/131/133/135 at 0x04110000 stride 512 (the 4x4 every-other-pixel block
  around the sun; it moves with the sun, (323, 86) by frame 7466). From the HUD fade-in (6010/6011) one more halfword
  first, at 0x047321E0 = row 136 column 240 (screen centre). Task 008's `[vram]` blocks 0x0412/0x0413 were these, the
  trace masks addresses to 2 MB.
- The region cannot be predicted from the GE side (the sun's position is the game's), and the cost is the GPU wait,
  not the size, so the whole 480x272 buffer is written.

Write-back: before the signal sink queues a SIGNAL interrupt (behaviour 1-3, with a signal function), `hle_media.cpp`
calls the new `VulkanRenderer::write_back_depth(color, depth address, depth stride, memory, why)` with the GE's
current target registers. It ends the pass, copies the depth aspect of that target's depth image (D32_SFLOAT_S8_UINT,
960x544) into a mapped host-cached buffer, submits the frame so far and waits (the `read_back_framebuffer` sequence),
then stores z = round(depth x 65535) (the viewport's z/65535 mapping) from each PSP pixel's centre texel as 16-bit
little-endian values, 480 per row, rows of the depth stride from `0x04000000 | (zbp & 0x1FFFF0)`. Screen-wide depth
buffers only (stride >= 480). Depth images get TRANSFER_SRC usage. On by default (the framework has no per-game hook;
a `GameProfile` field would need the profile in `src/`); `PURE_NO_DEPTH_READBACK=1` is the off switch, documented in
README.md; `PURE_TRACE_DEPTH_READBACK=1` logs each write-back. The bloom's reuse of the bytes is unaffected: the
0x04110000/0x04132000 targets take their guest-word snapshots at their first draw of the frame, after the SIGNAL.

Depth values the game reads:

| Read | PPSSPP frame 7155 | Ours, off | Ours, on |
|---|---|---|---|
| sun block on the grid (frame 6010) | 23 x16 | 0 x16 | 24 x16 |
| centre (240,136) | 1168 | 0 | 1168 |
| sun behind the left pillar (frame 6690, driven) | | 0 x16 | 3187-3224 |
| write-back z range | 23-13344 | | 23-13444 |

Flare (driven run `out/019/drive.txt`: race route + Cross held from 6100, no steering; same player path in both
runs, ship dist 1464.906 vs 1464.895 at frame 6690), frames 6250-7499, first-element alpha of the flare strip:

| Sun samples covered | Frames (on) | Drawn | First alpha mean (range) |
|---|---|---|---|
| 0 | 510 | 510 | 128.6 (109-157) |
| 1-3 | 14 | 14 | 117.7 (98-134) |
| 4-7 | 34 | 33 | 96.3 (68-118) |
| 8-11 | 22 | 22 | 69.0 (38-79) |
| 12-15 | 28 | 24 | 30.0 (9-40) |
| 16 | 642 | 6 (alpha 0) | 0 |
| off, all frames | 1250 (all read 0) | 1250 | 147.9 (109-182) |

Frame 6690 (sun behind the pillar): no flare with the write-back, glow and rings without it; mean luma in PSP
(100,40 90x100) 105.2 on vs 176.5 off. Frame 6016 (open sky): flare drawn in both (first alpha 121), same region
225.7 on vs 225.8 off (PPSSPP 221.1); `out/019/hud.png` 0.0676 against the reference at tol 32 (0.0676 off; 0.0740
in one other on run with a different AI field).

Frame time (drive script to 7500, `PURE_PERF=log`, 25 one-second lines between `[pure] frame 6000` and `7500`, plus
1500 trace lines):

| | Off | On |
|---|---|---|
| fps (game) | 59.93 (59.92) | 59.94 (59.93) |
| frame avg / max ms | 16.70 / 18.74 | 16.70 / 18.72 |
| guest / render / pacing wait ms | 2.51 / 1.31 / 12.86 | 2.50 / 1.52 / 12.67 |
| write-back total (GPU wait) ms | | mean 1.07 (0.90), median 0.95 (0.77), max 15.1 (14.9) |

fps on is within 0.1% of off; the write-back is about 1.07 ms of the 16.7 ms frame (6.4%), under the 10% escalation
line.

Verify output (`tools/patches.sh check && python3 tools/imgdiff.py out/019/hud.png ref/vineta_k_start.png --tol 32
--max-frac 0.08`, out/019/hud.png from the committed series, frame 6016 of `--frames 6045`):
```
ok: 8 patch(es) reproduce vendor/portablekit at 8b0c3fe
PASS fraction 0.067601 (8826/130560 pixels differ by more than 32, limit 0.08) at 480x272 (resized from 960x544 and 480x272)
```

Open questions:
- The write-back is on for every game on the framework. A per-game switch (a `GameProfile` field set by our profile
  in `src/`) would keep the GPU wait off games whose SIGNAL handlers never read depth; it needs a brief that may touch
  `src/`.
- Only SIGNAL interrupts trigger it. A game that reads depth after `sceGeDrawSync`/`sceGeListSync` would need the same
  call there (the brief's alternative); Wipeout Pure does not.
- The loads use the 0x04600000 depth mirror. The framework maps every mirror onto the same bytes and the write-back
  stores depth linearly, which gives the dump's values (sky 23-24, centre 1168); any reordering the real PSP applies
  in that mirror is not modelled.
- What the centre read (240,136) is for was not identified.
- Our sky samples read 22-24 where PPSSPP has 23 (rounding of the float depth); the game treats both as sky.
- The read-address evidence came from a throwaway edit of `src/guest_memory.cpp` (outside May touch, reverted); a
  committed per-address VRAM read trace would need a framework change there.

## Review
(Fable fills)

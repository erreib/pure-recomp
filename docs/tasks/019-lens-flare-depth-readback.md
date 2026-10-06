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
(worker fills)

## Review
(Fable fills)

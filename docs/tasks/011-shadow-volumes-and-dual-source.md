# 011: Ship shadows (stencil shadow volumes) and exact REPLACE under source-alpha blends

Milestone: M3 polish | Branch: task/011-shadow-volumes-and-dual-source | Status: OPEN

## Goal
Two leftovers from patch 0004 (docs/tasks/009-stencil-as-alpha.md, Open questions): (a) the ships' shadows are
missing: draws 339-356 of the race frame are depth-fail stencil volumes (ops zfail INCR/DECR, colour masked
0xFFFFFF) followed by draw 357, a full-screen darkening with stencil test GREATER ref 4 and ops REPLACE; the renderer
emulates neither, so the darkening is applied everywhere its geometry covers (or nowhere); (b) REPLACE under a colour
blend that reads source alpha (track strips 93-102 ref 0x80, engine glow 820/828 ref 0xFF with add(SA, FIXB)) is
approximated with constant-alpha blending. Make both exact.

## Read first
- CLAUDE.md, docs/ge-effects.md (the stencil section and the frame's stencil sequence), patches/0004-*.patch,
  vendor/portablekit/host/gpu/vulkan_renderer.cpp (depth/stencil attachment creation, pipeline keys, the push
  constants added by 0004), host/gpu/shaders/ge.frag, ref/vineta_k_start.ppdmp via tools/ppsspp/ppdmp.py (`draws --vt`)
- PPSSPP's approach (read-only, copy nothing): it keeps a real stencil attachment and copies it into alpha when a
  framebuffer is sampled; dual-source blending for alpha replace.

## Deliverable
1. A real Vulkan stencil attachment per render target mirroring the PSP's alpha-stencil: stencil ops INCR/DECR/
   INVERT/KEEP/ZERO/REPLACE on sfail/zfail/zpass, stencil test funcs, the stencil write mask; the target's alpha
   (what patch 0004 writes) stays the source of truth for sampling, so after any draw that changes the stencil in a
   way alpha cannot express, keep both consistent (the simplest consistent rule the design allows; document it).
2. Dual-source blending (`dualSrcBlend` feature; fall back to the 0004 approximation when unavailable) so REPLACE
   under source-alpha blends writes the exact ref.
3. Patch 0006 via `tools/patches.sh export`, README row, `PURE_NO_STENCIL_BUFFER=1` to disable the new attachment.

## Acceptance criteria
- [ ] The race frame 6016 shows a dark shadow under each ship on the grid (region check against
      ref/vineta_k_start.png: the shadow regions' brightness within 20 of the reference's).
- [ ] Frame 6016 vs ref at tol 32 is at most 0.30 (it is 0.303 after patch 0005).
- [ ] Frontend title capture unchanged (0.05 at tol 24); `tools/patches.sh check` passes with 6 patches.

## Verify
`tools/patches.sh check && python3 tools/imgdiff.py out/011/hud.png ref/vineta_k_start.png --tol 32 --max-frac 0.30 && python3 tools/imgdiff.py out/011/title.png ref/title.png --tol 24 --max-frac 0.05`

## May touch
- vendor/portablekit/host/gpu/ via `tools/patches.sh export 0006-<slug>` only, patches/, docs/ge-effects.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/, config/, patches/0001-0005

## Estimated turns
70

## Escalate when
MoltenVK lacks a usable depth+stencil format for the target or `dualSrcBlend`; report the device limits and stop.

## Result
(worker fills)

## Review
(Fable fills)

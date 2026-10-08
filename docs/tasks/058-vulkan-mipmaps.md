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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

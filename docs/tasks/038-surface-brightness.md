# 038: Surfaces 1.5 times too bright on Sebenco Climb and Sinucit (fidelity difference 3)

Milestone: M8 | Branch: task/038-surface-brightness | Status: OPEN

## Goal
Sebenco Climb's long concrete wall and Sinucit's overhang are about 1.5 times brighter than on the PSP: wall pixels
(113, 125, 126) in the port against (70, 81, 83) in PPSSPP, on draws that are unlit, fogged, vertex-coloured CLUT4
textures. Both backends draw the same pixels, turning the port's fog or lighting off changes nothing, and the mip
levels have the same mean colour, so the cause is upstream of the backends: the framework's GE state or vertex
decode, or a GE rule neither backend applies. This task finds it by bisecting one draw against PPSSPP's GE dump of
the same frame, and fixes it where it is (a vendor patch to the GE state or the decode, or a backend rule), or
reports the rule with evidence if the fix is larger than a task.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 3: the frame, the draws 197, 198 and 201 of the task's dump, the pixel
  values, what was ruled out), docs/ppsspp.md and ref/README.md (burst K's command for the Sebenco Climb frame with
  `--gedump`, how a `.ppdmp` is read: `tools/ppsspp/ppdmp.py`), docs/ge-backend.md 7 (ge_replay `--cut N --out` for
  a port draw's picture), docs/metal-backend.md ("How a draw is drawn": colour, texture function, vertex colour)
- vendor/portablekit/host/gpu/ge_state.cpp (vertex decode: colour formats 5650/5551/4444/8888 and the colour's
  unpacking; the material colour; TEXFUNC's colour-double bit (RGB x2) and TCC; the fog colour; the ambient),
  host/gpu/shaders/ge.frag (what the Vulkan fragment shader multiplies), src/gpu/metal_shaders.h (the same in MSL)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: the texture function with colour doubling, the vertex
  colour formats, fog, the material/ambient rules for unlit draws)
- tools/ppsspp/ppdmp.py (the dump reader: a draw's state and its vertex data), tools/imgdiff.py

## Deliverable
1. The bisection: PPSSPP's GE dump of the Sebenco Climb first race frame (make it with burst K's command and
   `--gedump`; the audit's was lost with its worktree) and a port recording of the same frame (`PURE_GE_RECORD` on
   the route, one frame). For the wall's draws, side by side: the GE state PPSSPP's dump holds (TEXFUNC bits, vertex
   type's colour format, the vertex colours decoded, the material colour, fog, ambient) and the port's `DrawCall`
   (`gerec_dump.py`), field by field; the first field that differs, or, if none differs, the first rule the shader
   applies that PPSSPP's documentation says differently. Write the table in docs/fidelity.md under difference 3.
2. The fix, where it is: a vendor patch (0016 `tools/patches.sh export 0016-<cause>`) if the state or the decode is
   wrong, or a backend change in `src/gpu/` if the Metal shader applies a rule wrongly (then say what the Vulkan
   path does, which has the same pixels). The wall's pixels within tol 16 of PPSSPP's afterwards.
3. The check across the game: `tools/frame_regress.sh` (headless Metal, 18 scenes) with the fractions before and
   after, and the Sebenco Climb and Sinucit first race frames against their references (the audit's reference table
   has them; add the port route for Sebenco Climb to `config/pad_scripts/` if it needs one, or capture through the
   sweep's shots at the matching flip, and say how).
4. docs/fidelity.md (difference 3's row: the cause, the result), patches/README.md if a patch, docs/metal-backend.md if
   a backend rule.

## Acceptance criteria
- [ ] The cause is named with the field or rule and the evidence table.
- [ ] After the fix, the Sebenco Climb frame's fraction against PPSSPP drops from about 0.32 to under 0.10, Sinucit's
      from 0.12 to under 0.06, and no suite scene rises by more than 0.003.
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` reported (it may change if the fix is in the state).

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh`

## May touch
- vendor/portablekit/host/gpu/ge_state.cpp, texture_decode.cpp (via `tools/patches.sh export 0016-<cause>`), patches/,
  src/gpu/, config/pad_scripts/ (a Sebenco Climb capture route), tools/ppsspp/routes/ (a dump route), docs/fidelity.md
  (difference 3), docs/metal-backend.md, patches/README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/hle/, host/shell/, src/host/, src/profile/, src/tools/, tools/frame_regress.sh,
  ref/*.png (new references are allowed only through the documented capture commands, listed in ref/README.md)

## Estimated turns
60

## Escalate when
The field-by-field comparison shows no difference and no documented rule explains the factor (report the table and
the three candidate rules you considered), or the fix would change the vertex decode for every draw (report the
scope and the suite's deltas with the change applied in a throwaway build).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

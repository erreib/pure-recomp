# 052: The patch series by topic, and the upstream list (the organisation pass, 4 of 5)

Milestone: M9 organisation | Branch: task/052-patch-series-by-topic | Status: OPEN

## Goal
The vendor patch series grew one task at a time: 20 patches, with host/gpu/vulkan_renderer.cpp touched by 11 of
them, hle_media.cpp by 5, PortableKit.cmake by 5, ge_state.{hpp,cpp} and ge_record_format.hpp by 4 each. Every
later patch that touches a file another one touched is a conflict waiting for the next change and a harder read for
anyone upstreaming. This task regroups the series by topic so that each framework concern is one patch, reproduces
the identical vendor tree, and writes the upstream list.

## Read first
- CLAUDE.md (never commit vendor/; patches only through tools/patches.sh), patches/README.md (every row: what, kind,
  why, upstream candidate or not), tools/patches.sh (export, check, how the series is applied in order),
  tools/vendor_setup.sh, docs/vendor-map.md, docs/decisions.md D-001
- The patches themselves, patches/0001 to 0021, and `git -C vendor/portablekit log --oneline -1` (the pin 8b0c3fe)

## Deliverable
1. The regrouped series, numbered afresh from 0001, one patch per topic, in an order that applies cleanly; a
   proposal (which old patches fold into which new one, and why) written first under the Result and then carried
   out. The shape, to be checked against the diffs rather than taken as given:
   - build and CMake (0001's quoting fix, the embedding and option changes of 0009/0010/0015/0020 that are build
     plumbing);
   - the GE backend and shell seams (0009, 0010, 0012);
   - the Vulkan renderer's correctness fixes (0003 to 0008: framebuffer lookup, stencil as alpha, the alpha test,
     shadow volumes and dual source, the descriptor pool, the depth write-back at SIGNAL);
   - the GE state extensions and the record format (0004's state part if separable, 0013, 0014, 0017);
   - the kernel and HLE timing (0002 the movie ring, 0011 host waits);
   - the save data (0015 the list, 0019 the no-key mode);
   - the audio (0018 the reverb);
   - the VFPU rounding (0020, 0021).
   Keep a patch separate when folding it would mix an upstream candidate with something that is ours only (the
   test modes, the profile seams), so that the upstream list stays honest.
2. The identity proof: `tools/patches.sh check` reports the new count and reproduces vendor/portablekit at 8b0c3fe,
   and the tree is byte-identical to the one the old series gave: before regrouping, record `git -C vendor/portablekit
   diff` of the old series (or a tar hash of the host/, include/, tools/, cmake/ trees); after, the same hash. Then
   `tools/build.sh profile` and `tools/frame_regress.sh` 18/18 at the same values (nothing can change if the tree is
   identical; the suite is the belt).
3. patches/README.md rewritten for the new series: a row per patch with the old numbers it absorbed, and a new
   `docs/upstream.md`: for each new patch, upstream candidate or ours-only, what an upstream PR would carry, and
   what it depends on; the tasks' docs and briefs that cite old patch numbers get a one-line mapping table at the top
   of patches/README.md (do not rewrite the task files).
4. tools/patches.sh unchanged unless the regrouping needs a feature it lacks (then the smallest change, said in the
   Result).

## Acceptance criteria
- [ ] `tools/patches.sh check` passes; the vendor tree's hash before and after regrouping is identical.
- [ ] `tools/frame_regress.sh` 18/18 at the same values.
- [ ] patches/README.md and docs/upstream.md written; no file under vendor/ committed.

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh`

## May touch
- patches/ (the series and README), docs/upstream.md (new), docs/vendor-map.md (the patch list if it has one),
  tools/patches.sh (only if needed)

## Must not touch
- vendor/ (never committed; your worktree's clone is yours to regenerate), src/, config/, docs/tasks/, other tools

## Estimated turns
40

## Escalate when
Two patches cannot be folded without changing hunks in a way that alters the tree (report the pair and the hunk),
or the identity hash differs after regrouping (report the file: stop, do not "fix" it).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

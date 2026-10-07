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
Status: IN PROGRESS (the folding proposal, written and committed before the series changes; the outcome follows it)

### Proposal (written before the regrouping)
Nine patches for the twenty, in this order. "Pieces" are an old patch's per-file sections, split at file boundaries
only: no hunk is edited, so every byte of the old series lands in exactly one new patch.

| New patch | Topic | Old pieces, in apply order | Upstream |
|---|---|---|---|
| 0001-cmake-embed-nids-verbatim | build | 0001 | candidate |
| 0002-ge-state-commands | GE state: the commands it ignored | ge_state.{hpp,cpp} of 0004, 0013, 0014, 0017 | candidate |
| 0003-vulkan-renderer-fixes | the Vulkan renderer | 0003; 0004 without ge_state (ge.frag, vulkan_renderer.cpp); 0005; 0006; 0007; 0008; vulkan_renderer.cpp of 0013, 0014, 0017 (comments only) | candidate |
| 0004-ge-backend-and-shell-seams | the GE backend and shell seams, the record format | 0009; 0010; 0012; ge_record_format.hpp of 0013, 0014, 0017; record_backend.cpp of 0017 | candidate |
| 0005-kernel-host-waits-and-pacing | kernel clock | 0011 | candidate (needs 0004) |
| 0006-mpeg-ring-not-empty-while-aus-pending | HLE MPEG | 0002 | candidate |
| 0007-savedata-list-and-no-key-mode | save data | 0015; 0019 | candidate (needs 0004) |
| 0008-sas-reverb | audio | 0018 | candidate |
| 0009-vfpu-rounding | VFPU rounding | 0020; 0021 | the rules are candidates, the test mode is ours |

Where this departs from the brief's shape, and why (from the diffs):
1. 0004's state part separates cleanly (it is the ge_state.{hpp,cpp} sections alone), but it cannot move after the
   seams to join 0013/0014/0017: 0009's record format writes `DrawCall::stencil` and the two write masks, and
   0004's own renderer part reads them, so the stencil state has to come before both. 0013/0014/0017's record-format
   hunks cannot come before the seams either (0009 creates ge_record_format.hpp). So the topic splits by file: every
   ge_state hunk of the four is one patch, placed before the renderer; the record format's three later field groups
   (and 0017's mip-level texels in record_backend.cpp) fold into the seam patch that creates the file, which then
   holds the format in its final form; the three comment-only vulkan_renderer.cpp hunks of 0013/0014/0017 ("this
   renderer does not draw X") fold into the renderer patch (0013's and 0017's sit beside lines 0005 wrote, so they
   cannot come earlier).
2. Build: none of the CMake changes of 0009/0010/0015/0020 is plumbing on its own. 0009, 0010 and 0015 add their own
   new sources to the source lists (their topic does not link without them), and 0020's `-ffp-contract=off` for
   the generated units is half of the VFPU rule (D-013: without it clang fuses across translated instructions).
   Each stays with its topic, and the build patch is 0001 alone. PortableKit.cmake is then touched by four patches,
   in four places that do not share context lines.
3. 0002 and 0011 stay apart: no shared file or concern (the MPEG ring's free count; the kernel clock's host waits
   and pacing), and 0011 needs the shell seam (`set_paced` is called in `ensure_shell_and_backend`) while 0002
   needs nothing. Folded, the MPEG fix would carry the seam into its upstream PR.
4. Ours-only parts: the VFPU test mode (`vfpu_dot_mode() == 1`, set by our profile) sits inside the same functions
   as the PSP rule in both 0020 and 0021; separating it would mean writing hunks that never existed. 0020 and 0021
   fold into one patch marked as before (the rules upstream, the mode ours). No other patch holds an ours-only
   part, so no fold mixes the two kinds.

Ordering: every new patch applies with `git apply` after the ones before it, and each reads only state that an
earlier one (or the pin) defines. Dry run in a scratch clone of the pin: the nine apply cleanly and leave tree
fcbef3828d8143b437ba91b541340f129f175a38, the identity of the old series' tree (below). Files touched by more than
one patch: 20 of 50 before, 10 after; vulkan_renderer.cpp by 11 patches before, by 2 after (the renderer patch and
the seam patch).

Carrying it out: the old patches are renamed 10NN first (so they sort after the new ones), then one new patch at
a time is added and the old patches it absorbs are removed (or cut down to their remaining file sections), with
`tools/patches.sh check` after each step and a commit per step.

Identity of the vendor tree as the old series leaves it (out/052/before/, recorded before any change; a temporary
index over the whole working tree, so the vendor checkout's own index is untouched):
- git tree of the whole vendor tree (every file, content and executable bit): fcbef3828d8143b437ba91b541340f129f175a38
- sha256 of the manifest (mode, sha256, path of each of the 344 files outside .git): 886cbf59285e2642011e9ce01e78f844b93ea7d625cca5808d59c44e79ae16ff
- sha256 of the full diff against the pin (50 files, binary, full index): a533d876ac1a9e64f1a3e961ecb56b66d33dae1b409831a7406402e308159cdc
- frame regression before (headless, metal): 18/18, out/052/regress_before/summary.txt

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

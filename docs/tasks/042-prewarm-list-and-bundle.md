# 042: The pre-warm list covers the campaign, and the app bundle carries it

Milestone: M8 | Branch: task/042-prewarm-list-and-bundle | Status: OPEN

## Goal
Two follow-ups of tasks 033, 040 and 041. `config/metal_pipelines.txt` lists only the pipelines of the Vineta K
Single Race cell, and since task 040 it also lacks the 16-bit and colour-test keys: task 041 counted nine render
pipelines every 30-fps run still makes by a draw (six at the race load, two or three in the race), 243 ms on a cold
shader cache, the one hitch a player could meet. And the app bundle does not carry the list at all, so the installed
app makes every pipeline on first use. This task refreshes the list over the campaign, ships it in the bundle, and
rebuilds the bundle from the current tree (the one in out/release-macos predates tasks 036 to 041).

## Read first
- CLAUDE.md, docs/metal-backend.md ("The pre-warm list": the refresh recipe; "Frame times"), docs/tasks/033 (Result),
  docs/tasks/041 (Result: the nine pipelines, the runs that made them), docs/release.md and docs/tasks/029 (the
  packer, `RELEASE_RESOURCES` in packaging/release.env: folders of the build's bin directory shipped into
  `Contents/Resources`), tools/bundle.sh (the `--check` runs), docs/tasks/034 (Result: scratch data directories,
  silent runs; the follow-up that `--check`'s runs are not silenced)
- src/gpu/metal_backend.mm near "metal_pipelines.txt in an app's Resources" (read only: where the backend looks and
  how it parses a list, including the `color_test` and `sixteen` fields task 040 added)

## Deliverable
1. `config/metal_pipelines.txt` refreshed as the union of `PURE_METAL_PIPELINES_OUT` files from headless sweep cells
   that cover the campaign: Single Race on every circuit of one class (`--unlock-all`, `--no-damage`), Time Trial,
   Free Play and Zone on at least one track each, and a Tournament race; keep the file's header comment, updated with
   what the list now covers. Acceptance: a second run of each of Single Race Vineta K, Free Play, Time Trial and Zone
   ends with `0 not in the list` on its `[metal] pipelines:` exit line.
2. The bundle ships the list: `tools/bundle.sh` (or packaging/release.env's `RELEASE_RESOURCES`, whichever the packer
   supports without a vendor change) puts `metal_pipelines.txt` in `Contents/Resources`, where the backend looks
   first, before the app is signed; `tools/bundle.sh --check` gains a check that the packed app's run prints a
   `[metal] pre-warm:` line naming the Resources copy.
3. `tools/bundle.sh --check` runs silent and on a scratch data directory like the other tools (task 034's follow-up),
   if the packed app honours `PURE_DATA_DIR` and the mute setting; otherwise say why not.
4. The bundle rebuilt from this branch: `tools/bundle.sh` (a release build, then the packer) and `tools/bundle.sh
   --check out/042` passing, the app left at `out/release-macos/stage/Wipeout Pure.app`. Do not touch anything under
   /Applications or the player's data directory.
5. docs/metal-backend.md ("The pre-warm list": what the list covers now), docs/release.md (the Resources file), the
   README's row for `PURE_METAL_PIPELINES` if it changes.

## Acceptance criteria
- [ ] The four cells above report `0 not in the list`; `tools/frame_regress.sh --only race_hud` unchanged.
- [ ] `tools/bundle.sh --check out/042` passes, including the new pre-warm check.

## Verify
`tools/bundle.sh && tools/bundle.sh --check out/042 && tools/frame_regress.sh --only race_hud`

## May touch
- config/metal_pipelines.txt, tools/bundle.sh, packaging/, docs/metal-backend.md, docs/release.md, README.md

## Must not touch
- src/, vendor/, patches/, include/psprecomp/, tools/frame_regress.sh, tools/campaign_sweep.py, config/pad_scripts/, ref/

## Estimated turns
30

## Escalate when
The packer cannot ship a file into Contents/Resources without a change under vendor/ (report what it offers; a one-line
vendor patch is not this task's), or a cell's second run still makes pipelines by a draw after the refresh (report the
keys: they may depend on something the sweep does not reach).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

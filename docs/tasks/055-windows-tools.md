# 055: Windows tools

Milestone: W2 (docs/windows.md step 2) | Branch: task/055-windows-tools | Status: OPEN

## Goal
Every check the harness has runs on Windows, so steps 3 and 4 can be verified here the way the Mac verified M1 to
M9: the Python tools, the bash tools under Git Bash, the PPSSPP driver against the Windows PPSSPP, and the
scorecard with its machine-bound references retaken. Task 054 proved the game and the frame suite; this task
proves the rest of tools/.

## Read first
- docs/windows.md (step 2, and "What does not" for which references transfer)
- docs/tasks/054-windows-build-boot.md (the Result: what is already proven, the open questions — the pipe
  runner's block-buffered stdout is yours to confirm harmless or fix for campaign_sweep's live steering)
- docs/verification.md (the table of checks), docs/scorecard.md, docs/ppsspp.md
- tools/purelib/port.py (the Windows runner from task 054), tools/purelib/ppsspp.py, tools/ppsspp/
- tools/worktree_init.sh, tools/vendor_setup.sh (the macOS assumptions to replace)
- docs/setup.md ("Windows setup", to extend)

## Deliverable
- PPSSPP installed for Windows (match the Mac's 1.20.x if available; record version and install path in
  docs/setup.md) and `tools/ppsspp/ppsspp_ctl.py` driving it: launch, debugger connect, memory read, replay.
- The references docs/windows.md says do not transfer retaken on this machine: `ref/scorecard/` and `ref/vfpu/`
  (`tools/scorecard.py --refresh-references`); the picture references under `ref/*.png` are already here and stay.
- Each check of docs/verification.md's table runs on Windows or is recorded as macOS-only with a one-line reason
  in docs/setup.md's Windows section (expected macOS-only: tools/gerec/metal_check.sh, hud_check's Metal shell
  path, bundle.sh). `tools/imgdiff.py --selftest`, `tools/controls_check.py`, `tools/docs_check.py`,
  `tools/verify_task.sh 054`, `tools/refactor_check.sh`, `tools/campaign_sweep.py` (one cell at least),
  `tools/save_roundtrip.sh`, `tools/wavstats.py` on a `PURE_AUDIO_WAV` capture, and `tools/scorecard.py --quick`
  all demonstrated.
- `tools/worktree_init.sh` working on Windows: hard links (or copies where a link cannot work) in place of
  symlinks for disc/, generated/ and disc.iso, no APFS `cp -c`, the shared ccache counted as on macOS — so
  worker tasks can run in worktrees here from step 3 on.
- docs/setup.md's Windows section extended with what this task installs and learns.

## Acceptance criteria
- [ ] `tools/scorecard.py --quick` runs to the end and prints the same grades as docs/scorecard.md's categories
      (trajectories may differ as fidelity difference 13 allows; say so in the Result if it does)
- [ ] `tools/ppsspp/ppsspp_ctl.py` completes one scripted PPSSPP run with a memory read
- [ ] `ref/scorecard/` and `ref/vfpu/` retaken on this machine; `tools/vfpu_probe.py` agrees with the port
- [ ] a fresh worktree passes `tools/worktree_init.sh` and builds `PureNative.exe` from the shared cache
- [ ] one campaign_sweep cell (single_race on Vineta K) reaches its end screen headless
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/scorecard.py --quick`

## May touch
- tools/ (not tools/bundle.sh), docs/setup.md, docs/ppsspp.md, docs/scorecard.md, docs/verification.md,
  docs/windows.md, ref/ (git-ignored; the retaken references)

## Must not touch
- vendor/, include/psprecomp/, src/, CMakeLists.txt, CMakePresets.json, config/, patches/, generated/

## Estimated turns
40

## Escalate when
The Windows PPSSPP's debugger protocol differs from what tools/purelib/ppsspp.py expects (docs/vendor-map.md rule:
report, do not adapt blind); a fix would need a vendor patch or a src/ change; the pipe runner's buffering breaks
campaign_sweep's steering and a tools-only fix does not restore it; any build exceeds 5 minutes.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

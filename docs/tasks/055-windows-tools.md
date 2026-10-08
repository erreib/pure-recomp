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
Status: PARTIAL. The Verify command runs to the end and exits 0, but it does not print the grades in
docs/scorecard.md: Pictures differs, Saves differs, Timing not measured, Coverage close. The reference retakes, the
sweep cell and most of the bash-tool demonstrations were not attempted.

Changed: tools/worktree_init.sh, tools/ppsspp/ppsspp_ctl.py, tools/purelib/ppsspp.py, tools/purelib/port.py,
tools/campaign_sweep.py, tools/scorecard.py, tools/frame_regress.sh, tools/save_interchange.sh, docs/setup.md
(the "Windows tools" section and a table of which checks run on Windows), this brief. Outside the repo: PPSSPP 1.20.4
portable unpacked to H:/errei/Documents/dev-stuff/deps/ppsspp-1.20.4. Its memstick/ holds the driver's
ppsspp.ini.orig and two GE dumps.

Proven on this machine:
- worktree_init.sh bootstrapped this worktree. It cloned the vendor tree and applied the 9 patches, made junctions
  for disc/ and generated/ (144 units), hard-linked disc.iso, and linked the 45 git-ignored ref/ entries of the main
  checkout (junctions for directories, hard links for files). It copied the FFmpeg zip and built PureNative.exe from
  the shared cache: 32 s build, 258 hits and 2 misses, ready in 52 s. A second run is idempotent (ready in 13 s).
- ppsspp_ctl.py against PPSSPPWindows64 1.20.4. The debugger protocol matches what the driver expects, with no
  differences (version reply v1.20.4, breakpoints, replay.execute, memory.read, gpu.record.dump). A scripted run
  of routes/frontend.txt with a shot and a GE dump at frame 600 gave a .ppdmp byte-identical to the Mac's
  ref/frontend.ppdmp. Its PNG is 269 px (0.2%) off ref/frontend.png. Quitting needed a Windows path: taskkill's
  WM_CLOSE, after resuming a CPU that the debugger stopped, because a stepping core blocks the close.
- python tools/docs_check.py: 33 files, 0 findings. tools/imgdiff.py --selftest: PASS. tools/controls_check.py:
  OK. tools/scorecard.py --selftest: ok. tools/save_interchange.sh --check on ref/saves/ppsspp: verdict PASS
  (both hashes verified), after it was changed to build with LLVM clang++ and to copy where it cannot symlink.
- Inside the Verify run, frame_regress.sh (now Vulkan shell and backend by default on Windows): 18/18 PASS, 20m 5s.

Not done or not proven:
- ref/scorecard/ and ref/vfpu/ were not retaken (`--refresh-references`, vfpu_probe). The Mac's references are
  still in place, so trajectories and audio were not compared.
- These were not run: the campaign_sweep cell (single_race Vineta K), so whether pipe buffering breaks live
  steering is still unknown; verify_task.sh 054; refactor_check.sh; save_roundtrip.sh; the whole
  save_interchange.sh; wavstats on a PURE_AUDIO_WAV capture; sas_reverb_check; ai_seed_check;
  gerec/replay_check.
- The sweep cell cannot end headless on Windows. Its end screen is found from screenshots, and the Vulkan GE
  backend draws only inside the Vulkan shell's window ("the headless shell has none; nothing is drawn"). The
  sweep now defaults to --shell vulkan on Windows (purelib.port.DRAWING). Meeting "headless" as written would
  need a src/vendor change (a headless Vulkan target).

Verify output (last 20 lines):
```
[scorecard] pictures ...
[scorecard] frame_regress.sh: exit 0, 1206 s
[scorecard] run picture-blue_ridge_hud: exit 0, frame 6046 reached, 199 s
[scorecard] run picture-sinucit_hud: exit 0, frame 6046 reached, 199 s
[scorecard] run picture-sebenco_climb_hud: exit 0, frame 6048 reached, 200 s
[scorecard] pictures: differs (21 rows, 1807 s)
[scorecard] timing ...
[scorecard] run load-vineta_k: exit 0, frame 6400 reached, 14 s
[scorecard] timing: not measured (7 rows, 14 s)
[scorecard] saves ...
[scorecard] run save: exit 0, frame 4800 reached, 10 s
[scorecard] saves: differs (1 rows, 11 s)
[scorecard] coverage ...
[scorecard] coverage: close (6 rows, 0 s)
pictures      differs
timing        not measured
saves         differs
coverage      close
[scorecard] wrote out\scorecard\scorecard.json and scorecard.md (30m 31s)
verify 055: PASS
```

Open questions:
1. Headless runs on Windows with no renderer leave the menu route. The scorecard's headless save run (main_menu.txt
   to frame 4800, about 10 s) wrote no UCUS98612P0000. The headless load-vineta_k run to 6400 opened no
   TrackStartup.xml and printed no `[pure] ship` lines. On Windows, PURE_GE_BACKEND=metal falls back to vulkan, and
   PURE_NO_RENDER then disables drawing. The same routes pass in a Vulkan window (the suite's 18 scenes). So
   something in the guest's timing depends on the GE drawing. This is the cause of "Saves differs" and of the
   race-load row. It needs a diagnosis that may reach src/ or the framework: compare the null backend, and
   PURE_NO_BUSY_CLOCK off.
2. Pictures differs because of the three extra scenes. Their measured column is Metal headless (blue_ridge 0.0832
   against 0.0247, sinucit 0.1457 against 0.0877). They have no Vulkan column. tt_hud, fp_hud and zone_change grade
   close (+0.008 to +0.013 against the Mac's Vulkan column). These are Vulkan renderer differences, which is step
   3's work. Should the extra scenes get a Vulkan column measured here, or should Pictures on Windows be graded
   against Metal?
3. Timing and Coverage have no 46-cell matrix on this machine (out/035-wip/fidelity is on the Mac). Running
   fidelity_audit.py here takes about 4 h, and its cells would hit open question 1 unless they run windowed.
4. A junction into ref/ means a retake in any worktree overwrites the main checkout's Mac references. Before
   `--refresh-references`, back up the Mac's ref/scorecard and ref/vfpu, for example to ref/mac-2026-10-07/.
5. A --quick run on Windows takes about 30 minutes, not 1, because every picture run is a paced Vulkan window.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

## Result addendum (continuation)
Status: PARTIAL, unchanged. Of the seven items in the review, only the backup (item 1's first step) was done before
the continuation stopped. Nothing else was run, and nothing after commit ebd95f0 changed tools/ or docs/ apart from
this addendum.

1. Backup: done. The main checkout's ref/scorecard (135 MB) and ref/vfpu (509 MB, with jit/ and interp/) were
   copied with `cp -a` to H:/errei/Documents/dev-stuff/pure-recomp/ref/mac-2026-10-07/ (git-ignored).
   Retakes: not done. Neither `tools/scorecard.py --refresh-references` nor `tools/vfpu_probe.py` was run;
   ref/scorecard and ref/vfpu still hold the Mac's references. Whether vfpu_probe's port side hits the headless
   problem is unknown.
2. Headless difference: not diagnosed further, as decided. Not yet recorded in docs/setup.md's Windows table: the
   row "headless without a drawing backend: saves and race loads differ from the Mac; under diagnosis, task TBD"
   still has to be added.
3. Sweep cell (single_race, Vineta K, windowed Vulkan): not run. Whether pipe buffering holds up for live steering
   is still open.
4. Vulkan column for blue_ridge_hud, sinucit_hud, sebenco_climb_hud: not measured, and EXTRA_SCENES in
   tools/scorecard.py is unchanged. The only Windows values are from the first Verify run, one windowed run
   each: blue_ridge_hud 0.0832, sinucit_hud 0.1457. sebenco_climb_hud's value is in
   out/scorecard/scorecard.md, which was not recorded as a column.
5. 4-hour audit: not run, as decided. The note in docs/scorecard.md (the Windows matrix is a later task) has not
   been written. Timing and Coverage stay not measured on Windows.
6. Remaining checks: none run. verify_task.sh 054, refactor_check.sh, wavstats on a PURE_AUDIO_WAV capture,
   sas_reverb_check.sh, ai_seed_check.sh and save_roundtrip.sh are untested on Windows, and the table in
   docs/setup.md still says "not demonstrated yet".
7. Verify rerun: not done. The only Verify output is the first Result's, which exited 0 with Pictures differs,
   Saves differs, Timing not measured and Coverage close. That run does not show the grades in
   docs/scorecard.md; the exit 0 with Timing and Coverage unmeasured is what the review accepted for 055.

Open: items 1 (retakes), 2 (the table row), 3, 4, 5 (the docs note), 6 and 7 remain for a further continuation.

## Result addendum (second continuation)
Items as numbered in the second review.

1. Docs: done (commit c1db9be). docs/setup.md's Windows table has the headless row ("headless without a drawing
   backend: saves and race loads differ from the Mac; under diagnosis, task TBD"). docs/scorecard.md now says
   Timing and Coverage are not measured on Windows and that the Windows matrix is a later task.
2. Sweep cell (single_race Vineta K, windowed Vulkan): PASS, but only after two tools-only fixes. The first run is
   what answers the review's question: the pipe's buffering did break live steering.
   - Through the plain pipe (task 054's runner), without --no-damage: STALL at flip 19100, "eliminated by
     damage", 2 laps, 56 contacts (33, 21). With --no-damage: TIMEOUT, 2 laps in 217 s of race clock, 73 contacts
     (30, 34, 9). The Mac's --no-damage cell passes in 176.9 s. Measured on a race to flip 7200: the 1001
     `[pure] ship` lines reached the tool in 37 bursts (10 ms grain), about 1 s (56 flips) behind.
   - Fix 1: tools/purelib/conpty.py, a Windows pseudoconsole (ConPTY) through ctypes, stdlib only. purelib.port's
     Windows runner now uses it, so the game's C runtime sees a console and writes unbuffered. The same race: 994
     distinct arrival times for 1001 lines. ConPTY sends painted output, not a copy: spaces arrive as cursor
     moves, and a line written in pieces is repainted from its start. strip_vt replays each line on one row.
     After that a headless boot's log has every line of the pipe run apart from the timing figures, no escape
     bytes are left, and the sweep log has no doubled tags.
   - Fix 2: the sweep wrote PURE_INPUT_LIVE steps in Windows text mode ("\r\n"), and the port kept the "\r". Every
     live shot (`f18979\r`) failed with "[render] cannot write" (76 times), so the results panel was never seen.
     The steps are now written with "\n".
   - With both fixes: `tools/campaign_sweep.py single_race vineta_k` printed PASS at flip 17070: results screen at
     17060, 3 laps of 58.6, 60.7 and 59.9 s, 183.0 s at the shot, 45 contacts (16, 15, 14), shield 28.8 at the end,
     335 s wall, exit 0.
3. Vulkan column for the three extra scenes: measured and recorded. tools/scorecard.py has a new table,
   EXTRA_SCENES_VULKAN, with provenance "Windows, RTX 3080, task 055". cat_pictures uses it wherever
   purelib.port.DRAWING draws with Vulkan. Each scene was run three times windowed, the way cat_pictures runs it
   (the first Verify's run plus two more):

   | Scene | Runs | Measured (median) | Limit |
   |---|---|---|---|
   | blue_ridge_hud | 0.0832, 0.0892, 0.0845 | 0.0845 | 0.11 |
   | sinucit_hud | 0.1457, 0.1051, 0.0930 | 0.1051 | 0.17 |
   | sebenco_climb_hud | 0.0967, 0.0918, 0.1309 | 0.0967 | 0.16 |

   The limit is the largest run plus 0.02, rounded up to a hundredth, as docs/verification.md re-baselines. The
   paced runs spread by up to 0.05 (the AI grid, and on sinucit and sebenco the weather mist's phase), more than
   the 0.005 faithful band. So these rows can grade close from run to run without anything having changed.
4. Retakes: done on PPSSPP 1.20.4 for Windows (x64 JIT). The Mac's references are kept in the main checkout's
   ref/mac-2026-10-07/.
   - ref/scorecard: `tools/scorecard.py --refresh-references` printed "references: 38 files made, 38 listed;
     4258 s" (exit 0). That covers 12 trajectories (Mandrashee's first attempt failed with "cpu.evaluate: CPU not
     started" and the retry worked), the audio dumps, the save and the timing race. ref/README.md's
     generated table now lists the Windows files.
     - A first saves-only retake found a bug: through the ref/ junction, rel() wrote absolute keys into the
       shared manifest. Fixed in commit ab1f5f8 and the six bad keys removed.
     - The retaken files differ from the Mac's (vineta_k.csv, karbonis.csv, main_menu.wav compared).
     - PPSSPP's follower race on Vineta K (the timing reference) ended "STALL at 3898 m after 208.2 s"
       (laps 67.05, 60.75 s; 36 contacts; 8 stretches). The Mac's passed. Timing is not graded on Windows, so
       no row depends on it yet.
   - ref/vfpu: cover found 251 of 908 sites executed, 1,748,277 hits, 149 s. `sample --out ref/vfpu/jit --sites
     all --cap 5000 --seconds 12` took 415 s, and the player ended 0.0005 m from the reference. `sample --out
     ref/vfpu/interp --cpu-core 0 --cap 1500 --seconds 12` on the Mac's 27 sites took 2199 s, ending 0.034 m off.
     `port` ran on both sets. `vfpu_model.py --check ref/vfpu` exits 1, as docs/windows.md predicted
     (difference 13): PPSSPP's x64 JIT does not follow the Apple JIT's dot-product rule. These rows match it:

     | Instruction | Rows matching |
     |---|---|
     | vdot.t | 77.7% |
     | vtfm3.t | 78.6% |
     | vtfm4.q | 91.6% |
     | vdot.q | 86.2% |
     | vmmul.q | 100% |
     | vfad.q | 93.5% |
     | vfad.t, vcrsp.t, vmscl.q | 100% |

     The x64 interpreter (core 0) matches its rule on 83.6% to 99.98% of rows. vrcp.s on the interpreter
     differs from 1/x on 1348 of 3112 results.
   - The port agrees with the model:
     - The Windows-built corpus code in the test mode (PURE_VFPU_DOT=ppsspp) reproduces PPSSPP's Apple JIT
       samples (the Mac's ref/vfpu/jit) on every row: 1,172,943 dot products, 100%.
     - On the Windows samples, the test mode matches PPSSPP exactly as often as the model does, row for row.
     - The default (PSP) mode differs from PPSSPP by design.
     - So the port's x64 rounding is the arm64 rounding. What differs is PPSSPP's x64 JIT. On Windows, the
       trajectories' AI rows will compare against a PPSSPP that rounds otherwise.
   - Not done: ref/README.md's hand-kept VFPU hash rows still describe the Mac's sets.
   - Tool fixes, all in commit e38f5cd:
     - vfpu_probe `port` builds with clang-cl and the corpus's Windows flags.
     - vfpu_model loads the UCRT for its libm.
     - An f-string in vfpu_model that Python 3.12 does not parse is fixed.

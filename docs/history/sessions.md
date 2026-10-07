# Sessions: the resume notes, session by session

docs/status.md's Resume sections as they stood on 2026-10-07, when task 053 cut that section to what a new session
needs (the branches, the gate, the running task, the open calls) and moved the notes here, newest first, as written.
Only the patch numbers changed, which task 052 regrouped (patches/README.md maps the old numbers to the new): each is
named by the patch that holds the change now and the task that made it, or as "old NNNN" where the sentence counts
the old series. Branch tips, worker states and plans are those of the day.


## Resume (session 4, 2026-10-06)
- `main` = (Erik's tenth fast-forward, 2026-10-07 evening, the commit below): tasks 003, 016 to 048 merged, old patches 0001 to
  0015 and 0017 to 0021 (nine patches since task 052), D-003, D-007 to D-013; the M8 audit and fix round, the reverb, PSP-format saves, the scorecard,
  the AI's start, and the VFPU rounding by the PSP's rule. `batch/m2` continues from there. Remote: `origin` =
  https://dev.eriksmedia.com/erreib/pure-recomp.git (private GitLab, created 2026-10-06 by Erik's push of `main`);
  Erik pushes, nobody else (the session's permissions deny pushes; CLAUDE.md forbids them for workers).
- Merge gate: `tools/frame_regress.sh` (5 scenes, 7 min) after any renderer change; `tools/verify_task.sh NNN` reruns a
  brief's Verify from this checkout.
- Merged 2026-10-06: 022 (ge_replay, in the game executable behind `--replay`; our own `main()` through
  `HOST_MAIN_NAME`), 023 (Metal backend: the 2D frontend scenes within 0.0002 of PPSSPP), 026 (the shell seam, old patch
  0010, now part of 0004-ge-backend-and-shell-seams: `host::Shell`, Vulkan shell adapter, headless shell with pad from the input script; D-007), and Fable's old patch
  0011 (0005-kernel-host-waits-and-pacing; headless runs unpaced: thousands of frames a second), 027 (the Metal shell, old patch 0012), 024 (Metal 3D:
  lighting, fog, screen-space sprites, culling; the race frame at internal scale 1 matches Vulkan to its first
  stencil draw), 025 (Metal effects: stencil as alpha, bloom chain, read-backs and write-backs, ge_replay `--cut`).
  **M6 complete.** D-008: Metal by default on macOS. Merged: 028 (the default in our entry point, per-backend
  measured columns in the suite, `run_boot.py --shell/--backend`; Verify rerun PASS on both paths), 030
  (controls doc + checker), 031 (the Metal window's race HUD: one command queue, `tools/hud_check.sh`), 029 (the app
  bundle; the profile names the plain BOOT.BIN so the installer works). **The app at `out/release-macos/stage/Wipeout
  Pure.app` is built from the merged tree with the HUD fix and passes its checks.** Merged: 032 (the test-only
  unlock-all switch, racing lines from the port's own AI, every track in the sweep). Merged: 034 (faster tests: the suite headless on Metal in 10 s, a sweep cell in 199 s with only the race paced,
  tools on scratch data directories, silent runs; Verify rerun PASS). Merged: 033 (frame-time trace, pipeline pre-warming, vblank-timed presents; the remaining dips are the
  game's own two-vblank stretches, routed to 035 item 6; Verify rerun PASS). **D-009 (Erik, 2026-10-06): fidelity before enhancements; the
  pause-menu redesign is dropped.** Merged: 035, the M8 fidelity audit (two workers; the matrix loop finished on its own; Verify rerun PASS,
  18/18 scenes). Merged: 036 (environment and projection mapping, old patch 0013: the race scenes vs PPSSPP 0.012 to 0.035 now; the
  suite's Metal column re-baselined), 038 (the brightness is the weather mist's phase; not a difference). Merged: 039 (the save list, old patch 0015; Verify rerun PASS), 037 (mipmaps, old patch 0014: race scenes vs PPSSPP
  0.011 to 0.015 now, Blue Ridge 0.025; Verify rerun PASS). Merged 2026-10-07: 040 (colour test, dithering of the 565
  billboard target, depth clamp with CLIPENABLE on, old patch 0017; the record backend records mip levels; race scenes
  unchanged or lower; Verify rerun PASS, 18/18, HUD 61/61). Merged 2026-10-07: 041 (the hitches are the headless test runs' own:
  priority-31 threads under host load and a cold-cache pipeline compile, 16 minutes of windowed race without a frame of
  100 ms; the music's 2 s stop is the track's own fade and silence and PPSSPP plays the same samples; PPSSPP's attract
  demos clip as much; `tools/audio_compare.py`, the driver's `--dump-audio`; Verify rerun PASS). **The M8 fix round is
  complete.** Open: differences 5 (save encryption, Sony's keys) and 6 (UMD timing) await Erik's call; 12 (the SAS
  reverb: the game sends type 5, both sends on, volume 0x666, the framework drops all of it; a vendor patch, PPSSPP's
  race dump through audio_compare.py as the check) is the next fidelity task if Erik agrees; the pre-warm list's nine
  missing pipelines are the one hitch a player could meet. Then the accuracy scorecard Erik asked about. Erik (2026-10-07): proceed with the three steps.
  Merged 2026-10-07: 042 (the pre-warm list over 16 cells, the app ships it, the bundle check silent and checking
  the pre-warm; Verify rerun PASS) and 043 (the SAS reverb, old patch 0018, 17 patches; two constants fitted to PPSSPP,
  D-010; Verify rerun PASS). The app at out/release-macos/stage is repacked from the merged tree with both. Running:
  044 (the accuracy scorecard). Erik 2026-10-07: 6 → D-011, the faster loads stay. Merged 2026-10-07: 045 (saves in the PSP's own format: old patch 0019 writes mode 1 without a game key and verifies saves on the way in; `tools/save_interchange.sh` passes both directions against PPSSPP; 18 patches; Verify rerun PASS). D-012: the expanded version's own save format, later. Merged 2026-10-07: 044 (the accuracy
  scorecard: `tools/scorecard.py --quick` in 49 s, `--full` in 18 min, references cached under ref/scorecard; first
  run in docs/scorecard.md: pictures faithful, timing faithful, audio faithful, saves close (69 heap pointers), coverage
  close, trajectories differs: the port's AI ships run a different race from PPSSPP's from 0.4 s after GO on every
  circuit while each side repeats itself, and three player paths move where an AI ship comes near or a wall scrape
  amplifies a 1 to 3 km/h contact difference). Merged 2026-10-07: 046 (the AI's start is `rand()` seeded from the time since boot and the game's frame clock at
  TEAM SELECTION, plus the unlocked team set and the port's 1 ms frame-time quanta; pinned by the test switch
  `PURE_TEST_RACE_CLOCK`, all 12 player trajectories are faithful, Karbonis included; the load is not involved; the AI
  still parts over a 1-ulp VFPU dot product in the codegen). Merged 2026-10-07: 047 (the probe and the rule: PPSSPP's JIT fuses vdot/vtfm in lane order
  and leaves vmmul unfused, its own compiler's doing; the real PSP, from pspautotests, truncates aligned products with
  two extra bits; the port fuses from another lane). D-013: the port rounds as the PSP, PPSSPP's rule is a test mode.
  Old patch 0020 landed 2026-10-07 (Fable): `vfpu_dot` rounds as the PSP (default) or as PPSSPP's JIT (test
  mode), the Vtfm/Vmmul emitters use it, the corpus is compiled with `-ffp-contract=off`; 19 patches; both modes 100
  percent on the 1.17 million samples; suite 18/18. The AI rows still part on ten circuits and Karbonis' player
  parts at 12 s under the test mode: the cross/quaternion products and vfad/vavg were never sampled. Merged 2026-10-07: 048 (vcrsp.t is
  unfused in PPSSPP's JIT on 1.59 million lanes, vfad a sequential sum; Karbonis' player parts after cross products
  alone). **M9 organisation pass, wave 1 merged 2026-10-07 evening:** 049 (the Metal backend in seven files by concern,
  the shaders as src/gpu/shaders/ge.metal, `tools/refactor_check.sh` pixel-exact), 050 (tools/purelib, the shared
  runner; every headless run on the steady clock), 051 (src/profile/test_hooks, the profile 668 to 201 lines), 052
  (nine patches by topic, the tree byte-identical, docs/upstream.md). Running: 053 (the docs pass). Then a
  simplification task from 049's list, then enhancements.
  Old patch 0021 landed (Fable, then regrouped into 0009-vfpu-rounding by task 052): both modes 100 percent on all 18 sample sets; suite 18/18;
  the player trajectories faithful on 11 of 12 (Karbonis parts by mm after a 7 s scrape, from something no sample
  covers: subnormal flushing is the next suspect); the AI rows moved but stay `differs` on nine circuits, which is
  the bit-exact chase against PPSSPP's JIT the plan rules out: **the rounding work stops here.** Next: the
  organisation pass (Erik's), then enhancements.
  Open for Erik: a finer virtual-time answer than the kernel's 1 ms starvation tick. Erik, 2026-10-06: finish this round first; then consider an accuracy scorecard (pictures,
  trajectory divergence per track with the AI seed pinned, timing, audio correlation, save files byte for byte,
  coverage, a VFPU differential test) before any enhancement. The game's own unlock code on MAIN MENU: LEFT, RIGHT,
  LEFT, L, R, L, RIGHT, LEFT, RIGHT, R, L, R (sets the profile byte the test switch stands in for).
- M5 breadth still open: higher classes/leagues, the other tracks in Time Trial/Free Play (budgets 11000 untested),
  a Zone racing line (a PPSSPP lap of PRO TOZO logged with `tools/pp_lines.py`), Erik's recorded lap
  (`tools/pad_record.py`), the save-list dialog for multiple profiles.

## Resume (updated at the end of session 2, 2026-10-05)
- `main` = 2971eff (Erik's second fast-forward). `batch/m2` is two commits past it (resume notes, `tools/pad_record.py`).
- `task/011-shadow-volumes-and-dual-source` (29ec191): PARTIAL, old patch 0006 exported but never built; the Result section
  holds the stencil-versus-alpha design rule and the exact remaining steps (wire `submit()`, build, capture, Verify).
  Finish it from that branch; do not merge the unbuilt patch. `task/012-campaign-sweep`: PARTIAL; the sweep tool, the single_race route, `docs/tracks.md` and a Vineta K
  notes file exist, no steering tuned (the first corner is a right-hander; a race needs ~18,000 flips). Decisions for
  the follow-up (Fable): `--frames` counts from the Cross hold, as the tool does; distance-keyed steering tables are
  acceptable; prefer Erik's recorded lap (`tools/pad_record.py`) over the closed-loop tuner, and keep the tuner's
  PPSSPP AI-line idea as the fallback for tracks nobody drives. Merge per the checklist;
  re-export old 0006 over the series if `tools/patches.sh check` complains.
- Next steps in order: merge 011/012; Erik's recorded lap (`tools/pad_record.py` turns a run log with
  `PURE_TRACE_PAD=1 PURE_FRAME_LOG=1` into a script; the command and keys are in the chat recap and README) to replace
  hand-tuned steering; M4 audio checks (wavstats); M5 save round trip; then the Metal backend (M6) on top of the five
  vendor patches, which are all upstream candidates.
- Session 3 (2026-10-05, Erik: "Proceed"): workers dispatched for 011 (continued), 012 (continued), 013 (audio
  checks), 014 (save round trip); merge whichever finished, from their branches.
- Earlier resume notes (session 1) follow.

## Resume (written 2026-10-05 at the first pause)
- Branches: `main` fast-forwarded to ad219ee on 2026-10-05 (Erik's third "fast-forward main"): old patches 0001 to 0007,
  tasks 001-015 (012 partial, 016 running). `batch/m2` continues from there. Both other workers committed PARTIAL results on their branches (worktrees under `.claude/worktrees/`):
  - `task/001-tooling-port`: `tools/patches.sh` DONE (check/export tested), `tools/worktree_init.sh` written (a fresh
    worktree builds in 33 s, all 144 corpus units ccache hits, so R5 is resolved); run_boot flags, check_env PIN check,
    README rows NOT done. Merge the two scripts after rerunning `tools/patches.sh check`; re-brief the rest as task 004.
  - `task/003-headless-intro-movie`: diagnosis only (see Blockers). Re-brief as "movie end condition": validate
    against PPSSPP, then old patch 0002 or `PURE_SKIP_FMV`.
- Fixes the workers asked for, outside their May-touch: `.gitignore` must use `/disc`, `/generated`, `/game` (the
  trailing-slash forms do not match the symlinks worktrees use); `tools/check_env.sh` still names `vendor/yakumo`;
  `run_boot.py` should give the game a pty (block-buffered stdout loses the tail at the deadline kill); `[hle-stub]`
  prints only on a stub's first call. Merge per the
  checklist in CLAUDE.md / the plan: rerun each brief's Verify from this checkout, spot-read, `git merge --no-ff` into
  `batch/m2`, remove the worktree.
- PPSSPP driver (spike S6, committed): `tools/ppsspp/ppsspp_ctl.py run --pad "700:CROSS,708:,..." --shot F:out.png
  --gedump F:out.ppdmp --log ...` drives PPSSPPSDL through its WebSocket debugger with frame-exact, deterministic input
  (`docs/ppsspp.md`). Screenshots need `SoftwareRenderer = True` (read from VRAM), GE dumps work with any renderer,
  save states are blocked (needs Accessibility for F2). PPSSPP timeline on a fresh memory stick: language ~480,
  notice ~1560, START at 2400 skips the movie, title ~2520, **profile screen Load/New/Delete ~2880** (our port shows a
  blank page there: the movie-end blocker). `ref/` is still empty; `out/ppsspp/title.{png,ppdmp}` and
  `out/ppsspp/boot-hle.log` exist. `tools/ppsspp/routes/{frontend,vineta_k_start}.txt` are deterministic (task 006).
- Next milestone steps: fix the profile-screen stall above; route to the main menu and a race (task 004: route script
  + `route_check` using `tools/imgdiff.py --region --min-variance`); PPSSPP reference compare; then M3 (race).
- The plan with every brief: `~/.claude/plans/in-the-bouncer-recomp-validated-babbage.md`.

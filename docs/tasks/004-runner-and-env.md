# 004: Runner flags, pty, stub summary, env check, README rows (the rest of task 001)

Milestone: M2 | Branch: task/004-runner-and-env | Status: OPEN

## Goal
Finish the tooling that task 001 left undone so routes, captures and stub summaries come from one command. Task
001's Result section in docs/tasks/001-tooling-port.md records what exists and the pitfalls it found.

## Read first
- CLAUDE.md, docs/tasks/001-tooling-port.md (Result and Open questions), README.md (Running section)
- tools/run_boot.py, tools/check_env.sh, tools/worktree_init.sh
- ~/dev/bouncer-recomp/tools/run_boot.py (the pty and log handling to copy)
- vendor/portablekit/host/ui/input_script.hpp (the script syntax) and host/system.cpp lines 40-60 ([hle-stub] prints once)

## Deliverable
1. `tools/run_boot.py`: run the game under a pty (as Bouncer's does) so block-buffered stdout is not lost at the
   deadline kill; `--script FILE` (joins non-empty, non-`#` lines with `;`, sets `PURE_INPUT_SCRIPT`, implies
   `--window`); `--shots DIR` (`PURE_SCREENSHOT_DIR`, converts every new `.bmp` there to `.png` after the run using
   `tools/png.py` `read_bmp`/`write_png`, not sips); `--every N` (`PURE_SCREENSHOT_EVERY`, default 0 with `--shots`);
   `--frames N` (`PURE_EXIT_AT_FRAME`, deadline max(seconds, N/15), exit 0 when `[pure] exit at frame` appears);
   `--stubs` (writes `<log>.stubs.txt`: each `[hle-stub] Library::name` with its `ra`, plus the start-up
   "Unimplemented imports" list). Keep the folded log and the 25-line tail.
2. `tools/check_env.sh`: also report `generated/` unit count (expect 144) and warn when `build/arm64/bin/PureNative`
   is older than `src/profile/pure_profile.cpp`.
3. `config/pad_scripts/frontend.txt`: the windowed route from boot to the title screen with named shots:
   `700:pad a` (language), `1600:pad a` (memory-stick notice), `2100:pad start` (title), shots `lang`, `notice`,
   `title` at frames that show those screens (verify with imgdiff variance on the title logo region 100,100,280,80).
4. README.md: Running section rows for the new flags; Layout rows for tools/patches.sh and tools/worktree_init.sh.

## Acceptance criteria
- [ ] `python3 tools/run_boot.py --seconds 20 --stubs out/004.log` writes `out/004.log.stubs.txt` listing the 26
      start-up stubs, and the log's last line is the `[run_boot] exit` line (nothing lost to buffering).
- [ ] `python3 tools/run_boot.py --script config/pad_scripts/frontend.txt --shots out/004-shots --seconds 80 out/004r.log`
      leaves `out/004-shots/title.png`, and `python3 tools/imgdiff.py out/004-shots/title.png --region 100,100,280,80 --min-variance 50` passes.
- [ ] `tools/check_env.sh` passes and prints the unit count.

## Verify
`python3 tools/run_boot.py --seconds 20 --stubs out/004.log; test -s out/004.log.stubs.txt && tail -1 out/004.log | grep -q 'run_boot\] exit' && python3 tools/run_boot.py --script config/pad_scripts/frontend.txt --shots out/004-shots --seconds 80 out/004r.log; python3 tools/imgdiff.py out/004-shots/title.png --region 100,100,280,80 --min-variance 50 && tools/check_env.sh`

## May touch
- tools/run_boot.py, tools/check_env.sh, config/pad_scripts/frontend.txt, README.md

## Must not touch
- src/, vendor/, patches/, tools/png.py, tools/imgdiff.py, anything else

## Estimated turns
30

## Escalate when
The pty approach changes the game's behaviour (different frame counts for the same script) or the title shot never
shows the logo within 80 s; report the frame numbers you observed and stop.

## Result
(worker fills)

## Review
(Fable fills)

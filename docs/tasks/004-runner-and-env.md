# 004: Runner flags, pty, stub summary, env check, README rows (the rest of task 001)

Milestone: M2 | Branch: task/004-runner-and-env | Status: MERGED

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
Status: DONE. The route needed one more step than the brief lists (see deliverable 3 and Open question 1).

Bootstrap: `tools/worktree_init.sh` reported a 34 s build (worktree ready in 35 s), with ccache at +243 hits and +2 misses.

Deliverables:
- 1 `tools/run_boot.py`: the game now runs with a pty as stdout and stderr (OPOST off, so lines end in `\n` without
  `\r`). The parent keeps the slave end open until the output is drained. On macOS, unread pty output is discarded
  when the last slave descriptor closes. A test child that wrote 50 lines and exited gave 0 bytes once the slave was
  closed, and all of them with the slave held open. Bouncer's runner never holds the slave, so it can lose a
  runner's last lines before exit. The new flags are `--script`, `--shots` (PNG conversion with `tools/png.py`, BMPs
  kept, only new or rewritten BMPs converted), `--every` (0 by default with `--shots`), `--frames` (deadline
  max(seconds, N/15), exit 0 on `[pure] exit at frame`, killed 15 s after it if shutdown hangs) and `--stubs`.
  argparse replaces the hand parser, so an unknown flag is now an error instead of being taken as the log path. The
  folded log and the 25-line tail are kept. The runner's closing lines (`deadline`, `stubs`, `shots`, `exit`) are
  written past `--max-lines`, so the log always ends with `[run_boot] exit`. Stubs are collected from the raw stream,
  so the cap does not truncate the summary. Ctrl-C kills the game. Tested: `--frames 300` headless exits 0 in 13.9 s;
  `--shots --every 200 --frames 610` windowed gives frame_200/400/600 PNGs; `--max-lines 50 --stubs` still ends with
  the stubs and exit lines; the stub parser was checked on synthetic `[hle-stub]` lines, including one glued to a
  `[guest]` line.
- 2 `tools/check_env.sh`: prints `generated/: 144 units`. A different count fails. A missing generated/ is a `warn`,
  because First-time setup runs check_env before the first regen. It warns when `build/arm64/bin/PureNative` is
  missing or older than `src/profile/pure_profile.cpp`. I tested this by backdating the binary's mtime and then
  restoring it.
- 3 `config/pad_scripts/frontend.txt`: `690:shot lang`, `700:pad a`, `1600:pad a`, `1640:shot notice`, `1650:pad a`,
  `1800:pad start`, `1840:shot title`. The title shot shows the wipEout pure logo and PRESS START BUTTON. It came out
  pixel-identical in three separate runs (imgdiff fraction 0.000000).
- 4 README.md: a table of the run_boot.py flags in Running, the new conversion in the `PURE_SCREENSHOT_DIR` row
  (replacing `sips`), the measured route in place of the old frame numbers, and Layout rows for `tools/patches.sh`
  and `tools/worktree_init.sh`.

Escalation checks (neither condition occurred):
- pty against pipe: I ran the same 56-step script windowed under HEAD's pipe runner (with `--env`) and under the
  new pty runner. All 53 shots matched pixel for pixel (fraction 0.000000 at every frame from 650 to 2300). The 20 s
  headless logs were line-identical apart from the new stubs line.
- The title is up from frame 1810 and shot at 1840, about 62 s into the run. In a run that quit at 2110, the game
  exited after 71 s.

Frames observed (windowed, this build):

| Frame | Screen |
|---|---|
| 500 to 700 | Language Selection (Cross at 700) |
| 800 to 850 | "Sony Computer Entertainment America presents" |
| about 900 to about 1730 | "A Studio Liverpool Game" loading page, if left alone. A Cross there skips it, and the notice is up 5 frames later (1605 after the Cross at 1600, 1740 after one at 1720) |
| 1605 | memory-stick notice. It stays until a Cross that comes after it. With the brief's three steps the run is still on it at 2400 |
| about 1690 | intro movie `WoFMVNew_US.PMF` after the Cross at 1650. It never ends by itself (still playing at 2400 when the notice was cleared at 1700) |
| 1810 | title, after Start at 1800 skips the movie. Still up at 2100 |

Title-region (100,100,280,80) variance by screen: title 8295, notice 4643 to 5341, loading page 1936, movie 0 to 2730,
language 3.9.

Changed: tools/run_boot.py, tools/check_env.sh, config/pad_scripts/frontend.txt (new), README.md,
docs/tasks/004-runner-and-env.md (this Result)

Verify output (last 20 lines; exit 0. Earlier in the output: `[run_boot] stubs: 26 unimplemented at start-up, 0 called
-> out/004.log.stubs.txt`, `[run_boot] exit 124 after 20.1s, 252 lines` as the last log line, `[run_boot] shots: 3 new
BMP(s) converted to PNG in out/004-shots (lang, notice, title)`, and `PASS variance R/G/B 530.8/1180.2/8295.1 (max
8295.1, need 50) in region 100,100,280,80 of out/004-shots/title.png (960x544)`):
```
pure-recomp environment
  ok    cmake (/opt/homebrew/bin/cmake)
  ok    ninja (/opt/homebrew/bin/ninja)
  ok    ccache (/opt/homebrew/bin/ccache)
  ok    pkg-config (/opt/homebrew/bin/pkg-config)
  ok    python3 (/opt/homebrew/bin/python3)
  ok    glslangValidator (/opt/homebrew/bin/glslangValidator)
  ok    /usr/bin/clang is Apple clang
  ok    pkg-config sdl3 3.4.18
  ok    pkg-config vulkan 1.4.363
  ok    MoltenVK
  ok    java openjdk version "21.0.12.1" 2026-08-18
  ok    ghidra at /opt/homebrew/opt/ghidra/libexec
  ok    ghidra-allegrex zip present
  ok    PPSSPP app (/Applications/PPSSPPSDL.app)
  ok    disc.iso -> /Users/erreib/Downloads/Wipeout Pure (USA) (En,Fr,Es) (v2.00).iso
  ok    disc/ extracted (38 files)
  ok    vendor/portablekit at 8b0c3fe
  ok    generated/: 144 units
  ok    build/arm64/bin/PureNative is newer than src/profile/pure_profile.cpp
```

Open questions:
1. The route has one step more than the brief, and the Start comes earlier. On this build, the Cross at 1600 lands on
   the loading page rather than the notice, so the notice needs its own Cross (1650). Start skips the movie at 1800
   instead of 2100: Start at 2100 would put the title at about 2110, roughly 72 s in, too close to the 80 s deadline.
   The route also ends at the title without pressing Start there. Start on the title opens `Profile_part1.PMF`, the
   task 005 stall. The status.md figures ("notice ~1500, title ~2050") are stale for this build. Fable to confirm.
2. The acceptance check is weak. A variance of at least 50 in the logo region also passes the notice, the loading page
   and most movie frames, and it fails only the language page and blank frames. I checked title.png by eye. A
   stronger check would be a compare against a reference title frame, or a threshold around 6000 (title 8295, highest
   other screen seen 5341), though that threshold may not hold across renderers.
3. `--shots` implies `--window`, which the brief states only for `--script`. A headless run has no renderer and
   captures nothing.
4. CLAUDE.md lists `tools/verify_task.sh`, but it is not in the tree. I ran the Verify line directly with bash.

## Review
Verify rerun by Fable on batch/m2 after the merge: headless `--stubs` and `check_env.sh` pass; the title capture
failed at first (variance 4) because the worker measured its route before patch 0002, which lets the SCEA clip play
to its end after the language confirm and moves every later frame: the title is up from ~1700 and the Start at 1800
had opened the profile movie before the 1840 shot. Route re-timed: title shot at 1750, Start at 1800, profile shot at
2100 (variance 8295 on the title, profile page matches `out/shots6/q3000.png` within 0.02%). Spot-read: the pty
handling and the stubs parser in tools/run_boot.py. Merged: 5c2b5e6 area (batch/m2). Notes: `--shots` implies
`--window` (fine); `tools/verify_task.sh` is still unwritten.

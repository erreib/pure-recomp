# 001: Tooling port: patches.sh, worktree_init.sh, run_boot hardening

Milestone: M1 | Branch: task/001-tooling-port | Status: OPEN

## Goal
Every later task runs in its own git worktree. A worktree must become buildable in minutes without regenerating or
recompiling the corpus from scratch, vendor patches must be checkable and exportable, and the headless runner must
produce a stub summary and support frame-count exits. Model the scripts on the Bouncer ones named below.

## Read first
- CLAUDE.md
- tools/vendor_setup.sh, tools/build.sh, tools/regen.sh, tools/setup_game.sh, tools/run_boot.py, tools/env.sh
- patches/README.md, patches/0001-embed-nids-verbatim.patch
- ~/dev/bouncer-recomp/tools/patches.sh and ~/dev/bouncer-recomp/tools/run_boot.py (shape to copy; paths differ)
- docs/vendor-map.md section "Building"

## Deliverable
1. `tools/patches.sh check`: clones nothing; verifies that `vendor/portablekit` HEAD equals `vendor/PIN`, that
   applying `patches/*.patch` in order to a clean checkout of that commit (use `git -C vendor/portablekit stash`-free
   logic: `git worktree add` of the pinned commit into a temp dir, apply, diff against the live vendor tree)
   reproduces the live tree exactly; prints `ok` or the first differing file. `tools/patches.sh export NNNN-slug`:
   writes `git -C vendor/portablekit diff` of the uncommitted vendor changes relative to the already-applied series
   to `patches/NNNN-slug.patch` (i.e. the delta beyond existing patches), refuses if NNNN exists, reminds to add the
   README row.
2. `tools/worktree_init.sh`: in a fresh worktree, runs `tools/vendor_setup.sh`, symlinks `game/` and `generated/`
   to the main checkout's (path from `git worktree list`'s first entry, or `$PURE_MAIN_CHECKOUT`), symlinks
   `disc.iso` and `disc/` the same way, then `tools/build.sh profile`. With the shared `CCACHE_DIR` from `tools/env.sh`
   the corpus compile must be cache hits; print the build time at the end.
3. `tools/run_boot.py`: add `--script FILE` (reads the file, joins non-empty non-comment lines with `;`, sets
   `PURE_INPUT_SCRIPT`; implies `--window`), `--shots DIR` (sets `PURE_SCREENSHOT_DIR`, converts every `.bmp` written
   there to `.png` after the run with `sips -s format png`, keeps the `.bmp`), `--every N` (`PURE_SCREENSHOT_EVERY`),
   and a `--stubs` summary: after the run, write `<log>.stubs.txt` listing each `[hle-stub]`
   library::name with its count and first `ra`, and print the count; `--frames N` sets `PURE_EXIT_AT_FRAME=N`
   (implemented in `src/profile/pure_profile.cpp` by Fable; stops the runtime at that flip) and raises the deadline
   to max(seconds, N/15); exit code 0 when the run ended by the frame exit (`[pure] exit at frame N` in the log).
4. `tools/check_env.sh`: also checks `vendor/PIN` matches `vendor/portablekit` HEAD and that `generated/` has
   144 units when present.

## Acceptance criteria
- [ ] `tools/patches.sh check` prints ok on the current tree; after a deliberate one-line edit in
      vendor/portablekit it reports that file; `export 0002-test` writes exactly that one-line diff (then delete it).
- [ ] In a fresh `git worktree add /tmp/pure-wt`, `tools/worktree_init.sh` completes and `build/arm64/bin/PureNative`
      exists; the corpus units were cache hits (`ccache -s` hit count rises by about 144).
- [ ] `tools/run_boot.py --seconds 30 --stubs out/t.log` writes `out/t.log.stubs.txt`.
- [ ] `tools/run_boot.py --seconds 40 --script config/pad_scripts/frontend.txt --shots out/t-shots out/t2.log` leaves
      PNGs in `out/t-shots` (the script file: `650:shot lang` on one line is enough for the test; a real route is
      task 003's).

## Verify
`tools/patches.sh check && tools/check_env.sh && python3 tools/run_boot.py --seconds 20 --stubs out/001.log; test -f out/001.log.stubs.txt`

## May touch
- tools/patches.sh, tools/worktree_init.sh, tools/run_boot.py, tools/check_env.sh, README.md (Layout/Setup rows),
  config/pad_scripts/frontend.txt (test script only)

## Must not touch
- src/, vendor/, patches/, config/, CMakeLists.txt, anything else

## Estimated turns
25

## Escalate when
`git worktree` or ccache behaves differently from the brief (e.g. the corpus is not cache-hit in a worktree): report
the measured build time and stop rather than changing build flags.

## Result
Status: PARTIAL (stopped early at the coordinator's request; Verify fails because deliverable 3 is not done)

Deliverables:
- 1 `tools/patches.sh`: DONE. `check` verifies HEAD == vendor/PIN, applies the series to a temporary `git worktree`
  of the pin, compares every path either tree changed (bytes, presence, executable bit), prints `ok: ...` or
  `differs: <first file>` (exit 1). `export NNNN-slug` writes only the delta beyond the series, refuses an NNNN that
  exists or is not above the last patch, and reminds to add the README row. Tested: ok on the current tree; a
  one-line edit to cmake/PortableKit.cmake (a file 0001 already patches) is reported by `check`, and
  `export 0002-test` wrote exactly that one added line (not 0001's VERBATIM); with 0002-test present `check` is ok
  again; an added and a deleted file export as new/deleted; duplicate and lower numbers are refused; a wrong PIN is
  reported. Test patches deleted and the vendor tree restored (`check` ok).
- 2 `tools/worktree_init.sh`: written, tested only on this already-initialised worktree (3 s; not yet run in a
  fresh `git worktree add /tmp/pure-wt`). Steps: vendor_setup.sh (skipped when `patches.sh check` passes, refused
  when the vendor tree has uncovered changes), links disc/ generated/ disc.iso into the main checkout,
  tools/setup_game.sh, clones the main checkout's FFmpeg archive into build/arm64/_deps/downloads, then times
  `tools/build.sh profile` (log in out/worktree_init.log) and prints the ccache hit/miss delta, warning above 20
  misses.
- 3 `tools/run_boot.py` (--script, --shots, --every, --stubs, --frames N/15 and exit 0 on frame exit): NOT DONE.
- 4 `tools/check_env.sh` (PIN check, 144 units): NOT DONE.
- README Layout/Setup rows and config/pad_scripts/frontend.txt: NOT DONE.

Measured worktree build time: the hand bootstrap of this fresh worktree took 33.3 s wall for `tools/build.sh profile`.
That covers the configure, which downloaded and built FFmpeg 7.1.5, and 250 ninja steps. The shared ccache went
from 243 to 487 direct hits (+244) and from 497 to 498 misses (+1), so all 144 corpus units were cache hits.
`tools/vendor_setup.sh` took 1.1 s. Re-running `tools/worktree_init.sh` afterwards gave a 2 s build and +0/+0.

Changed: tools/patches.sh (new), tools/worktree_init.sh (new), docs/tasks/001-tooling-port.md (this Result)

Verify output (last 20 lines; exit 1: run_boot.py does not know --stubs yet, so out/001.log.stubs.txt is absent):
```
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/Adverts/advert_006.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/Adverts/eddie_coffeeshop.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/3DVexWindow/Assegai/logo01.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/Adverts/eddie_staten.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/3DVexWindow/Agsystems2/mankind.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/Adverts/eddie_ubermall.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/MusicLicensed/landscape02.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Billboards/MusicLicensed/colour_landscape01.vex/stringtable.xml flags=0x000F0001 -> 0x80010002
    ... (x2)
[io] open disc0:/PSP_GAME/USRDIR/Data/Movies/IntroMovieP1_US.PMF flags=0x000F0001 -> 0x80010002
[run_boot] deadline 20s reached, killed
[run_boot] exit 124 after 20.0s, 253 lines
```
(`tools/patches.sh check` printed `ok: 1 patch(es) reproduce vendor/portablekit at 8b0c3fe` and `tools/check_env.sh` passed.)

Open questions:
1. game/: the brief says to symlink game/ to the main checkout. The dispatch steps said to run `tools/setup_game.sh`,
   and the script follows them, so each worktree gets its own game/ and its own ms0/ saves. Parallel runs then do
   not share save state, and the copy is 3.8 MB. Fable to confirm.
2. `.gitignore` lists `disc/`, `generated/` and `game/` with a trailing slash. Those patterns do not match symlinks,
   so in a worktree the `disc` and `generated` links show as untracked, and a `git add -A` would commit them. The
   fix is `/disc` and `/generated` without the slash, but `.gitignore` is outside May touch.
3. For whoever finishes deliverable 3: the framework prints `[hle-stub]` only on a stub's first call
   (vendor/portablekit/host/system.cpp:52), so the per-name count in the summary will almost always be 1. Also,
   run_boot.py reads the runner through a pipe, which leaves std::cout block-buffered. Lines still in the buffer
   are lost when the deadline kill fires. Bouncer's run_boot.py gives the runner a pty for this reason.
4. check_env.sh still checks for `vendor/yakumo`, a stale name. Deliverable 4 should replace that line with the
   PIN check.
5. The FFmpeg archive copy in worktree_init.sh goes slightly beyond the brief. It avoids an 11 MB download from
   ffmpeg.org per worktree and changes no build flag.

## Review
(Fable fills)

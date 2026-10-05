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
(worker fills)

## Review
(Fable fills)

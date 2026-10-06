# 015: Heap corruption reported at shutdown

Milestone: M3/M5 hygiene | Branch: task/015-heap-corruption | Status: OPEN

## Goal
After a race run ends by `PURE_EXIT_AT_FRAME`, the process sometimes prints
`PureNative(...) malloc: Heap corruption detected, free list is damaged at 0x6000...` and `*** Incorrect guard value:
16` during shutdown (`~/dev/pure-recomp/out/p6.log`, `out/full.log`; task 011 saw two of six runs hang at shutdown).
A damaged free list means a host-side out-of-bounds or use-after-free write somewhere earlier. Find it and fix it.

## Read first
- CLAUDE.md, docs/status.md (Blockers), src/profile/pure_profile.cpp and src/hle/audio_capture.cpp (our own host
  code: wrappers holding `static HleFunction original`, the flip counter, the movie/ship probes), the framework's
  shutdown path in vendor/portablekit/host/main.cpp and host/gpu/vulkan_renderer.cpp (destruction order), and
  the run logs named above (the message appears after `[run_boot]`'s frame exit).

## Deliverable
1. Reproduce with diagnostics: macOS `MallocScribble=1 MallocPreScribble=1 MallocGuardEdges=1
   MallocCheckHeapStart=1000 MallocCheckHeapEach=1000` on a race run to frame 6045 (expect a crash or an earlier
   report with a backtrace: run under `lldb --batch` or read the crash report), or a host-only AddressSanitizer
   configure in a separate build directory (`-DCMAKE_CXX_FLAGS=-fsanitize=address` for the host sources only; the
   corpus units may be excluded with a cache variable if the build system allows, otherwise expect a long build).
2. The culprit with file:line and the fix: in `src/` directly, or in `vendor/` as `patches/0007-<slug>.patch`.
3. Three consecutive race runs to frame 6045 with clean shutdown (no malloc message, process exits by itself).

## Acceptance criteria
- [ ] The Result names the write (file:line) and shows the diagnostic output that found it.
- [ ] Three runs `python3 tools/run_boot.py --script out/015/route.txt --frames 6045 --seconds 230 out/015/runN.log`
      end with `[run_boot] exit 0` and contain no `malloc:` line.

## Verify
`for n in 1 2 3; do grep -q 'malloc:' out/015/run$n.log && exit 1; grep -q 'run_boot\] exit 0' out/015/run$n.log || exit 1; done; echo clean`

## May touch
- src/, patches/ (via `tools/patches.sh export 0007-<slug>`), docs/status.md (the blocker row), tools/env.sh (a
  documented `PURE_MALLOC_DEBUG=1` switch is welcome)

## Must not touch
- vendor/portablekit/include/psprecomp/, tools/run_boot.py, config/

## Estimated turns
50

## Escalate when
The corruption is in generated corpus code or the framework's runtime core (then report the write and stop).

## Result
(worker fills)

## Review
(Fable fills)

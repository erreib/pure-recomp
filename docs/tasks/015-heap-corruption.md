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

Status: DONE. The corrupting write is in the framework's renderer teardown (host layer, not generated code or the
runtime core). Patch 0007 fixes it. Three race runs to frame 6045 now shut down cleanly, and Verify prints `clean`.

Changed:
- patches/0007-free-target-descriptors-before-pool.patch (vendor host/gpu/vulkan_renderer.cpp): `shutdown()` now
  destroys the render targets, the held picture and the interpolation targets before `vkDestroyDescriptorPool`.
  Before, it did so after.
- patches/README.md: row 0007 (Bug, upstream candidate).
- tools/env.sh: `PURE_MALLOC_DEBUG=1` exports the macOS malloc checks used here (MallocScribble, MallocPreScribble,
  MallocGuardEdges, MallocCheckHeapStart/Each=1000, MallocCheckHeapAbort). The comment shows how to scope it to one
  run with a subshell, so the compiler does not inherit the checks.
- docs/status.md: the blocker row is marked resolved.
- This file.

Culprit: `vendor/portablekit/host/gpu/vulkan_renderer.cpp:3552`, in `Impl::destroy_target`:
`vkFreeDescriptorSets(device, descriptor_pool, 1u, &descriptor)` for each target's two `copy_descriptors`. Those
are allocated when the game samples a framebuffer as a texture, which Wipeout Pure's race bloom does. Line numbers
are for the pin plus patches 0001 to 0006. `shutdown()` reached that line from :8071, after it had already destroyed
`descriptor_pool` at :8059. Under MoltenVK 1.4.2, the pool and its sets are C++ heap objects.
`MVKDescriptorPool::freeDescriptorSets` puts each freed set on the pool's free list: it stores into the pool
object, emplaces into its free-list vectors and links the set object. All of that memory was freed with the pool.

The damaged nano free-list slot is only detected at the next allocation that picks it, which made the symptom look
random. The 9 crash reports from 19:16 to 21:34 today all show `nanov2_guard_corruption_detected` in `exit()` ->
`MediaState::~MediaState` (hle_media.cpp:112) -> `~VulkanRenderer` -> `shutdown()`. In 5 of them it fires inside
`vkFreeDescriptorSets` from `destroy_target`. In the other 4 it fires later in the same teardown: in
`SDL_DestroyWindow`, in AppKit, or in an AudioQueue stop on a dispatch thread while the main thread was in
`vkDestroyCommandPool`. The "hang" was not a separate bug. The aborting process sits in the crash reporter for
longer than run_boot's 15 s grace period, so run_boot kills it and logs `shutdown hung`.

Diagnostic output that located it:

1. The brief's malloc variables, on a race run to frame 6045 with the unfixed binary (`out/015/malloc_debug.log`;
   crash report `PureNative-2026-10-05-214750.ips`, pid 76577). With MallocScribble, the stale free fails at once
   on the scribbled pointer:
   ```
   PureNative(76577,0x1f642e2c0) malloc: *** error for object 0x5555555555555555: pointer being freed was not allocated
   PureNative(76577,0x1f642e2c0) malloc: *** set a breakpoint in malloc_error_break to debug
   [run_boot] killed 15s after the frame exit (shutdown hung)
   ```
   Faulting thread (main):
   ```
   libsystem_malloc  ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
   libMoltenVK       std::vector<MVKDescriptorPoolFreeList::Entry>::emplace<unsigned long&>(...)
   libMoltenVK       MVKDescriptorPool::freeDescriptorSets(unsigned int, VkDescriptorSet_T* const*)
   libMoltenVK       vkFreeDescriptorSets
   PureNative        VulkanRenderer::Impl::destroy_target(Target&)   vulkan_renderer.cpp:3552
   PureNative        VulkanRenderer::shutdown()                      vulkan_renderer.cpp:8071
   PureNative        VulkanRenderer::~VulkanRenderer()               vulkan_renderer.cpp:2212
   PureNative        MediaState::~MediaState()                       hle_media.cpp:112
   libsystem_c       __cxa_finalize_ranges <- exit
   ```
2. The same run under `lldb --batch` with MallocScribble=1 (`out/015/lldb_uaf.log`). It breaks on
   `vkDestroyDescriptorPool`, prints the pool handle, then enables a breakpoint on `vkFreeDescriptorSets`. It shows
   the frees going to the pool that was just destroyed, and that the pool's memory is already freed (scribbled
   0x55). The same address held live data while the texture sets were freed at :8005, before the destroy:
   ```
   vkDestroyDescriptorPool  x1 = 0x0000000148008000   shutdown() at vulkan_renderer.cpp:8059:5
   vkFreeDescriptorSets     x1 = 0x0000000148008000   destroy_target() at vulkan_renderer.cpp:3552:43 <- shutdown() :8071:55
   (lldb) memory read -f x -s 8 -c 8 $x1
   0x148008000: 0x5555555555555555 0x5555555555555555
   0x148008010: 0x5555555555555555 0x5555555555555555
   ...
   malloc: *** error for object 0x5555555555555555: pointer being freed was not allocated
   ```
3. With the fix, the same malloc-checked run (`out/015/malloc_debug_fixed.log`) stops at frame 6045 and exits by
   itself in 199.7 s with no malloc error and no crash report. Its only `malloc:` lines are the checker's
   informational ones, which is why the Verify runs use no malloc variables.

Verify: `python3 tools/run_boot.py --script out/015/route.txt --frames 6045 --seconds 230 out/015/runN.log`, run
three times one after another. `out/015/route.txt` is `out/race/route.txt` without its `shot` lines. Each run
reaches `[pure] exit at frame 6045` / `Runtime stopped: PURE_EXIT_AT_FRAME reached` and exits by itself, with no
`killed ... (shutdown hung)` line. The run logs end with:
```
run1: [run_boot] exit 0 after 199.1s, 454 lines
run2: [run_boot] exit 0 after 198.4s, 453 lines
run3: [run_boot] exit 0 after 197.6s, 453 lines
```
Verify command output (all of it):
```
clean
```
`tools/patches.sh check`: `ok: 7 patch(es) reproduce vendor/portablekit at 8b0c3fe`. The incremental build's only
warning is the existing one at vulkan_renderer.cpp:2425 (deprecated volatile).

Open questions:
- CLAUDE.md names `tools/verify_task.sh`, but it is not in this tree, so I ran the Verify line by hand.
- `PURE_MALLOC_DEBUG` belongs in README.md's switch table, but README.md is outside May touch. It is documented in
  tools/env.sh and in the status row.
- The renderer is still torn down from a function-local static's destructor (`media()` in hle_media.cpp) during
  `exit()`, after `main` has returned and the Runtime is gone, while CoreAudio stops its queue on a dispatch thread.
  Nothing went wrong there in the four fixed runs. That order is fragile, though, and an explicit renderer
  teardown after `runtime.run()` would be the sturdier upstream change. I did not make it here.
- Builds without 0007 still abort at shutdown. A crash report at 21:57 today came from another worktree's binary
  (UUID a30916d6, not this build's DB21BCF5) and has the same `destroy_target` -> `vkFreeDescriptorSets` stack. The
  other branches get the fix when 0007 is merged.

## Review
(Fable fills)

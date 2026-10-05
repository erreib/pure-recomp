# 005: Why the frontend stops consuming movie pictures after 52 frames

Milestone: M2 | Branch: task/005-movie-consumer-stall | Status: OPEN

## Goal
The intro "SCEA presents" clip (`Data/Movies/IntroMovieP1_US.PMF`, 130 packets, 261 pictures in PPSSPP) stops
being decoded after picture 52 (1.7 s) in our port; the movie never ends, its sceMpeg instance is never deleted,
and the second movie (`Profile_part1.PMF`, after Start on the title) leaves the game on a blank profile page. Find
what stops the consumption and make the clip play to its end so the movie object is torn down like in PPSSPP.

## What is already known (read these; do not redo them)
- docs/status.md Blockers; docs/tasks/003-headless-intro-movie.md Result (the ring never drains because the game
  stops fetching AUs); docs/timing.md (frame loop).
- Traces in the main checkout: `~/dev/pure-recomp/out/m2-kc.log` (kernel + mpeg + sceAudio ch3 output, windowed),
  `out/m2-calls.log`, `out/ppsspp/boot-hle.log` (PPSSPP's sceMpeg sequence: 261 GetAvcAu for this clip, AvailableSize
  rising 382 -> 512, then AvcDecodeStop, Delete).
- Decompiles in `out/movie_all.txt` (the MovieManager range 0x08948800-0x0894A400 and the frontend caller),
  `out/movie.txt`, `out/movie2.txt`, `out/audioobj.txt`, `out/sound2.txt`, `out/callers*.txt`. Key facts:
  - `FUN_089488a8` (per-frame update, called by `FUN_088caf78` from the frontend): skips when `*(s+0)==0` (inactive)
    or `*(s+0x124)!=0` (paused); readiness `FUN_08948e14`; ends the movie when `*(s+0xd0)>0` and
    `sceMpegRingbufferAvailableSize(s+0x28)==0x200`; then audio fetch `FUN_08949068` and video fetch `FUN_089491a0`.
  - `FUN_089491a0` fetches a picture only while the queue has room: `*(s+0x118)` (capacity) - `*(s+0x120)` (count)
    - 1 >= 1. `FUN_0894900c` enqueues (count++), `FUN_08949034` dequeues (count--), called only from the picture
    getter `FUN_08948b34`, which the frontend's renderer reaches through a vtable (`FUN_088cb548` has no direct
    callers in Ghidra). One picture is consumed per getter call, no timestamps.
  - Pause/resume wrappers `FUN_088cb4d8`/`FUN_088cb4f4` are called from `FUN_0894b678`, `FUN_0894bc7c`,
    `FUN_0894cd2c`, `FUN_0894cd00` (not yet decompiled).
  - In our windowed trace the audio side (channel 3, `sceAudioOutputPannedBlocking` every 46 ms) and the video side
    stop in the same frame (t=5.797 s, picture 52) with no kernel event in between; our `sceMpegAvcDecode` writes
    the "picture produced" flag correctly (vendor/portablekit/host/hle/hle_mpeg.cpp).
- Hypotheses, in order: (a) the frontend stops calling the picture getter after a fixed time or after the first
  presents card (so the queue fills and the fetch idles); (b) the game paused the movie (`*(s+0x124)`), e.g. from a
  kernel callback or a frontend state change; (c) the getter returns early because `*(s+0x11c)` (picture array)
  is cleared.

## Deliverable
1. Prove which hypothesis holds. Tools: `tools/ghidra_headless.sh script Decompile <out> <addr>...` and
   `script Callers <out> <addr>...` (Ghidra refuses project paths under `.claude`, so run them from the main checkout
   `~/dev/pure-recomp` read-only, or copy `ghidra_project/` elsewhere); a guest-memory probe from the profile: add
   `PURE_WATCH_MOVIE=1` to `src/profile/pure_profile.cpp` that, inside the `sceDisplaySetFrameBuf` wrapper
   (`wrap_flip_counter`), reads the movie object pointer at `DAT_08ab45bc` (guest 0x08AB45BC) and prints
   `*(s+0)`, `*(s+1)`, `*(s+0x124)`, `*(s+0x118)`, `*(s+0x120)`, `*(s+0x128)`, `*(s+0xd0)` once per flip while they
   change (`rt.memory().load32/load8`). That shows per frame whether the queue is full, whether pictures are still
   consumed (`0x128` = total dequeued) and whether the pause flag was set, and at which frame.
2. The fix, smallest first: if (b) and the pause comes from a kernel callback or an HLE answer we give (UMD, power,
   memory stick, `sceKernelCheckCallback`), correct that HLE answer in `src/hle/` via `register_extra_hle` (or a vendor
   patch if the framework is wrong for every game); if (a), find the condition in the frontend code (decompile
   `FUN_088caf78`'s neighbours and the vtable owner of `FUN_088cb548`) and report what the frontend waits for; if
   (c), the same.
3. Keep `PURE_WATCH_MOVIE` as a permanent switch, documented in README.md.

## Acceptance criteria
- [ ] The windowed run `python3 tools/run_boot.py --seconds 40 --window --env PSPRECOMP_NO_INTERPRETER=1 --env PURE_TRACE_MPEG=1 out/005.log`
      shows more than 200 `sceMpegAvcDecode` lines for the first movie and a `sceMpegAvcDecodeStop` followed by
      `sceMpegDelete` (the movie ends and is torn down), without input.
- [ ] `PURE_WATCH_MOVIE=1` prints the per-frame fields and the Result explains the stop with the frame number.

## Verify
`python3 tools/run_boot.py --seconds 40 --window --env PSPRECOMP_NO_INTERPRETER=1 --env PURE_TRACE_MPEG=1 out/005.log; test "$(grep -c 'sceMpegAvcDecode(' out/005.log)" -gt 200 && grep -q 'sceMpegDelete' out/005.log`

## May touch
- src/profile/pure_profile.cpp (the watch switch and a registration call only), src/hle/ (new files), CMakeLists.txt
  (SOURCES), README.md (switch table), patches/ (only via `tools/patches.sh export`, with a README row), tools/ghidra/
  (new scripts only)

## Must not touch
- vendor/ except through a patch, vendor/portablekit/include/psprecomp/, tools/run_boot.py, tools/imgdiff.py, config/

## Estimated turns
50

## Escalate when
The stop is caused by missing input (the frontend waits for a button) or by a frontend timer that is by design, in
which case report the finding and the frame, and leave the fix to Fable; or the fix would need the kernel scheduler.

## Result
(worker fills)

## Review
(Fable fills)

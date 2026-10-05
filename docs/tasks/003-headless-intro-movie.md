# 003: Headless runs must get past the intro movie

Milestone: M2 | Branch: task/003-headless-intro-movie | Status: OPEN

## Goal
With `PURE_NO_RENDER=1 PURE_NO_AUDIO=1` the game plays its intro movie (sceMpeg, `Data/Movies/IntroMovieP1_US.PMF`
inside Data.wad) and then polls `sceMpegRingbufferAvailableSize` forever (it returns 0x1A8: 88 of 512 packets stay
filled). In a window with audio the same movie plays and the game reaches the title screen. Every automated check
in this project runs headless, so headless must reach the title screen too.

## Read first
- CLAUDE.md
- docs/status.md (Blockers: "Headless intro movie"), docs/research.md section on sceMpeg
- ~/dev/pure-recomp/out/m1-corpus-trace.log (headless trace with PURE_TRACE_MPEG: the call sequence then the loop)
- vendor/portablekit/host/hle/hle_mpeg.cpp (ringbuffer, GetAvcAu/AvcDecode, GetAtracAu/AtracDecode), and
  host/movie/avc_decoder.cpp, host/hle/hle_media.cpp (how a decoded frame reaches the display) and
  host/audio/audio_sink.cpp (what NO_AUDIO changes)
- vendor/portablekit/docs/HLE_EXTENSIONS.md (how a port overrides an HLE call without a vendor patch)

## Deliverable
Find why the packets are never consumed headless (likely: a decode or a frame hand-off is skipped when there is no
renderer or no audio sink, so the game never sees the AU it waits for, or a return code differs from the windowed
path). Then the smallest fix, in this order of preference: (1) an HLE override in `src/hle/` registered through
`register_extra_hle` in `src/profile/pure_profile.cpp` (add a `register_pure_hle_mpeg(HleRegistrar&)` in a new file
`src/hle/mpeg_pure.cpp` and call it; do not change other profile code), (2) a vendor patch exported with
`tools/patches.sh export 0002-<slug>` and a row in `patches/README.md` (only if the bug is the framework's and
affects any game; say so in the patch description). Also add `PURE_SKIP_FMV=1`: an override of the movie path that
reports the movie finished immediately (whatever the game polls for), as the stand-in the campaign sweep can use
if decoding headless is ever too slow. Document both in README.md's switch table.
Capture `PURE_TRACE_MPEG=1` logs of the windowed and the headless run before the fix and diff them; put the diff's
decisive lines in the Result.

## Acceptance criteria
- [ ] `python3 tools/run_boot.py --seconds 60 --env PSPRECOMP_NO_INTERPRETER=1 --env PURE_FRAME_LOG=100 out/003.log`
      shows frames past 1200 and no 1000-fold repeat of `sceMpegRingbufferAvailableSize` (with PURE_TRACE_MPEG=1).
- [ ] The windowed run still plays the movie (frames 120 to ~600 look like the splash/movie, title at ~1400).
- [ ] `PURE_SKIP_FMV=1` reaches the title screen earlier, headless and windowed.

## Verify
`python3 tools/run_boot.py --seconds 60 --env PSPRECOMP_NO_INTERPRETER=1 --env PURE_FRAME_LOG=100 --env PURE_TRACE_MPEG=1 out/003.log; grep -q 'frame 1200' out/003.log && ! grep -q 'x1000' out/003.log`

## May touch
- src/hle/mpeg_pure.cpp (new), src/profile/pure_profile.cpp (only the registration call and the include),
  CMakeLists.txt (adding the new source to SOURCES), README.md (switch table), vendor/portablekit/host/ only via a
  patch (see above), patches/

## Must not touch
- vendor/portablekit/include/psprecomp/, src/gpu/, tools/, config/

## Estimated turns
45

## Escalate when
The fix needs the renderer or audio sink to exist headless (then describe the dependency and stop), or the decode
itself fails on this PMF (FFmpeg error in the log).

## Result
(worker fills)

## Review
(Fable fills)

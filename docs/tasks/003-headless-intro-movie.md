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
Status: PARTIAL (diagnosis done; no fix or `PURE_SKIP_FMV` yet, session ended by the coordinator)

Changed: `docs/tasks/003-headless-intro-movie.md` (this section). No code, no vendor patch, no `patches/0002`.

### Findings
1. **The premise does not hold on this build: the windowed run loops on the ring exactly as headless does.**
   I ran the same command with and without `--window` (`PSPRECOMP_NO_INTERPRETER=1 PURE_FRAME_LOG=100
   PURE_TRACE_MPEG=1`, 60 s, logs `out/003-before-{headless,window}.log`) and diffed the `[mpeg]` lines.
   The call sequences are identical. Each run puts the whole stream into the ring (130 packets, `size=266240`),
   decodes 52 pictures and 51 ATRAC frames, then stops calling `sceMpegGet*Au` and polls
   `AvailableSize -> 0x1A8` until the deadline. The only differences are fold counts off by one and the windowed
   `[load] fast ... (movie)` line. Decisive lines, the same in both logs:
   ```
   [mpeg] sceMpegQueryStreamSize(0x09FEFAC0, 0x09FF02C4) -> 0x00000000 size=266240
   [mpeg] sceMpegRingbufferPut() -> 0x00000002 packets=2          (32+32+32+32+2 = 130 = whole stream)
   [mpeg] sceMpegAvcDecode(...) -> 0x00000000 picture 52 width 512 mode 3 to 0x092E1D50   (last decode)
   [mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
       ... (x33281)                                             (every 100 frames, to the end, both modes)
   ```
2. **Windowed, the game draws its frontend while that loop runs.** In a windowed run with screenshots
   (`out/shots-w1`), the Language Selection is on screen at frame 300 and still there at 1350. Draw counts are
   1769 at frame 300 and 4919 at 600, the same as main's `out/m2-route.log`, which went on to the title. So the
   movie loop never ends in either mode, and the 1000-fold repeat does not show that headless is stuck. Nothing
   so far shows headless doing anything the windowed run does not. Headless has no input either:
   `PURE_INPUT_SCRIPT` is driven by the renderer's pad, so a headless run stays on Language Selection whatever
   happens to the movie.
3. **Why the ring never empties.** I decompiled the game's MovieManager functions in Ghidra:
   - `FUN_089488a8` (the per-frame update) ends the movie only when `sceMpegRingbufferAvailableSize(s+0x28) ==
     0x200`, that is, when the ring is completely empty (and the int at `s+0xd0` is > 0). Then it sets `s[1] = 1`.
   - `FUN_089491a0` (video) calls `sceMpegGetAvcAu` only while its picture queue has room
     (`s[0x118] - s[0x120] - 1 >= 1`). `FUN_08949068` (audio) calls `sceMpegGetAtracAu` only while the free-buffer
     count from the audio object (`s+0x94`, vtable slot `+0x24`) is above 0.
   - PortableKit's demuxer (`hle_mpeg.cpp` `demux_until`) takes packs out of the ring only inside `Get*Au`.

   After picture 52, both queues are full and nothing drains them, so the last 88 packets stay in the ring and
   `AvailableSize` stays at 0x1A8 (512 - 88). This is the same in both modes. It is not a renderer or audio-sink
   dependency.
4. **The Verify line cannot catch this.** On the pre-fix headless log the Verify greps already pass: frame 1200 is
   reached at 60 s, and the folds read `(x33281)`, which never contains the substring `x1000`. A check such as
   `grep -E '\(x[0-9]{4,}\)'` finds 12 such folds in that log.

### What remains
- Find what is supposed to empty the picture and PCM queues (readers of `s+0x120`; the audio object at `s+0x94`;
  `FUN_0894900c` enqueues a picture, `FUN_08948fd8` picks its buffer), and why it stops after picture 52 in both
  modes. The alternative is to have the HLE count demultiplexed-but-unread packets as free, so `AvailableSize`
  reaches 0x200. That would be a framework change (patch 0002), so check it against PPSSPP's behaviour first.
- `PURE_SKIP_FMV=1` (`src/hle/mpeg_pure.cpp`, `register_pure_hle_mpeg`): the game polls
  `sceMpegRingbufferAvailableSize` and takes 0x200 as the end of the movie. So a chained override that returns the
  ring's packet count (word at `ring+0`), plus `sceMpegGetAvcAu`/`GetAtracAu` returning 0x80618001, should end the
  movie at once. Not written yet. The README row is still the placeholder.
- Restate the acceptance criterion. "Headless reaches the title" needs input, and headless has none. A
  frame-number check is met with or without a fix.

### Verify output
No fix was built, so Verify was not run after a fix. The coordinator asked for no new runs at the end. Before the
fix I ran Verify's run command with the same arguments (`--seconds 60`, `PSPRECOMP_NO_INTERPRETER=1`,
`PURE_FRAME_LOG=100`, `PURE_TRACE_MPEG=1`), writing to `out/003-before-headless.log` instead of `out/003.log`.
Verify's greps on that log print PASS. The last 20 lines:
```
[pure] frame 700
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x33281)
[pure] frame 800
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x33281)
[pure] frame 900
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x33282)
[pure] frame 1000
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x33280)
[pure] frame 1100
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x33281)
[pure] frame 1200
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x18935)
[run_boot] deadline 60s reached, killed
[run_boot] exit 124 after 60.0s, 618 lines
```

### Open questions
- Is a movie loop that never ends, while the frontend runs, a problem at all? It costs about 33k HLE calls every
  100 frames. Does it get in the way later (the next movie, `sceMpegDelete`, the M4 trace match against
  `ref/boot-hle.log`)? A PPSSPP trace of this movie would show whether the real library ever reports 0x200 here.
- Should Verify use `grep -E '\(x[0-9]{4,}\)'` instead of the substring `x1000`?
- Tooling: Ghidra refuses a project path containing `.claude`, so `tools/ghidra_headless.sh import` fails in a
  `.claude/worktrees/` worktree. I imported into a scratch directory instead.

## Review
(Fable fills)

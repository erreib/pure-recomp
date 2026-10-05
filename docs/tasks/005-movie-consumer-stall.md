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
Status: BLOCKED (the escalation condition holds: the stop after picture 52 is the Language Selection page waiting
for Cross, by design, and PPSSPP stops at the same picture. A second, real bug shows up once the language is
confirmed; it is diagnosed below and left to Fable, as the brief asks.)

Changed:
- `src/profile/pure_profile.cpp`: `PURE_WATCH_MOVIE=1` (`watch_movie()`, called from `wrap_flip_counter`).
- `README.md`: the switch row.
- `docs/tasks/005-movie-consumer-stall.md`: this section.
- No HLE override, no vendor patch.

### Finding 1: hypothesis (b). The Language Selection page pauses the movie and waits for a button
The watch, windowed, no input (`out/005-watch1.log` in the worktree):
```
[pure] movie frame 129 t=4170750 s=0x08EA4A2C active=1 ended=0 paused=0 reader=1 cap=4 queued=1 shown=0 ...
[pure] movie frame 179 t=5839050 s=0x08EA4A2C active=1 ended=0 paused=0 reader=1 cap=4 queued=1 shown=50 ...
[pure] movie frame 180 t=5872416 s=0x08EA4A2C active=1 ended=0 paused=1 reader=1 cap=4 queued=1 shown=51 ...
```
After that the line never changes up to the deadline (frame 1140+). From flip 130 to flip 179 the game consumed
exactly one picture per flip. At **flip 180 (t=5.872 s, shown=51)** the pause byte `+0x124` is set. Once it is set,
`FUN_089488a8` returns before any fetch, and the getter `FUN_08948b34` hands out the current picture without
dequeuing it. `FUN_08948994` also sets the audio object's flags (`+0xb4`, `+0xe8`), which is why audio and video
stop in the same frame. Hypotheses (a) and (c) do not hold: consumption ran right up to the pause, and the picture
array (`+0x11c` = 0x08B51AB0) stays set.

Who pauses: I decompiled the four callers of the pause and resume wrappers (`out/pausers2.txt`, `out/pausers3.txt`
in the worktree; vtable pointers found by searching BOOT.BIN for the function addresses):
- `FUN_0894cd2c` (pointer at 0x08AC3230) is the Language Selection page's per-frame update. When the movie's shown
  count equals 0x33 (51) and its own flag `+0xf0` is clear, it pauses the movie (`FUN_088cb4d8`). Then
  `FUN_0894ce18` makes `LanguageText`, `ControlTextConfirmButton` and `ControlTextConfirm` visible, and the page
  drives its `Language` list. The count comes from `FUN_088cb510`, which returns widget+0x1c4, that is movie+0x128.
- The only resume for that pause is `FUN_0894cd00`, in the same vtable (pointer at 0x08AC3280). It runs the base
  page's close handler `FUN_088b5d20` and then `FUN_088cb4f4` (resume). So the movie resumes when the page is left
  after a language is confirmed.
- Proof with input (`PURE_INPUT_SCRIPT=700:pad a`, `out/005-input1.log`): `[script] frame 700: pad a`, then
  `movie frame 701 ... paused=0 ... shown=51`, and consumption goes on.
- PPSSPP does the same. In `out/ppsspp/boot-hle.log`, the 52nd `sceMpegAvcDecode` is at 07:45:703. Then come 124
  flips with no sceMpeg call until 07:49:841. That capture pressed CROSS at frame 700 (`docs/ppsspp.md`).

So without input the first movie cannot end, in PPSSPP as here. A faithful fix cannot meet the acceptance
criterion's "without input". The criterion needs the language confirm (or a skip switch).

The other pausers, for reference:
- `FUN_0894b678` (pointer at 0x08AC2EC0) is the intro page's update. It pauses at shown 0x90 (144) and 0xE7 (231)
  and resumes after 2.0 s of the frontend clock (`*(DAT_08b17c18+0x44)`). At shown 0x104 (260) it starts a 2 s end
  hold, then resumes and closes (`FUN_088ceca4` on `+0xe4`). These timers work in our port: pauses at flips 794 and
  941, resumes at 854 and 1001 (60 flips, 2.0 s). PPSSPP's gaps are 2.036 s and 2.033 s after pictures 145 and 232.
- `FUN_0894bc7c` (pointer at 0x08AC3020) pauses when the shown count equals the page's XML value `FMVFrameCount`
  and never resumes on its own. This is probably the profile page that holds the last frame of
  `Profile_part1.PMF` under its Load/New/Delete menu.

### Finding 2 (with input): the ring reads empty 16 pictures early, so the movie is never torn down
With `700:pad a` the movie plays on, then stops at flip 1015:
```
[pure] movie frame 1014 t=33699660 ... ended=0 paused=0 reader=1 cap=4 queued=1 shown=244 ...
[pure] movie frame 1015 t=33733026 ... ended=1 paused=0 reader=1 cap=4 queued=0 shown=245 ...
```
The run has 245 `sceMpegAvcDecode` lines, no `sceMpegAvcDecodeStop` and no `sceMpegDelete`.
`sceMpegRingbufferAvailableSize` returns 0x200 from then on to the 60 s deadline (frame 1800+). PPSSPP decodes
261 pictures: AvailableSize is 510 after picture 260 and 512 after 261, `AvcDecodeStop` follows 2.0 s later, then
`Delete`. Our last video AU has pts=822732. The header's last timestamp (PPSSPP: "Last timestamp: 870780") is
48048 = 16 x 3003 later, so 16 pictures are still queued in the framework's demuxer when the ring reads empty.

Cause, in `vendor/portablekit/host/hle/hle_mpeg.cpp`:
- `demux_until` returns a pack to the ring (`kFilled - 1`) as soon as it is demultiplexed.
- `sceMpegRingbufferAvailableSize` returns `packets - filled`.
- The game fetches ATRAC AUs about 0.5 s of stream time ahead of video (at the end: ATRAC pts 871581 against video
  822732). So the `GetAtracAu` calls pull the last packs out of the ring, and with them the last 16 video AUs.

The game then reacts as follows:
- `FUN_089488a8` tests `AvailableSize == 0x200` before it fetches video. It sets `ended` and stops fetching.
- `FUN_0894b678` waits for shown == 0x104 (260) to start its end hold. At 245 pictures it never gets there.
- So the teardown `FUN_089492c0` (`AvcDecodeStop` ... `sceMpegDelete`) never runs. Its callers are `FUN_088caf78`,
  `FUN_088cb4bc` and `FUN_08899784`; which one PPSSPP takes is not checked.

Suggested fix (not done, per the escalation rule):
- Patch 0002 in `hle_mpeg.cpp`: `AvailableSize` must not report the ring empty while the demuxer still holds AUs
  from its packs. Either count a demultiplexed pack as filled until its AUs are taken, or cap the free count at
  `packets - 1` while `video_ready()`/`audio_ready()` holds for the instance whose `ringbuffer` is this ring.
- It belongs in the framework: any game that ends a movie on an empty ring is affected.
- An override in `src/hle/` cannot see the demuxer queues. It would have to compare the last delivered video pts
  with the header's last timestamp.
- Likely the same cause as the profile-screen blocker: if `Profile_part1.PMF` also loses its last pictures,
  `FUN_0894bc7c` never reaches `FMVFrameCount`, never pauses, and never shows its menu. Not tested.

### Verify output
The Verify command fails as expected: `test` exits 1 with 52 `sceMpegAvcDecode(` lines and no `sceMpegDelete`.
The last 20 lines of `out/005.log`:
```
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x332)
[mpeg] sceMpegGetAtracAu(0x08EA4A80, 0x09125110, 0x08EA4AA8, 0x09FF0260) -> 0x00000000 pts=269721
[mpeg] sceMpegAtracDecode(0x08EA4A80, 0x08EA4AA8, 0x0913BAC0, 0x00000000) -> 0x00000000
[mpeg] sceMpegGetAvcAu(0x08EA4A80, 0x09125100, 0x08EA4A90, 0x09FF0264) -> 0x00000000 pts=237147 size=75
[mpeg] sceMpegAvcDecode(0x08EA4A80, 0x08EA4A90, 0x00000200, 0x09FF0260, 0x09FF0268) -> 0x00000000 picture 50 width 512 mode 3 to 0x091D1D10
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x330)
[mpeg] sceMpegGetAtracAu(0x08EA4A80, 0x09125110, 0x08EA4AA8, 0x09FF0260) -> 0x00000000 pts=273900
[mpeg] sceMpegAtracDecode(0x08EA4A80, 0x08EA4AA8, 0x0913DB40, 0x00000000) -> 0x00000000
[mpeg] sceMpegGetAvcAu(0x08EA4A80, 0x09125100, 0x08EA4A90, 0x09FF0264) -> 0x00000000 pts=240150 size=75
[mpeg] sceMpegAvcDecode(0x08EA4A80, 0x08EA4A90, 0x00000200, 0x09FF0260, 0x09FF0268) -> 0x00000000 picture 51 width 512 mode 3 to 0x09259D30
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x335)
[mpeg] sceMpegGetAvcAu(0x08EA4A80, 0x09125100, 0x08EA4A90, 0x09FF0264) -> 0x00000000 pts=243153 size=89
[mpeg] sceMpegAvcDecode(0x08EA4A80, 0x08EA4A90, 0x00000200, 0x09FF0260, 0x09FF0268) -> 0x00000000 picture 52 width 512 mode 3 to 0x092E1D50
[mpeg] sceMpegRingbufferAvailableSize(0x08EA4A54) -> 0x000001A8
    ... (x341673)
[run_boot] deadline 40s reached, killed
[run_boot] exit 124 after 40.0s, 599 lines
```

### Open questions
- How should the criterion change? A version that holds once finding 2 is fixed: run windowed with
  `--env PURE_INPUT_SCRIPT=700:pad a` and `--seconds 60`. The movie should then end near flip 1030 and tear down
  about 60 flips later. The alternative is `PURE_SKIP_FMV` (task 003).
- Fix finding 2 as vendor patch 0002 (my recommendation), or with a pts-based override in `src/hle/`?
- Is the 341673-fold `AvailableSize` poll from the readThread (100 µs `sceKernelDelayThreadCB` loop in
  `FUN_08949904`) worth throttling while the movie is paused? It is guest behaviour, so I left it alone.

## Review
(Fable fills)

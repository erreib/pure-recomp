# 013: Audio capture and checks (M4)

Milestone: M4 | Branch: task/013-audio-checks | Status: OPEN

## Goal
Music (ATRAC3+ through the framework's FFmpeg build), sound effects (sceSas) and movie audio play, but nothing
measures them. Add a WAV capture of what the game hands to sceAudio, a stats tool, and the M4 checks: music plays
continuously through the frontend (loop boundary included), the race has effects, and the mixed output is not
clipping or dropping.

## Read first
- CLAUDE.md, docs/status.md, src/profile/pure_profile.cpp (the `PURE_TRACE_CALLS` wrapper shows how to wrap a bound
  HLE call and read guest memory), vendor/portablekit/host/hle/hle_media.cpp (audio_output: channel, frames per
  call, format 0x10 mono, the sample rate constant), config/pad_scripts/frontend.txt and main_menu.txt,
  ~/dev/pure-recomp/out/race/route.txt, ~/dev/bouncer-recomp/tools/wavstats.py (shape to copy)

## Deliverable
1. `PURE_AUDIO_WAV=<file>`: in the profile (`src/hle/audio_capture.cpp`, registered from `register_pure_hle`), wrap
   `sceAudioOutputPannedBlocking`, `sceAudioOutputBlocking` and `sceAudioOutputPanned` and append each submitted
   buffer, converted to stereo 16-bit 44.1 kHz with the call's volumes applied, to one WAV per channel
   (`<file>.ch<N>.wav`) and a mixed `<file>` (sum, clipped). Virtual-time placement is not required: append in call
   order (the blocking calls pace the channel).
2. `tools/wavstats.py <wav> [--from S] [--min-active-frac F] [--max-clip-frac C]`: per-second RMS and peak, fraction
   of seconds with RMS above a silence floor, clipping fraction, PASS/FAIL.
3. Checks, run and recorded in the Result: (a) frontend route to the main menu with music: active fraction ≥ 0.9
   after the language confirm, no clipping; (b) a loop boundary: the frontend music loops within ~3 minutes; the
   stats must show no silent second at the boundary; (c) race route with the throttle held for 1500 frames: the
   mixed track has effects (peaks above the music's RMS) and the engine channel is continuous.

## Acceptance criteria
- [ ] `python3 tools/run_boot.py --script config/pad_scripts/main_menu.txt --frames 4700 --env PURE_AUDIO_WAV=out/013/menu.wav out/013/menu.log`
      then `python3 tools/wavstats.py out/013/menu.wav --from 15 --min-active-frac 0.9 --max-clip-frac 0.001` passes.
- [ ] The race capture's stats are in the Result with the effects observation.

## Verify
`python3 tools/wavstats.py out/013/menu.wav --from 15 --min-active-frac 0.9 --max-clip-frac 0.001`

## May touch
- src/hle/audio_capture.cpp (new), src/profile/pure_profile.cpp (registration + include only), CMakeLists.txt
  (SOURCES), tools/wavstats.py, README.md (switch row), docs/verification.md (audio section)

## Must not touch
- vendor/, patches/, tools/run_boot.py, config/

## Estimated turns
35

## Escalate when
The audio calls do not go through the HLE wrapper (the framework's sink is reached another way); report where.

## Result

**Status: PARTIAL.** The capture, the stats tool and all three checks are done. The music, loop-boundary and race
checks pass. The brief's Verify command fails, and the cause is the brief's premise, not the audio: the game plays no
music between the language confirm and the main menu (PPSSPP shows the same). Verify needs a new `--from`; see Open
questions.

**Changed**
- `src/hle/audio_capture.cpp` (new): `PURE_AUDIO_WAV=<file>`. It wraps the bound `sceAudioOutputPannedBlocking`,
  `sceAudioOutputBlocking` and `sceAudioOutputPanned`, and also `sceAudioChReserve`, `sceAudioSetChannelDataLen` and
  `sceAudioChangeChannelConfig`, because the framework keeps each channel's format and length to itself. Format bit
  0x10 means mono, and the frame count comes from the channel's data length. Each buffer is written as stereo s16
  44.1 kHz with the volumes applied the way the sink does it (`min(vol, 0x8000)`, `>> 15`), to `<file>.ch<N>.wav` and
  to a clipped mix `<file>`.
  - Every file runs on virtual time: a buffer starts where the channel's last one ended, or "now" if it came late, and
    any gap is written as zeros. So within a channel the order is still call order.
  - Gaps under 2 s are logged as underruns, and the exit line gives the count per channel.
  - WAV headers are rewritten after every write.
- `src/profile/pure_profile.cpp` (one declaration plus the call in `register_pure_hle`), `CMakeLists.txt` (SOURCES).
- `tools/wavstats.py` (new):
  - per-second RMS and peak
  - active fraction above `--floor` (default 100)
  - silent seconds and the longest silent run
  - clipping fraction
  - zero runs ≥ `--gap-ms` (default 50), which catch dropouts shorter than a second
  - `--from`/`--to` and PASS/FAIL limits
  
  It runs in about 0.9 s on a 157 s file.
- `README.md` (switch row), `docs/verification.md` (Audio section: capture, channel table, tool, check results).

**Escalation: not triggered.** The only way into the framework's sink is `audio_output` in `hle_media.cpp`. It is
reached from the three output calls this game imports (Output2 is not imported), so the wrapper sees every buffer. I
cross-checked against the framework's `PURE_AUDIO_DUMP` on the loop run: the capture matches it bit for bit (exact
16-frame matches at 146.5 s and 175.5 s, with the dump 0.816 s earlier because the sink drops fast-load silence), and
total energy agrees within 0.3%.

**Channels** (all stereo):

| Channel | Frames per call | Carries |
|---|---|---|
| ch1 | 768 | sceSas: UI, engine, effects, speech |
| ch2 | 2944 | sceAtrac music |
| ch3 | 2048 | sceMpeg movie audio |

**The frontend flips at 30 per second** (the race at 60), so route flip N is at about N/30 s there. The language
confirm at flip 700 is at 23.3 s, which puts the brief's `--from 15` before it.

**(a) Frontend.** I ran the acceptance command as written: `menu.wav` is 157.5 s, with no clipping anywhere.
- The music starts at t=145.48 s (flip ~4370). `sceAtracSetDataAndGetID` is called right after the profile save, and
  it is the game's first music track.
- PPSSPP's `ref/boot-hle.log` shows the same: its only ATRAC context is created at 32:24.000, about vblank 5400,
  between the WARNING confirm (5250) and the main menu (5643).
- Before that the game plays only movie audio (ch3) and UI blips (ch1). Measured from 15 s, that gives active 0.2535,
  so Verify fails.
- From the music start, `wavstats out/013/menu.wav --from 146 --min-active-frac 0.9 --max-clip-frac 0.001` PASSES:
  11/11 seconds, no clipping, 0 zero runs.
- ch3 has two gaps of ~1.9 s inside the clip that plays after the language confirm (t=28.3 s and 33.2 s, logged as
  underruns). PPSSPP's `sceMpegAtracDecode` per-second counts stop for a second at the same points of that clip
  (16 s and 21 s wall), so the gaps look like the game's own.

**(b) Loop boundary.**
- The frontend track is 1,764,236 samples (40.0 s) and loops the whole track forever (`SetLoopNum -1`).
- Left idle on the main menu, the attract demo takes over about 30 s after the music starts and releases it before the
  loop point. So `out/013/loop.txt` presses DOWN/UP every 300 flips (`--frames 7700`, plus `PURE_TRACE_ATRAC`).
- The ATRAC trace shows `at=1762188 count=2048 next=0` twice. The music repeats bit for bit at +1,764,236 frames, with
  boundaries at 185.49 s and 225.49 s.
- From 146 to 257.6 s, both ch2 and the mix: active 111/111, no silent second, 0 zero runs ≥ 50 ms, clipping 0. PASS.
- Mix RMS for 182-189 s: 2346 2570 2361 1793 1449 1220 1300 1142. The same values recur at the next boundary
  (222-229 s).
- A third boundary, at 198.83 s in the race rerun, is also seamless.

**(c) Race** (`out/013/race.txt`: `out/race/route.txt` plus `6100:pad a 1500`, `--frames 7700`,
`PURE_WATCH_SHIP=1`)
- The race clock starts at t=209.05 s (flip ~6325). The ship reaches 327 km/h, hits the wall at the first right-hander
  (~215 s) and sits against it under throttle until 230.3 s (flip 7600). The run ends at 232.0 s.

Window 209-232 s:

| File | Active | Clipping | RMS (median) | Peak |
|---|---|---|---|---|
| mix | 23/23 | 0 | 1507-3887 (2393) | 9417-20091 |
| ch1 effects | 23/23 | 0 | 914-3618 (2185) | 4377-20077 |
| ch2 race music | 23/23 | 0 | 592-1907 (1106) | 5775-9729 |

- **Effects are present:** effects RMS is above music RMS in 22 of 23 seconds, and the mix peak is 6.3 to 18.4 times
  the music RMS in every second.
- **Engine channel is continuous:** ch1 has 0 underruns over the whole run and 0 zero runs ≥ 50 ms in the race.
- ch2 is silent from 204.2 s to 209.0 s, between the race load and GO. That is by design: the race music starts at GO.

**Verify output** (`python3 tools/wavstats.py out/013/menu.wav --from 15 --min-active-frac 0.9 --max-clip-frac 0.001`,
exit 1, last 20 lines):
```
   144.0 s  rms     883  peak  5940  clip     0  #####
   145.0 s  rms    1280  peak 11019  clip     0  ########
   146.0 s  rms    1553  peak 10206  clip     0  ##########
   147.0 s  rms    1198  peak 10455  clip     0  #######
   148.0 s  rms    1283  peak 10290  clip     0  ########
   149.0 s  rms    1139  peak  9654  clip     0  #######
   150.0 s  rms    1259  peak 10813  clip     0  ########
   151.0 s  rms    1121  peak 10812  clip     0  #######
   152.0 s  rms    1270  peak 10742  clip     0  ########
   153.0 s  rms    1176  peak 10552  clip     0  #######
   154.0 s  rms    1333  peak 10458  clip     0  ########
   155.0 s  rms    1314  peak 10812  clip     0  ########
   156.0 s  rms    1569  peak 10812  clip     0  ##########
   157.0 s  rms    1713  peak 10812  clip     0  (0.53 s)  ###########
window 15.0 .. 157.5 s: 142 whole seconds, floor rms 100
silent seconds: 106 (at 15, 16, 17, 18, 19, 20, 21, 22, 27, 28, 31, 32, 34, 35, 37, 38, 39, 40, 41, 42, ...)
longest silent run: 17 s from 73 s
zero runs >= 50 ms: 32, longest 16937 ms (26.381 s 1947 ms, 31.210 s 2042 ms, 33.733 s 429 ms, 34.198 s 2035 ms, 36.345 s 16937 ms, 55.066 s 5356 ms, 62.085 s 269 ms, 62.720 s 7871 ms, 70.662 s 1272 ms, 72.046 s 5233 ms, ...)
active fraction 0.2535 (36/142), clipping fraction 0.000000 (0/12571240 samples)
FAIL (active >= 0.9, clip <= 0.001)
```

**Open questions**
1. **The Verify line needs a new premise.** Proposed: the same capture command, then
   `python3 tools/wavstats.py out/013/menu.wav --from 146 --min-active-frac 0.9 --max-clip-frac 0.001`, which passes
   (music from the main menu on). Measuring "after the language confirm" would mean `--from 24`, and that cannot pass
   because the game is silent there. Should the status.md M4 exit ("active 90% after countdown") be pointed at the
   race window? `--from 209 --to 232` passes at 1.0.
2. **Music-feed dropouts seen once each, not reproduced:**
   - first race run: 7,547 zero frames (171 ms) at 183.9 s, just after the TRACK SELECTION confirm (flip 5500). The
     music then repeated at +1,771,742 frames instead of +1,764,236, so the zeros were inserted, not skipped.
   - idle main-menu run: 8,902 zero frames (202 ms) at 164.1 s.

   Both runs came before the underrun log. Each run of zeros begins inside a buffer the game submitted, so it is the
   game's own music feed starving under load, not a late output call. The reruns logged 0 music underruns and 0 zero
   runs. Worth a follow-up if the zero-run report shows it again (the sound thread scheduled against the loader).
3. Movie-audio content (the ch3 gaps) is judged only against PPSSPP's decode counts. A PPSSPP WAV dump of the same
   route would settle it.
4. Runs are not deterministic in time: the race rerun reached the main menu 13 s later (music at 158.8 s instead of
   145.5 s; it ran alongside the menu rerun on the same `game/ms0`). Read stats windows off the capture's own log
   lines (`from t=`) or the ship trace, not from flip numbers.

Captures (not committed): `out/013/{menu,loop,race,attract-loop}.wav*` with their logs, the scripts `loop.txt` and
`race.txt`, and `loop.sinkdump.wav`.

## Review
(Fable fills)

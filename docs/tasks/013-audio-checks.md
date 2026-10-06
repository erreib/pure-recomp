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
(worker fills)

## Review
(Fable fills)

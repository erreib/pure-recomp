# 041: The hitches, the music gaps and the demo's clipping: checked against PPSSPP (fidelity differences 7, 8, 9)

Milestone: M8 | Branch: task/041-hitches-and-audio-checks | Status: OPEN (run alone on the machine)

## Goal
Three findings of the audit are "to check": the game freezing 0.1 to 0.3 s now and then with a gap in the sound (12
of 46 cells, at no fixed place), the race music stopping about 2 s when it changes tracks at 5:24 of the race music
and 3.9 s at Free Play's finish, and the attract demo's sound clipping. Each is either the game's own behaviour
(PPSSPP does the same) or the port's. This task settles each with PPSSPP's audio dump and an idle-machine run, and
fixes what is the port's if it is small, or reports it as a task.

## Read first
- CLAUDE.md, docs/fidelity.md (differences 7, 8 and 9, their evidence, the hitches column of the matrix, the
  `out/fidelity-hitch/` note), docs/tasks/033 (Result: `PURE_METAL_TRACE`, `tools/frame_times.py`, the long-frame
  causes), docs/ppsspp.md (the driver; how to run a route with PPSSPP's audio dump, `DumpAudio` in its settings or
  the driver's option: read the driver), tools/wavstats.py, docs/tasks/013 (the WAV capture: `PURE_AUDIO_WAV`)
- src/hle/audio_capture.cpp (the capture's channels and underrun lines), vendor/portablekit/host/audio/ (the sink,
  the SAS mix; what "underrun" means in the log), host/hle/hle_atrac.cpp (how a new music track is fed)

## Deliverable
1. Hitches (7): a player-like run, the Metal shell in a window, no probe lines, no WAV capture, nothing else on the
   machine, with `PURE_METAL_TRACE`: the Vineta K race through the sweep (`--shell metal`, `--no-damage`) twice, and
   `tools/frame_times.py` on each. If frames over 100 ms appear, their columns say where (the trace names the host's
   waits, the backend's work, and `other_ms` for the game and the HLE); then the same run with `PURE_AUDIO_WAV` and
   with the probe lines back, to show which of the three makes them. Fix it if it is the port's and small (a wait that
   can be moved, a buffer that can grow); otherwise the finding goes to docs/fidelity.md with the numbers.
2. Music gaps (8): PPSSPP's audio dump of a long race (the route that reaches 5:30 of race music) and of a Free Play
   finish, against the port's WAV of the same routes (`tools/wavstats.py` per second, and the sample-level gap at
   the track change and the finish): the same gaps mean the game's own; a gap only in the port means the HLE's ATRAC
   feeding (then say which call sequence differs, with `PURE_TRACE_ATRAC`).
3. Demo clipping (9): PPSSPP's audio dump of the attract demo (the main menu left for 30 s) against the port's: the
   peak levels and the clipped-sample counts side by side; if only the port clips, the SAS mix level in the framework
   is the suspect (report the level and what PPSSPP's output implies; a one-line patch if it is a constant).
4. docs/fidelity.md: the three rows resolved (faithful, fixed, or a task with evidence); docs/verification.md if a
   check becomes repeatable (an audio comparison script under tools/ is welcome: `tools/audio_compare.py A.wav B.wav
   --from S` printing per-second activity and the longest silences of each).

## Acceptance criteria
- [ ] Each of the three has a verdict with evidence in docs/fidelity.md: the same in PPSSPP, or the port's with the
      cause named (and fixed, or a task).
- [ ] If a fix is made: `tools/frame_regress.sh` unchanged and `tools/wavstats.py` on the Vineta K race unchanged
      (active 12/12 from the race start, no clipping).

## Verify
`python3 tools/audio_compare.py --selftest && tools/frame_regress.sh --only race_hud`

(`--selftest` checks the tool on two generated WAVs; the comparisons themselves are reported in docs/fidelity.md.)

## May touch
- tools/audio_compare.py (new), tools/ppsspp/routes/ (audio-dump routes), tools/ppsspp/ (the driver: an audio-dump
  option if it has none, with its docs/ppsspp.md row), docs/fidelity.md (differences 7 to 9),
  docs/verification.md; for a small fix: src/hle/audio_capture.cpp, or a vendor patch to host/audio/ or host/hle/hle_atrac.cpp
  via `tools/patches.sh export 0018-<cause>` with its patches/README.md row

## Must not touch
- vendor/portablekit/include/psprecomp/, host/gpu/, host/kernel/, src/gpu/, src/host/, src/profile/, tools/frame_regress.sh,
  tools/campaign_sweep.py, config/, ref/

## Estimated turns
50

## Escalate when
PPSSPP's audio dump cannot be taken through the driver (report what the driver offers and what the settings file
needs; the comparison then waits), or the hitches appear only with the sweep's probe lines (report: that is the
test harness, and the finding closes as not the port's).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

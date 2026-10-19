# 098: The audio sink keeps a late producer's content (task 081's fork b+)

Milestone: E8 (the display rate; the rig's 100 Hz skips) | Branch: batch/m2 (the planning session, docs/approach.md
rule 1: one vendor file, under 100 lines) | Status: PARTIAL (built and headless-checked 2026-10-19; the window probe
and the rig's run are owed)

## Goal
After a dip the sink no longer inserts 46 ms of silence into a continuous channel. A producer that fell briefly
behind keeps its content, loses only the frames the device already played, and regains its lead inaudibly: the SDL
stream runs 1% slow for about 4.6 s. Task 081's analysis stands: a producer below real time for longer than the
limit still snaps, because its deficit has to surface somewhere. D-023 records the choice.

## Read first
- docs/tasks/081-audio-sink-grace.md, Result and Review (the mechanism, the near-mute of rule (b) alone, the fork).
- docs/timing.md, "On the rig's 100 Hz display" (the early-race skips this is for).
- patches/README.md, 0024-audio-resync-counter and 0031-audio-sink-late-writes.

## Deliverable
- `patches/0031-audio-sink-late-writes.patch` (host/audio/audio_sink.cpp only): `kLateLimit` 2048, `kRecoveryRatio`
  0.99, `kRecoveryFrames` 204800; the late branch beside the stall branch in `mix`; `recover_until` and `ratio` in
  `Impl`; the ratio applied with `SDL_SetAudioStreamFrequencyRatio` after the sink's lock is released (the device
  callback holds the stream's lock while it takes the sink's); `lates=`, `late=` and `ratio=` on the `[audio]` line
  after `lead=` (the readers match `resyncs=` by name), `lates=` and `late=` in the shutdown total;
  `<PREFIX>_AUDIO_SNAP=1` for the old rule.
- Rows: patches/README.md (row and section), docs/upstream.md, docs/vendor-map.md, docs/developing.md
  (`PURE_AUDIO_SNAP`), docs/timing.md, docs/decisions.md D-023, docs/status.md, task 097's row 7.

## Verify
`PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio && PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan && PURE_TRACE_AUDIO=1 PURE_AUDIO_SNAP=1 tools/display_rate_check.sh --audio`

A window check (task 097, row 7). Pass: the check PASSes under both rules; over the race the new rule's `[audio]`
lines show `resyncs=0`, the dips as `lates=` with `ratio=0.990` seconds after them, `silent=0`; the old rule's show
the resyncs the dips used to cost. Then the rig at 100 Hz (097, the rig's step 4), where the 2026-10-15 run FAILed on
3 to 4 early-race resyncs: with the new rule none, and the race by ear.

## Result
Status: PARTIAL. The patch is in batch/m2 (`tools/patches.sh check`: 30), the build clean, the headless suite
18/18. The window probe ran on the Mac in task 097's batch (its Result, finding 3): PASS under both rules with the
same `[audio]` figures to the frame (`lates=0`, `ratio=1.000`, 20 channel-restart resyncs), because the Mac never
runs a channel late at 119.4 Hz. The dip regime the patch is for is the rig's: task 097, the rig's step 4 (Erik).

What ran (2026-10-19, out/098/):
- `tools/frame_regress.sh`: PASS, 18/18 (sound off there; nothing moved).
- A 40 s unpaced headless run with no device (`trace.log`): the new fields print; the self-draining ring sits at a
  lead of exactly 2048, so after the start-up second (`resyncs=2 lates=19 late=5632`, channels starting at cursor 0
  behind a read position already advanced) every second reads `lates=0 late=0 ratio=1.000`.
- Two 50 s paced boots with the device (`run_boot.py --sound --env PURE_PACED_FROM=1`), new rule (`paced_new.log`)
  and `PURE_AUDIO_SNAP=1` (`paced_snap.log`): 48 audio seconds each, `resyncs=2` each (the two channel starts),
  `lates=0`, `ratio=1.000` throughout, lead 3072 to 4352. The frontend never runs late, so the two rules agree
  there; they differ only in the race under dips, which the window probe measures.

Changed: vendor/portablekit/host/audio/audio_sink.cpp (as patch 0031), patches/README.md, docs/upstream.md,
docs/vendor-map.md, docs/developing.md, docs/timing.md, docs/decisions.md (D-023), docs/status.md,
docs/tasks/097-screen-batch.md, this file.

Open questions:
- The 512-frame threshold that armed the old jump now arms a recovery on a write that would have played in time
  (task 081's second question). Harmless (a 1% slowdown for 4.6 s), but if the probe shows `lates=` every second in
  a clean race, the arming threshold should drop to cursors strictly behind `read_position`.
- Whether 1% for 4.6 s is the right pair. A larger ratio rebuilds faster and is more audible; the probe's `ratio=`
  seconds say how long recoveries last in practice.
- The counter's readers (`purelib.logs.audio_resyncs`) read `resyncs=` only; `lates=` has no reader yet. Add one
  when the probe's verdict wants it.

## The rig's run (2026-10-19, task 500)
Measured in docs/tasks/500-rig-batch.md (its Result's step 8 table and reading 1, the Follow-up, and the clean run):
the probe PASSes at 100 Hz under the new rule once channel restarts are counted apart and the machine is quiet
(1 resync, the load's; 1 restart; no second under 95%). The dip at race second 4 took two shapes across the runs:
clean when the load's late writes armed the ratio early (the 512-frame threshold, open question 1 here), or 19961
frames of silence in 84 pieces when the lead drained to zero first. Open questions 1 and 2 are the next sink task.

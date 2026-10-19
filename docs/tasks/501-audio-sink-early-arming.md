# 501: The sink arms its recovery before the lead is gone (the rig's early-race shape)

Milestone: E8 (the rig's 100 Hz sound) | Branch: task/501-audio-sink-early-arming from batch/m2 | Status: OPEN (the rig:
the planning session, or a worker with the screen booked; docs/approach.md rule 1 says this size is the session's)

## Goal
Task 098's sink no longer has two shapes on the rig. Task 500 measured the race's 4th second at 100 Hz five times
under the new rule: three runs were clean because the race load's late writes happened to arm the 1% recovery at
once (the lead rebuilt to 3000 or more before the dip), and one run let the lead drain to 0 first, after which every
write for 2 s was behind the device and the device played the deficit as silence, 19961 frames in 84 pieces (a buzz),
ten times the old rule's one 2064-frame jump. Which shape a run got depended on where the load's snap left the lead
(777 against 2273 frames) and on nothing the sink controls. After this task the recovery arms as soon as a producer
is under its two-buffer lead, so the load's landing always starts it, and the no-device trace stays quiet.

## Read first (about 25K tokens)
- docs/tasks/500-rig-batch.md: Result's step 8 table and the `lead=` paragraph, reading 1, the Follow-up's two runs,
  and "The clean run" (the five runs' figures; the probe's restart classification is already merged).
- docs/tasks/098-audio-sink-late-writes.md: Result (the headless figures: the self-draining ring sits at a lead of
  exactly 2048) and the open questions 1 and 2.
- patches/README.md, the 0031-audio-sink-late-writes section (the rule as written, and why the ratio is applied
  outside the lock); docs/decisions.md D-023 (the fork and the consequences it claims).
- tools/patches.sh header: `open` and `close`, the workflow for editing a patch in the middle of the series.
- vendor/portablekit/host/audio/audio_sink.cpp, `AudioSink::mix` and the constants above it (about 120 lines).

## The facts the change rests on
- The sink's constants: `kRingFrames` 8192, `kPrebufferFrames` 2048 (the device "is kept two guest buffers ahead of
  the write cursor"), `kLateLimit` 2048, `kRecoveryRatio` 0.99, `kRecoveryFrames` 204800. The device reads 44100
  frames a second; the ratio closes a deficit or rebuilds a lead at 441 frames a second.
- The arming threshold today is `cursor < read_position + kPrebufferFrames / 4` (512 frames): a write under a
  512-frame lead counts as `lates=` and arms `recover_until`; a cursor strictly behind also drops its played frames
  (`late=`). Task 098's open question 1 asked whether the 512 should drop to "strictly behind". Task 500's answer: no,
  the early arming is the part that works; this task moves it the other way.
- On the rig the race load's snap (`resynced=` 4455 to 5100) lands the cursor 777 to 2595 frames ahead and the lead
  then moves 300 to 700 frames a second either way for the race's first 4 seconds. The clean runs: `lates=2` or
  `lates=10` at the load's second with `late=` 0 or 1536, `ratio=0.990` for 5 s, the lead's minimum 1556 to 2348. The
  bad run: `lates=0` at the load (the cursor landed at 2273), the lead 1949, 1625, then 0, then `lates=30, 54, 10`
  with `late=13919, 6042, 0` and `silent=14363, 5598` (the silence equals the late frames, write for write).
- A producer at real time cannot catch up by itself: its deficit D stays until the ratio eats it, and until then the
  device plays D silent frames per write. That is what the bad run shows and what D-023's "a dip costs a few ms of one
  channel's content" did not foresee.
- Without a device (`stream == nullptr`, headless or `PURE_NO_AUDIO`) the ring drains itself to a lead of exactly
  2048, so a threshold at `kPrebufferFrames` would arm on every write there unless the recovery is gated on a device.
- The Mac never arms: its frontend lead is 3072 to 4352 and its race lead 7424 (task 097, finding 3); the rig's race
  lead after the first 10 s is 4500 to 7700. A threshold at 2048 changes nothing in those regimes.

## Deliverable
1. **Patch 0031 edited in place** (`tools/patches.sh open`, a fixup into 0031's commit, `close`; the series stays at
   30, `check` says so): the recovery arms when a write's cursor is under `read_position + kPrebufferFrames` (the
   lead the sink is designed to hold), not under a quarter of it. The drop of played frames stays for a cursor
   strictly behind; `kLateLimit` and the snap stay; `PURE_AUDIO_SNAP=1` stays the old rule unchanged. No recovery
   without a device: `recover_until` is only set when `impl.stream != nullptr`, so the no-device trace reads
   `lates=0 ratio=1.000` as today. `lates=` counts arming events as it does now (its meaning widens with the threshold;
   say so in the README section). No new switch, no new constant beyond replacing the `/ 4u`, no change to the trace
   line's fields.
2. **The record**: patches/README.md's 0031 row and section (the threshold and why: task 500's two shapes); D-023
   amended by a dated paragraph under its Status (the measured consequence on the rig and the new threshold; the
   decision itself stands); docs/timing.md's "The sound" sentence on the rig's runs gains the outcome; a short
   section appended to docs/tasks/098-audio-sink-late-writes.md closing open question 1 and pointing here for 2.
3. **The window checks the change needs**, listed in the Result for the planning session: the Mac's probe on both
   shells (task 097 row 7: `lates=0 ratio=1.000` there before and, expected, after).

## Acceptance criteria
- [ ] `tools/patches.sh check`: `ok: 30 patch(es)`; the diff of patch 0031 against batch/m2's is the threshold, the
      device gate and comments only.
- [ ] Three runs of `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan` on the rig at 100 Hz, the
      window in front, Chrome closed (task 500: a busy machine stalls the race a quarter of a second and no sink rule
      survives that), each copied aside from out/display_rate_check/audio-vulkan/run.log before the next: each PASS;
      the `[audio]` line of the race load's second (its `resyncs=1`) reads `ratio=0.990` in all three; after that second
      `late=0` and `silent=0` on every line to the run's end in all three; `lead=` never 0 after the load's second.
- [ ] One run with `PURE_AUDIO_SNAP=1`: the old rule's figures (a `resynced=` jump of about 2000 at the dip or a
      clean race, `lates=0`), the switch still an A/B.
- [ ] A 40 s unpaced headless run as task 098's (`trace.log`): after the start-up second every line reads
      `lates=0 late=0 ratio=1.000` (the device gate).
- [ ] `tools/frame_regress.sh` 18/18 (sound off; nothing should move).
- [ ] The README section, D-023's paragraph, timing.md's sentence and 098's appended section written;
      `python3 tools/docs_check.py` PASS.

## Verify
`tools/patches.sh check && tools/frame_regress.sh && PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan`
(the rig, the window in front and uncovered, Chrome closed; the last command is one of the three runs above)

## May touch
- vendor/portablekit/host/audio/audio_sink.cpp, only through `tools/patches.sh open` and `close` into patch 0031
- patches/0031-audio-sink-late-writes.patch (as `close` rewrites it), patches/README.md (the 0031 row and section)
- docs/decisions.md (a paragraph under D-023's Status), docs/timing.md (the rig's sentence in "The sound"),
  docs/tasks/098-audio-sink-late-writes.md (append only), this file

## Must not touch
- Anything else under vendor/, include/psprecomp/, tools/, src/, the other patches, docs/status.md (the planning
  session's at the merge)

## Estimated turns
25

## Escalate when
- The series cannot be reopened cleanly (`open` refused, or `close` leaves `check` under 30): stop, BLOCKED.
- With the ratio armed from the load, `lead=` still reaches 0 in the race's first 10 s in any of the three runs: the
  drain outpaces 441 frames a second and the fix is a different one (a larger ratio, a cushion snap for a cursor
  strictly behind, or both); report the three runs' `lead=` lines for the race's first 10 s and stop, PARTIAL. Do not
  retune `kRecoveryRatio` here.
- `ratio=0.990` shows on every line of a run's race on either rule, or on the Mac's probe when the planning session
  runs it: the threshold arms in a steady state and a pitch 17 cents low has become permanent; revert to 512 in the
  Result and report.

## Result
(the rig fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(the planning session fills) Verify rerun: | The Mac's probe: | Merged: | Notes:

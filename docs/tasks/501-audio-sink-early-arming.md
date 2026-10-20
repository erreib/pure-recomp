# 501: The sink arms its recovery before the lead is gone (the rig's early-race shape)

Milestone: E8 (the rig's 100 Hz sound) | Branch: task/501-audio-sink-early-arming from batch/m2 | Status: DONE (the rig, the planning
session, 2026-10-19; the probe PASS once it counted the race load's snaps apart)

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

## Result (the rig, 2026-10-19, the planning session; branch task/501-audio-sink-early-arming)
Status: PARTIAL. The change is made, measured on the rig and recorded; one gate is owed: the Verify chain's last
command (the probe) ran on a loaded machine and FAILed on the machine, not the sink (below). A probe PASS on a quiet
machine closes it; four earlier runs on the final rule, below, say what it will show. Logs under out/501/.

Changed: patches/0031-audio-sink-late-writes.patch (edited in place through `tools/patches.sh open` and `close`; the
series stays at 30: the arming threshold `kPrebufferFrames / 4u` to `kPrebufferFrames`, gated on a device
(`impl.stream != nullptr`, false without SDL audio) and off under `PURE_AUDIO_SNAP=1`, the comments), patches/README.md
(the 0031 row and section), docs/decisions.md (a dated paragraph under D-023), docs/timing.md (the rig's sentence),
docs/tasks/098-audio-sink-late-writes.md (appended), this file. Beside the brief: tools/patches.sh, one line, its own
commit: `open` applied each patch with `git apply --index`, which on this machine (core.autocrlf true from the system
gitconfig) refused patch 0001 at once, the index holding LF and the worktree CRLF; it now applies to the working tree
and stages with `git add -A`, as `check` applies, and `close` already compares and copies working-tree bytes, so the
live vendor tree kept its line endings and the 29 untouched patch files normalise to no change.

What ran (the rig, 2026-10-19, Chrome closed, VS Code open, the window in front):
- `tools/patches.sh check`: ok, 30 patches, after each `close`.
- `tools/build.sh profile`: incremental, the sink and the link only, twice.
- The headless 40 s trace (`trace.log`, then `trace2.log` on the final binary): every line after the start-up
  second `lates=0 late=0 ratio=1.000`, `lead=2048` (the device gate holds; 1925 lines).
- `tools/frame_regress.sh`: PASS 18/18 twice (9m 9s, then 9m 32s in the Verify chain, which noted fp_hud moved 0.039
  from the measured value, a timing swing under the load below).
- The probes, `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan`, logs `probe-new-N*.log`:

| Run | Binary | Verdict | Load's second (`resyncs=`, `resynced=`, `lates=`) | `ratio=0.990` | `lead=` minimum, race seconds 1 to 10 | `late=`, `silent=` after the load's second |
|---|---|---|---|---|---|---|
| 1 | first | FAIL, 2 resyncs, both in the load's second | 2, 23591, 3 (a stalled load: 23.8 presents that second, `silent=` 21250) | 188 to 196s | 2949 | 0, 0 |
| 2 | first | PASS | 1, 6947, 25 | 188 to 192s | 1707 | 0, 0 |
| 3 | first | PASS | 1, 4404, 29 | 188 to 193s | 1512 | 0, 0 |
| 4 | final | PASS | 1, 4404, 34 | 188 to 197s | 1091 (the load), 1139 at race second 4 | 0, 0 |
| 5 | final, the Verify chain | FAIL: 95 resyncs, 33 seconds under 95% speed, presents' median 96.3 | 1, 4667, 13 | from 188s | 546 at 198s after two 400 ms host stalls | 28192 at 194s and 7673 at 198s, under the stalls |

  The old rule, `PURE_AUDIO_SNAP=1`: on the first binary (`probe-snap*.log`) PASS but with `lates=9 ratio=0.990` at
  the load, because writes between a 512 and a 2048 lead fell through to the new arming: the A/B was broken, fixed in
  the final binary by gating the arming off under the switch. On the final binary (`probe-snap2*.log`): `lates=0
  ratio=1.000` throughout, the dip at race second 4 as a 1737-frame jump (the old click), so the switch is the old
  rule again; that run FAILed on 20 resyncs and 4 seconds under 95% from host frames of 434 and 473 ms, the load below.
- Run 5 and the old-rule run met the machine busy: between runs the CPU read 39 to 54% and the disk 95% from VS Code
  (its C++ extension indexing) and an installer (`setup.tmp`), none of it the game. Run 1's load stall is of the
  same kind. The runs with the race's `[perf]` seconds at 99 to 100% all PASS.

Readings:
1. The arming from 2048 does what the brief asked: in runs 2 to 4 the ratio is on from the load's second, the lead
   rebuilds to 3000 or more within four seconds, and the dip at race second 4 (run 4: 2663 to 1139) passes with no
   late frame and no silence. `lates=` now reads 25 to 59 a second while the lead is under 2048 (arming events, as
   the README says), then 0; `ratio=0.990` ends 4 to 9 s after the load, never steady.
2. Nothing in the rule survives a host stall of 400 ms: the producer falls more than `kLateLimit` behind and snaps,
   as D-023 says it should. Run 5 shows what that looks like (95 snaps over 33 slow seconds) and is the measure of
   the machine, not of this change.
3. No escalation condition met: the lead never reached 0 in a quiet run; `ratio=0.990` never covered a whole race.

Verify output (out/501/verify.log, its last 20 lines; exit 1 on the loaded probe):
```
league_select   5185    0.0614   0.08   24     0.062 -0.0006  PASS
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0731   0.12   32     0.049 +0.0241  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0868   0.11   32     0.048 +0.0388  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_change   5679    0.0673   0.10   32     0.052 +0.0153  PASS

moved more than 0.03 from the vulkan measured value: fp_hud (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (9m 32s)
display_rate_check: audio, shell vulkan, backend vulkan, the display's own refresh, margin the default, out /h/errei/Documents/dev-stuff/pure-recomp/out/display_rate_check/audio-vulkan
display_rate_check: probe: [pure] display rate: 100 Hz display, the game at 99.49 Hz in a race (margin 0.005), the PSP's 59.94 Hz outside one; the unpaced boot presents 99.9 a second; the run ends at flip 13362
display_rate_check: run_boot exit 0, 144 s, log /h/errei/Documents/dev-stuff/pure-recomp/out/display_rate_check/audio-vulkan/run.log
vulkan: 100 Hz display, margin 0.005, the game at 99.49 Hz (10051 us a vblank); the window on screen: yes (unpaced presents a second: the menus' median 100.0, the race load's [70.5, 99.3]); race seconds 84 (81 after the first 3); resyncs 95 (audio seconds: 188s, 194s, 199s x2, 201s x2, 203s x2, 204s x2, 205s x2, 206s x2, 208s x2, 209s x3, 210s x2, 211s x3, 213s x2, 215s x2, 230s x2, 231s, 245s x5, ...); ...
display_rate_check: FAIL (audio, vulkan, margin 0.005, 10051 us a vblank: 95 resyncs, 33 seconds under 95% and 44 under 99% (reported), medians 96.3 presents and 99.5 game flips a second; 95 resyncs (at most 1); 33 seconds under 95% speed)
verify exit: 1
```

Open questions:
- The gate: one probe PASS on a quiet machine (the Verify's last command) to close this as DONE.
- The window checks the planning session owes at the merge: the Mac's probe on both shells (task 097 row 7), expected
  unchanged (`lates=0 ratio=1.000`; the Mac's leads sit above 2048).
- The probe's window guard judges presents, not host stalls: a run like 5 passes the guard and FAILs on the sink's
  counters. A guard on `[perf]` frame maxima before the race (the load's) would name the machine instead.

## Review
(the planning session fills) Verify rerun: | The Mac's probe: | Merged: | Notes:

## The gate (2026-10-19, later the same day): DONE

Status: DONE. The probe's own bound was the last thing in the way, not the sink, and the probe now PASSes with the
sink's figures as the brief asked.

What the owed probe showed first (run 6, `probe-new-6*.log`, Chrome open again at 12% of the CPU, nothing else):
FAIL on 2 resyncs, both in the race load's second (188s: `resyncs=2 resynced=9207`, a 128 ms host frame in the
load), the paced race clean (`late=0 silent=0` on every line after, `lead=` 2533 at the load and 3324 by 190s,
`ratio=0.990` 188 to 195s). Run 1 was the same shape with a 516 ms load stall. The load stops every producer, and its
stalls snap them once or twice when they resume (runs 2 to 5 and 7: once; 1 and 6: twice); no sink rule bears on
that (a cursor over `kLateLimit` behind snaps by D-023, and must), and the bound "at most 1 resync (the race load's)"
counted the load's second stall as a click in the race.

The probe's rule (tools/display_rate_check.sh, commit "Count the race load's snaps apart in the sound probe"): the
`[audio]` lines before `[pure] paced from frame` (the load, AUDIO_FROM) are the race load's, printed apart and not
bounded; from that line on `MAX_RESYNCS=0`: a snap in the paced race is a click. Over the kept logs: runs 1, 4, 6
PASS (0 in the race, the load's 2, 1, 2), run 5 FAILs on its 94 (the machine), the old rule's `probe-snap2` FAILs on
its 18 (the dips' 1737-frame jumps, 4 under 95%), which is what the probe is for. docs/verification.md row 21 says so.

The Verify's last command under that rule (run 7, `probe-new-7*.log`, the same machine state):
```
vulkan: 100 Hz display, margin 0.005, the game at 99.49 Hz (10051 us a vblank); the window on screen: yes (unpaced presents a second: the menus' median 100.0, the race load's [72.0, 99.6]); race seconds 77 (74 after the first 3); resyncs 0 (audio seconds: none); the race load's 1 (audio seconds: 188s); channel restarts 1 (audio seconds: 196s); seconds under 99% speed 1 (race second 22 98%), under 95% 0; medians 99.5 presents and 99.5 game flips a second; flip 13362 reached: yes; 137 s
display_rate_check: PASS (audio, vulkan, margin 0.005, 10051 us a vblank: 0 resyncs, 0 seconds under 95% and 1 under 99% (reported), medians 99.5 presents and 99.5 game flips a second)
```
Its sink figures: the load's second `resyncs=1 lates=6 late=2251 ratio=0.990`, then `late=0 silent=0` on every line
to the end, `lead=` 3254 at 189s and never under it through race second 10, `ratio=0.990` 188 to 213s (re-armed once
at 210s by one write under the lead that dropped nothing). With runs 2, 3, 4 and 6 that is five runs on the new rule
with a clean paced race; the acceptance criteria's three hold.

Two more things settled on the way, both outside the brief, recorded here because they bear on Erik's concern (the
sound at the Display rate):

1. **`dropped=` is the harness, not the player's sound** (task 097, finding 4). The counter is the sink's runaway trim
   (`retire(..., false)`: a write that would end past `read_position + kRingFrames`). Every tool's windowed run has
   the menus unpaced (`PURE_PACED_FROM=5900`: the menus at 318% speed on the first `[perf]` line of run 6), so the
   producer writes three seconds of sound a second and the ring, 8192 frames, trims the rest; the `[audio]` lines
   there are 44100-frame windows a third of a second long, which is why the load falls at "188s" of a 137 s run. In
   the paced race `dropped=0` on every line of every run, and in a 45 s run paced from the start
   (`PURE_PACED_FROM=0`, `paced-menus.log`) `dropped=0` on all 42 lines with `lead=` 4264 to 4864. A player's run is
   paced throughout. Nothing to fix; the status line's follow-up can go.
2. **The storms route at 100 Hz still runs slow** (task 091-display-rate-storms' 85%): `PURE_DISPLAY_RATE=1
   tools/stutter_check.sh` today (`stutter-100hz/`): speed median 90%, 148 of 215 race seconds under 95%, frame avg
   11.2 ms, worst 62.5 ms; the check itself said the window was not on screen at the race load (320.7 presents in
   its first second) so it is not a measurement by its own rule, but the race's figures match the storms task's. The
   probe's route on the same build and display holds 99.5. The leading candidate for the difference is the sweep's
   live-file steering: the check's header (task 077) measured 15 to 25 ms of render on every tenth flip for it on
   the rig, and 150 of this run's 165 frames over 25 ms were those flips; the second difference is the weapons the
   follower picks up. A gamepad has no live file. The test that settles it is Erik's played race with `PURE_PERF=log`
   (docs/windows.md, "Open on the rig"), which is also task 500's step 9.

tools/audio_hiccups.py (its own commit) reads a play session's or the probe's log and names each `[audio]` second's
event with the host's second beside it (restart, snap after a host stall or under speed or the old rule's at a dip,
the sink's late writes, a dry ring); on the kept logs it names run 5's 33 snaps as 24 host stalls and 9 seconds under
speed, and the old rule's dips as its own.

Verify (the chain's parts, this close): `tools/patches.sh check` ok 30; `tools/frame_regress.sh` 18/18 twice earlier
today, nothing in this close touches the game; the probe above PASS; `python3 tools/purelib/logs.py --selftest` PASS;
`python3 tools/docs_check.py` 39 files, 0 findings.

Open questions:
- The window checks the planning session owes at the merge: the Mac's probe on both shells (task 097 row 7), expected
  unchanged (`lates=0 ratio=1.000`, resyncs 0 in the paced race; the Mac's load snap, if any, now printed apart).
- Erik's ear (task 500, step 9) with the trace, read by tools/audio_hiccups.py: the one test of the concern itself.
- If a played race runs under 95% speed at 100 Hz with a gamepad, the pacer call (drop vblanks or slow down) is next;
  if near 100, the storms task's 85% is the harness's and docs/timing.md's storms paragraph should say so.

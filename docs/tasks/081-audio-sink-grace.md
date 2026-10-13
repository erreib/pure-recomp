# 081: The sink plays counted silence instead of skipping

Milestone: Windows fidelity (Erik, 2026-10-12; tasks 079 and 080 both measured the skips) | Branch:
task/081-audio-sink-grace | Status: MERGED (f5c81eb, 2026-10-12; BLOCKED as briefed, the finding kept)

## Goal
When the audio producer falls briefly behind the device, `AudioSink`'s stalled-producer branch
(vendor/portablekit/host/audio/audio_sink.cpp, the mix loop: `if (cursor < impl.read_position + kPrebufferFrames /
4u) cursor = impl.read_position + kPrebufferFrames;`) throws away ~46 ms of a continuous channel to rebuild its
lead — an audible click. Task 079 measured 5.18 of them a second through a swept race and task 080's baseline 17.4/s
at both scales, every one with `silent=0`: the shortfalls are real and the skips are how they reach Erik's ears.
After this task a late producer keeps its content: only frames already played are dropped, the rest land where they
belong, any unwritten stretch plays as silence that `retire` already counts, and the resync counter reads ~0 in a
race. The fix is patch 0024-audio-resync-counter's natural second half and shares its upstream case.

## Read first
- CLAUDE.md, docs/tasks/079-audio-rate-match.md and docs/tasks/080-guest-budget-and-sink-grace.md (whole files:
  the counter, the figures, why rate-matching and the depth store were rejected), docs/status.md (the 079 row),
  patches/README.md (0023's row), docs/upstream.md
- vendor/portablekit/host/audio/audio_sink.cpp, the whole file, closely: the ring and its cursors (`read_position`,
  `write_end`), the mix loop (the ADDITIVE write: `ring[slot] = saturate(ring[slot] + left)` — channels mix into
  each other, so a late channel's frames before `read_position` are gone but frames after it may land on top of
  already-mixed, not-yet-played content, which is correct), the stalled-producer branch, the runaway trim,
  `retire`'s silent accounting, the 0023 counters, `report()`
- The figures: the 080 worktree's out/080/ (.claude/worktrees/agent-ae5f11aa5851525c9), the 079 worktree's
  out/079-char/, and the main checkout's out/play-trace*.log
- tools/stutter_check.sh (the gate and the probe's environment), tools/flash_check.sh (the race lane rides the
  sweep with sound), docs/verification.md, README.md (the PURE_TRACE_AUDIO row)

## Deliverable
One vendor patch, `patches/0024-audio-sink-grace.patch`, its rows in patches/README.md (upstream candidate, with
0023), the docs, commits per proven stage.
- **The rule:** a write whose cursor is behind `read_position` drops exactly the frames already played
  (`read_position - cursor` of them, counted: a new `late` frame counter beside `resynced` on the trace line) and
  writes the rest from `read_position` on — no jump, no rebuilt lead, no 46 ms of channel discarded. The old
  branch's counter (`resyncs`) stays and now counts only writes that were ENTIRELY in the past (everything
  dropped), which should be ~0 in a race. A channel that was idle so long its cursor is far behind (the menus' 8
  restarting channels in 079's run, 85 k to 6.4 M frames) is not "late": restarts keep their old behaviour —
  pick the boundary (kRingFrames is a natural one: farther behind than the whole ring is a restart, nearer is
  lateness) and say it in a comment and the Result.
- **Prove it:** the gate's probe (`PURE_TRACE_AUDIO=1 tools/stutter_check.sh`) before and after on the branch:
  before, resyncs at the 080 baseline's order; after, resyncs ~0, the shortfall visible as `late` frames (and any
  true gap as `silent`), the race's figures in the Result. By ear is Erik's, not a gate.
- **The gates:** `tools/stutter_check.sh` PASS, `tools/flash_check.sh --shell vulkan` PASS (its laps ride a
  sounded sweep; escalate rather than widen if its figures move), `tools/frame_regress.sh --shell vulkan --backend
  vulkan` 7/7 (sound is off there; nothing should move), `tools/patches.sh check` (24 patches) and `python3
  tools/docs_check.py` PASS.
- **Docs:** patches/README.md, README.md (the trace row's new field), docs/windows.md (the 2026-10-12 hunt's line:
  the clicks' fix), docs/tasks/081-audio-sink-grace.md (the Result).

## Acceptance criteria
- [ ] the before/after probe figures in the Result: resyncs from the baseline's order to ~0, the shortfall counted
      as late (and silent where a gap truly played)
- [ ] channel restarts (long-idle cursors) behave as before, and the Result says where the boundary is
- [ ] `tools/stutter_check.sh` PASS, `tools/flash_check.sh --shell vulkan` PASS, `tools/frame_regress.sh --shell
      vulkan --backend vulkan` PASS 7/7
- [ ] `tools/patches.sh check` (24) and `python3 tools/docs_check.py` pass; nothing committed under vendor/

## Verify
`tools/stutter_check.sh && tools/flash_check.sh --shell vulkan && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/audio/audio_sink.cpp: only through `tools/patches.sh export 0024-audio-sink-grace`;
  commit patches/, never vendor/
- patches/0024-audio-sink-grace.patch (new), patches/README.md
- README.md, docs/windows.md, docs/verification.md, docs/tasks/081-audio-sink-grace.md (the Result)

## Estimated turns
60

## Must not touch
- include/psprecomp/, generated/, config/, src/, tools/, every other vendor file, ref/, docs/decisions.md,
  docs/status.md, anything not listed above

## Escalate when
- the additive mix makes the late-write rule double-mix or tear a channel (report the case: the rule may need the
  per-channel cursor, which is HLE territory)
- flash_check's race figures move beyond their bounds
- the probe still shows resyncs well above 0 after the fix (name what writes land entirely in the past)

## Result
Status: BLOCKED. The third escalation condition fired: after the fix the probe shows resyncs far above 0 (35.7/s
from the paced flip, against 17.4/s before), and the writes that land entirely in the past are named below. The
rule as briefed mutes a continuous channel instead of clicking it. No patch is committed. Nothing under vendor/
changed. `tools/patches.sh check` still reads 23.

**The before-probe** (the unfixed branch, patches 0001 to 0023, committed as its own stage in 5179ddc):
`PURE_TRACE_AUDIO=1 tools/stutter_check.sh --out out/081/before` PASSed (22 of 222 seconds over 25 ms, readback
0.00). `[audio] total frames=24977536 silent=0 dropped=0 resyncs=7390 resynced=27826304`. Before the paced flip:
229 s, 1701 resyncs (7.4/s). From the paced flip on (327 `[audio]` seconds, the race and its results tail): 5686
resyncs (17.4/s, the 080 baseline's order), 12,104,064 frames resynced, silent 0. In the race seconds a resync jumps
2033 to 2063 frames, so the cursor sat AT the read position (0 to ~15 frames ahead of it) when the old branch
fired. The writes were not in the past; their lead had run out.

**The rule tried** (built and probed, then reverted; the patch is kept uncommitted in the worktree's
out/081/0024-audio-sink-grace.tried.patch):
- Restart: a cursor more than kRingFrames (8192) behind `read_position` takes the old snap to read_position + 2048,
  counted as a resync with `resynced`.
- Late: a cursor behind `read_position` by no more than that has its played head dropped (`read_position - cursor`
  frames, counted as `late=`, with `lates=` events). The rest is mixed at its own slots from `read_position` on.
- A write wholly in the past is dropped and also counted as a resync.
- A cursor in [read_position, read_position + 512) is written in place.

The additive mix itself was not the problem. A late channel's own earlier frames all end before its cursor, so the
remaining frames land only on other channels' content and nothing is mixed twice.

**The after-probe** (`PURE_TRACE_AUDIO=1 tools/stutter_check.sh --out out/081/after`): FAIL, 23 of 214 seconds
over 25 ms against the 10% bound (21.4 allowed). Before it was 22 of 222, so this sits on the line. The sink does no
frame work, so I read it as noise, but it is unproven. `[audio] total frames=17141376 silent=0 dropped=0
resyncs=9767 resynced=12241664 lates=14239 late=9363712`.
- Before the paced flip: 190 s, 15.3 resyncs/s, 17.5 lates/s.
- From the paced flip on: 191 s, 6823 resyncs (35.7/s), 450,304 frames resynced, 10,859 lates (56.9/s), and
  6,811,008 late frames (35,660 a second), silent 0.
- The steady race second reads `resyncs=37 resynced=0 lates=59 late=36608`. That is one continuous channel writing
  768-frame buffers about 59 times a second (45,312 frames/s, its whole output):
  - about 37 of those writes a second land ENTIRELY in the past and are dropped whole;
  - the other ~22 are partly late (~370 frames dropped each);
  - so about 80% of that channel's audio never reaches the device.
- The menus show the same shape: seconds like `resyncs=59 lates=59 late=45312` (every write of the channel dropped).

**Why: the brief's premise does not hold.** The guest-clocked producer never runs faster than real time. In the race
(80 to 90% speed in this harness) it runs slower. A channel whose lead reaches zero therefore never gets it back.
Without the jump its cursor stays behind the device by a roughly constant amount (or drifts further behind) until it
passes kRingFrames and the restart branch snaps it forward. Every write in between is late, most of them entirely.
The old branch "skipped" nothing of the channel's content: it inserted ~46 ms of silence and rebuilt a 2048-frame
lead. That gap is the click. Dropping played frames without rebuilding a lead turns the click into a near-mute.
Whatever the rule, a producer below real time leaves a deficit that has to come out as silence, a pitch or tempo
change, or lost content.

Changed: docs/tasks/081-audio-sink-grace.md (the before figures in 5179ddc, and this Result). No patch, no
README/windows.md rows. The probe logs, the summarizer (out/081/audsum.py) and the tried patch are uncommitted
under out/081/.

Verify output: not run in full. Escalated at the after-probe. The gates I did run:
```
before: stutter_check: PASS (22 of 222 seconds over 25 ms, readback 0.00 ms a frame)
after (rule applied): race: PASS, paced from flip 6100; 214 seconds, 11762 frames
after (rule applied): (a) seconds with a frame over 25 ms: 23 of 214 (10.7%); apart, the live-file flips (a multiple of 10) over it: 1002, worst 67.4 ms
after (rule applied): stutter_check: FAIL (23 of 214 seconds over 25 ms, readback 0.00 ms a frame; 23 of 214 seconds have a frame over 25 ms (at most 10%))
after revert: ok: 23 patch(es) reproduce vendor/portablekit at 8b0c3fe
```

Open questions:
- Which way should the sink go?
  - (a) Keep the jump, but make it smaller and land it at read_position plus a modest lead. 512 frames would be
    11.6 ms of gap instead of 46 ms, at the cost of more frequent events.
  - (b) Shift a late cursor to `read_position` and keep the whole buffer (the gap is only the lateness, no content
    lost). This leaves the channel at near-zero lead, so small gaps come back on jitter.
  - (c) Fix it at the source: the HLE's blocking output (`queued_until_us` in hle_media.cpp) keeps each channel a
    fixed lead ahead of the device, or the paced clock catches up. That is the HLE or kernel territory the
    briefs have ruled out so far.
- Most of the before-run's resyncs fire at lead ~0, not lead < 0. The write pattern suggests the device and
  producer both move in buffer-sized steps, so the cursor often meets `read_position` exactly. Is the 512-frame
  threshold itself firing on writes that would have played in time?
- The after-run stutter_check FAIL (23/214 against 22/222 before) is one second over the bound. Is it noise? A
  re-run on the unfixed branch would tell.

## Review

Merged f5c81eb (2026-10-12). The block was right, and the attempt was worth its cost: the tried rule is kept in the
worktree's out/081/ with its probe, and the Result's analysis is the day's keystone — the deficit of a producer
below real time must surface somewhere, and every sink-side rule only chooses where. In Erik's play the deficit is
transient (the dip seconds), so the lived experience is: a dip eats the channel's lead, the old branch re-arms it
with a 46 ms silence — the click — and all is well until the next dip. The design fork for the next session:
(a) a smaller jump (11.6 ms gaps, more often); (b) keep the content and gap only the true lateness — honest, but
the channel then rides at zero lead and crackles on jitter unless the lead is rebuilt; (b+) rebuild it inaudibly by
lowering the SDL stream ratio ~1% for a few seconds after a dip (rate-matching was the wrong cure for 079's
imagined drift, but it is the right instrument for lead recovery); (c) HLE backpressure (hle_media.cpp's
queued_until_us), which is the territory every brief so far has ruled out. The root above all of them stays open:
what swells the guest 2.5 ms in effect storms (the SAS voices are the suspect) — fix the dips and the sink's
policy matters a tenth as often. The sink is shared code, so the Mac session should weigh the fork too.

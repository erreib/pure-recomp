# 503: The sink's late rule keeps content for a dip of milliseconds, not of a write

Milestone: E8 (the rig's 100 Hz sound) | Branch: task/503-audio-sink-late-limit from task/502-hiccup-marks (502 unmerged
when this was cut) | Status: DONE (the rig, the planning session, 2026-10-20; rule 1, a small change made directly;
Erik's ear on the next played race owed)

## Goal
Erik's first marked race (2026-10-20, `out/ear/run.log`, read by `tools/audio_hiccups.py`) put his first mark at race
second 3, right after this:

| Audio second | `lates=` | `late=` | `silent=` | `lead=` |
|---|---|---|---|---|
| 27s | 59 | 44118 | 43338 (982 ms) | 0 |
| 28s | 59 | 17995 | 17231 (390 ms) | 16 |
| 29s | 59 | 262 | 262 (5 ms) | 796 |

The race start ran at 87 to 91% speed for two seconds (`[perf]`: 29.5 then 90.4 presents, worst frame 109 ms), the
lead the load's snap had left drained in half a second, and the deficit that formed, about 1500 frames, sat under
the 2048-frame stall floor of D-023: every write landed entirely behind the device, was dropped whole, and the device
played silence, 1.4 s of it, mostly after the dip had ended, until the 1% ratio had closed the deficit at 441 frames a
second. Task 500's reading 1 described the mechanism; task 501's early arming cannot reach a deficit that forms
faster than the ratio works. The old rule would have snapped three or four times across those two seconds, 50 ms a
click. His second mark (race second 44, two seconds at 87 to 88% in an effects-heavy stretch) sat on two snaps plus
22034 late frames and 95 ms of silence; the Esc menu's resume, which he also heard, gave two snaps and 15000 late
frames the first time and one snap and 20768 the second.

The arithmetic the change rests on: a producer at real time never catches up by itself, so a deficit D costs D
frames of silence on every write (about 58 a second) until the ratio has closed it in D / 441 s: about 0.066 D²
frames in all, and total silence once D exceeds one write (about 750 frames). A snap costs one gap of
`kPrebufferFrames` (2048) plus D in that channel. They meet near D = 200. The late rule was made for a dip of a few
milliseconds (D-023: "a dip costs a few ms of one channel's content"), and that is where it should stop.

Also measured by that race: the played race keeps real time with a gamepad. Speed median 100%, 7 of 167 race
seconds under 95% (the start, race second 31, seconds 44 and 45, the Esc menu's open and close), frame avg median
10.1 ms. The storms route's 85 to 90% (task 091, task 501's rerun) is the harness's live-file steering.

## Deliverable
1. Patch 0031-audio-sink-late-writes edited in place (`tools/patches.sh open`, a fixup, `close`; the series stays
   at 32): `kLateLimit` from `kPrebufferFrames` (2048) to 256, with the comment that says why. Nothing else in the
   rule changes: the early arming, the ratio, the recovery length, the device gate and `PURE_AUDIO_SNAP=1` stay.
2. patches/README.md (the 0031 row and section), docs/decisions.md (a dated paragraph under D-023), docs/timing.md
   (the rig's sentence: the hole, the limit, and the played race's speed), docs/status.md, this file.

## Verify
`tools/patches.sh check && PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan`, the 40 s headless
trace as task 098's (no device: unchanged), `python3 tools/docs_check.py`; then Erik's ear: the same race with the
marks (docs/windows.md, "Open on the rig"), and the Esc menu opened and closed in the race.

## Result
Status: DONE (Erik's ear owed: the next marked race, and the Esc menu in it).

Changed: patches/0031-audio-sink-late-writes.patch (`kLateLimit` 256 and its comment; edited through
`tools/patches.sh open`, a fixup into 0031's commit, `close`; the series stays at 32), patches/README.md (the 0031
row and section), docs/decisions.md (the dated paragraph under D-023), docs/timing.md (the rig's sentence),
docs/status.md (the sink bullet, Next), this file.

What ran (the rig, 2026-10-20):
- `tools/patches.sh check`: ok, 32 patches, after `close`. `tools/build.sh profile`: the sink and the link.
- The probe, `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan` (`out/503/probe-1*.log`): PASS.
  The race load's snap once (5633 frames, a 114 ms host frame), then `lates=3 late=0` in the load's second with the
  ratio armed, and after it `late=0 silent=0 lates=0` on every line: the lead 2701 at the load, 3481, 4261, 4273,
  2749 at the race's dip (192s, under the already-armed ratio), 3630, 4074; `ratio=0.990` 188 to 192s. Nothing
  snapped in the paced race: the dip did not reach the device, so the lower floor was not exercised there; it is
  exercised by a race that runs under speed, which the probe's route does not.
- The 40 s headless trace (`out/503/trace.log`, no device): 2022 lines, every one after the start-up second
  `lates=0 late=0 ratio=1.000`, `lead=2048`: unchanged, the device gate holds.
- `python3 tools/docs_check.py`: 39 files, 0 findings.

Verify output (the probe's last two lines):
```
vulkan: 100 Hz display, margin 0.005, the game at 99.49 Hz (10051 us a vblank); the window on screen: yes (unpaced presents a second: the menus' median 100.0, the race load's [67.6, 100.1]); race seconds 77 (74 after the first 3); resyncs 0 (audio seconds: none); the race load's 1 (audio seconds: 188s); channel restarts 1 (audio seconds: 196s); seconds under 99% speed 1 (race second 5 97%), under 95% 0; medians 99.5 presents and 99.5 game flips a second; flip 13362 reached: yes; 137 s
display_rate_check: PASS (audio, vulkan, margin 0.005, 10051 us a vblank: 0 resyncs, 0 seconds under 95% and 1 under 99% (reported), medians 99.5 presents and 99.5 game flips a second)
```

Erik's second marked race (`out/ear/run2.log`, the same day, right after): "Seemed almost perfect this time. I just
noticed one tiny tiny stutter in the intro camera sequence." One mark, at host second 20, race second 2, and the log
under it:

| Audio second | `resyncs=` | `resynced=` | `silent=` | `lead=` | the host's second |
|---|---|---|---|---|---|
| 20s | 2 | 5789 | 1693 (38 ms) | 91 | race second 2: speed 80%, worst frame 44 ms |
| 21s | 1 | 2498 | 450 (10 ms) | 4137 | race second 3: 100% |

Three clicks and 48 ms of silence across the race's slow start (the intro camera, the one second of the race under
95%: 80%), where the first race had 1.4 s of silence; then nothing for 160 race seconds: `late=0 silent=0
resyncs=0` on every line, the speed median 100%, and the Esc menu opened and closed twice mid-race (0.7 s and 0.6 s)
with the lead holding at 5400 to 6500 and no event on either side, where the first race's 2.6 s menu had two snaps
and 15000 late frames on resume. The reader names the start's snaps `a dip ate the lead (80% speed)` (its wording
changed with this run: under a 256-frame floor a jump under 4096 frames is a dip's, the old rule's or not).

Open questions:
- The intro camera's second runs at 80% on this machine (worst frame 44 ms): the pacer's question (docs/status.md,
  "Open calls"), not the sink's; at 80% speed a fifth of that second's sound does not exist, and 48 ms of it in three
  pieces is the sink's best shape for it short of a pitch drop to match.
- The Esc menu's resume was clean twice here (short menus) and not once in the first race (a 2.6 s menu, before this
  floor): a trace of a long menu on this sink before anything is written for it.

## The intro camera's second, traced (2026-10-20, Erik's third race)

Erik's A/B by ear: at a lower Resolution the start's click is "definitely less noticeable" but still there, and the
overlay's frame graph goes irregular for an instant. Then one race start at his settings (3440x1440, Display) with
`PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=12 PURE_TRACE_AUDIO=1 PURE_PERF=log` (`out/ear/run3.log`): this start had
one snap (`resynced=3005`, `silent=957`, 22 ms) and he did not notice it; the second race's had three (48 ms). The
`[slow-frame]` lines of race second 1 (speed 93%, worst frame 123 ms) are three different costs:

| Frames | What the line says | Cost |
|---|---|---|
| 550 | `pacing 108 ms`: the pacer holding the game after the load | not audible |
| 553, 554, 555 | `guest 30.5`, `47.1`, `36.4 ms`: three frames of the game's own work, where the `[io]` lines open the track, the billboards and every ship | 114 ms in a row |
| 558 | `render 32.3 ms`: one frame of the renderer's CPU time, first-use uploads (`copy x2`, `decode 1.1`) | 32 ms |
| 559, 585, 599 | `fence 8.3`, `8.6`, `14.2 ms`: waiting on the GPU, the flyby at 3440x1440 (`gpu(prev)` 4 ms, second 2's `[stalls]` fence max 14.16) | the resolution-dependent part |

The guest spikes are the game streaming the track during the flyby, as on the PSP, where the kernel preempts the
game thread and the audio thread keeps writing; the port's kernel switches threads at the game's yields, so 47 ms of
game work is 47 ms with nothing written, against the sink's 46 ms lead (`kPrebufferFrames` 2048). The render frame
is once a race and would move to the load screen with a prewarm. The fence waits are pixels.

Task 504, briefed from this: (1) a test switch for the sink's lead (`PURE_AUDIO_LEAD=N` frames) and Erik's ear at
4096 (93 ms): a silent-free start says the cushion is enough, and the question becomes the 46 ms of added sound
latency in play (his ear; if felt, a race-start-only lead trimmed back at a ratio of 1.01 over the next 20 s);
(2) if not enough, the first-use uploads prewarmed at the race load; (3) the guest spikes are the kernel's
preemption question, the pacer-sized design in docs/status.md's "Open calls", not this task's. Not urgent: the
third start was not heard.

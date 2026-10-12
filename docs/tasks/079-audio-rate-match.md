# 079: The audio sink clicks against a fast device clock

Milestone: Windows fidelity (Erik, 2026-10-12: audio stutter through every race, every build, every setting) |
Branch: task/079-audio-rate-match | Status: MERGED (the merge before this commit, 2026-10-12; BLOCKED as briefed, the counter kept)

## Goal
Erik hears audio stutter on the rig through whole races, on Friday's build as on today's, at every enhancement
setting, at 60 Hz as at 100 Hz — while another game on the same machine plays clean, and every counter the sink has
reads zero. The planning session's traced play sessions (out/play-trace-100hz.log and out/play-trace.log on the
rig) found the mechanism the counters miss: the `[audio]` trace lines tick once per 44100 frames the DEVICE
consumed, and there are consistently about 1% more of them than `[perf]` wall seconds (ratios 1.0089 and 1.0110) —
the playback device (an external USB soundcard) drains faster than the game produces (the game's own clock also
paces ~0.5% under wall, task 072's figures; the relative drift is what matters). The producer's lead over the read
cursor (kPrebufferFrames/4 = 512 frames, ~12 ms) is eaten in about a second, and then `AudioSink`'s stalled-producer
branch (audio_sink.cpp around line 311: `if (cursor < impl.read_position + kPrebufferFrames / 4u) cursor = ...`)
silently jumps the cursor forward: an audible click, no counter, once every second or two, forever. The ring never
runs dry (the jump restores the lead), so `silent=` stays 0 and the gap is invisible to every probe so far.

After this task the sink rate-matches the device, the resyncs are counted and visible in the trace, and a scripted
run on the rig proves both the defect (the counter before the fix) and the cure (the counter after).

## Read first
- CLAUDE.md, docs/status.md (the 077/078 rows: the probe method and what was already ruled out), docs/upstream.md
  (this is an upstream candidate: every port clicks on drifting hardware), patches/README.md
- vendor/portablekit/host/audio/audio_sink.cpp, the whole file: the ring (kRingFrames 8192, kPrebufferFrames 2048),
  `retire` (the silent accounting: `silent` counts ring-dry frames — correct and untouched), the mix loop's
  stalled-producer branch (the uncounted jump), the runaway-producer trim (`dropped`, its symmetric twin, counted),
  `feed_device` / `SDL_PutAudioStreamData` (the SDL3 feed), `report()` (the per-second `[audio]` line),
  `SDL_OpenAudioDeviceStream` (the stream the ratio call acts on)
- SDL3's audio stream API as vendored (build/_deps SDL headers): `SDL_SetAudioStreamFrequencyRatio`,
  `SDL_GetAudioStreamQueued`, `SDL_GetAudioStreamAvailable` — what the ratio means (values above 1.0 consume the
  source faster) and where it may be called from (any thread; the stream locks internally)
- The play logs named above, and tools/campaign_sweep.py + tools/flash_check.sh (the race lane) as the scripted
  vehicle: the sweep machine plays through the same default device, so the drift and the resyncs reproduce
  scripted — they always did; nobody was listening and nothing counted
- README.md's switches table (where the new switch rows go), docs/verification.md

## Deliverable
One vendor patch, `patches/0023-audio-resync-counter.patch`, its rows in patches/README.md, and the docs. Commits per
proven stage; the characterization commit comes before any fix.
- **Characterize first:** add the missing counter — the stalled-producer jump increments `resyncs` (and a
  `resynced` frame count), both on the `[audio]` trace line and in the shutdown total. One swept race with
  `PURE_TRACE_AUDIO=1` (sound on): commit the run's figures. The prediction to check: resyncs at roughly 0.5 to 1
  a second through the race, matching the ~1% drift; if the rate is wildly different, stop and report before
  designing (the fix below assumes drift, not a bursty producer).
- **The fix, rate-matching:** track the producer's lead (write_end - read_position, already under the lock) with a
  slow filter, and steer `SDL_SetAudioStreamFrequencyRatio` so the lead holds near kPrebufferFrames: a small
  proportional controller, the ratio clamped to 1.0 ± 0.02 and slewed gently (no audible pitch wobble: full-scale
  correction over seconds, not frames). The stalled-producer jump and the runaway trim stay as last-resort guards;
  with the controller they should never fire in steady state. Behind `PURE_NO_RATE_MATCH=1` the controller is off
  and the sink is byte-for-byte the old one (the switch row in README.md).
- **Prove it scripted, both ways:** the same swept race after the fix (resyncs 0, or say why not), and once with
  `PURE_NO_RATE_MATCH=1` (the resyncs return at the characterization rate: the switch and the counter both proven).
  Paste all three runs' `[audio]` summary lines into the Result.
- **The suite must not move:** the audio path's virtual-time side is untouched; `tools/frame_regress.sh --shell
  vulkan --backend vulkan` 7/7 and `tools/flash_check.sh --shell vulkan` PASS (flash_check's laps ride the sweep
  with sound on — if its figures move beyond their bounds, escalate rather than widen).
- **Docs:** patches/README.md (both tables, the upstream column — flag it as an upstream candidate),
  README.md (the switch row; the `PURE_TRACE_AUDIO` row gains the resync fields), docs/windows.md (one line closing
  the 2026-10-12 stutter hunt: what it was), docs/verification.md if the check lists change. `python3
  tools/docs_check.py` and `tools/patches.sh check` pass.

## Acceptance criteria
- [ ] the characterization run committed first, with the resync counter's figures (the defect visible at last)
- [ ] after the fix, the same run shows resyncs 0 (or the Result says what remains and why it is right)
- [ ] with `PURE_NO_RATE_MATCH=1` the resyncs return at the characterization rate
- [ ] the ratio the controller settles at is in the Result (expect roughly 1.01 on this rig), and the trace line
      carries it so a player's log shows the drift
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` PASS 7/7, `tools/flash_check.sh --shell vulkan` PASS
- [ ] `tools/patches.sh check` and `python3 tools/docs_check.py` pass; nothing committed under vendor/

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan && tools/flash_check.sh --shell vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/audio/audio_sink.cpp (and audio_sink.hpp if the counters need it): only through
  `tools/patches.sh export 0023-audio-resync-counter`; commit patches/, never vendor/
- patches/0023-audio-resync-counter.patch (new), patches/README.md
- README.md, docs/windows.md, docs/verification.md, docs/tasks/079-audio-rate-match.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, src/, tools/, every other vendor file (the HLE audio modules, the kernel,
  the renderers are not the patient), ref/, docs/decisions.md, docs/status.md, anything not listed above

## Estimated turns
60

## Escalate when
- the characterization's resync rate does not match the drift (a bursty producer or a scheduling hole is a
  different bug)
- SDL_SetAudioStreamFrequencyRatio is absent from the vendored SDL or behaves per-put rather than persistently
  (report what the header says; a sink-side resampler is a bigger task, not this one)
- flash_check's race figures move beyond their bounds with the controller on

## Result
Status: BLOCKED. This is the brief's first escalation condition: the resync rate does not match a drift. The
characterization is committed (6ea021f, patch 0023 with the counter only). No controller was built.

**The characterization run.** I ran `PURE_TRACE_AUDIO=1 PURE_PERF=log tools/campaign_sweep.py single_race vineta_k
--no-damage --shell vulkan --sound` on the rig. The cell passed: 3 laps, 193.5 s race clock, 424 s real. The log is in
the worktree's out/079-char/.
- Summary: `[audio] total frames=18499509 silent=220530 dropped=0 resyncs=1121 resynced=15033659`
- By phase (the [audio] seconds, next to the [perf] `speed`, which is virtual ms over wall ms):

| phase | seconds | resyncs | rate | frames per event | mean speed |
|---|---|---|---|---|---|
| menus, 1-189 s | 189 | 10 | 0.05/s | 1.24 M | 100.4% (183 s at 99-101%) |
| load, 190-202 s | 13 | 10 | 0.77/s | 50 k | 95.6% |
| race, 203-405 s | 202 | 1047 | 5.18/s, in 188 of 202 s | 1959 | 88.5% |
| results | 14 | 50 | 3.6/s | 1980 | 94% |

- Of the 9 menu seconds with a resync, 8 are channels restarting after idle (85 k to 6.4 M frames skipped: the
  channel was silent, so nothing is heard). Only one (63 s, 2163 frames) looks like a lead running out. A 1% fast
  device would eat the 1536-frame lead every 3.5 s per continuous channel, which is tens of resyncs in 189 s. That
  did not happen.
- In the race the resyncs run at 5 to 10 times the prediction, about 1959 frames (44 ms) each. That is a cursor
  caught right at the device, not one trimmed by a slow drift. Frames skipped in the race: 10,152 a second. The
  producer's shortfall at 88.5% speed is 5,070 frames a second per continuous channel, so two channels come to
  about 10,140. The skips track the guest's lost real time: a slow, bursty producer, not a fast device.

**The "1% fast device" premise looks like an artefact.** `host/perf/frame_stats.cpp:463-517` starts each `[perf]`
window at the first frame after 1000 ms (`s.window_start = now`) and carries no remainder. So each `[perf]` line
covers 1 s plus about half a frame: about 0.8% at 60 fps and 1.6% at 30 fps. Counting `[audio]` lines against
`[perf]` lines gives 1.0089 and 1.0110 in Erik's logs and 418/415 = 1.0072 in this run, whatever the device does.
Measured by its frames instead, this run's device played 18,499,509 / 44100 = 419.5 s inside a 424 s cell
(boot included), so it is not 1% fast.

**Erik's play logs agree with this reading.** Their mean speed is 99.24% (100 Hz) and 98.11% (60 Hz), mostly at
100%, with about 50 seconds dipping to 63-95%. The skips would cluster in those dips. A ±2% ratio cannot absorb a
second at 63%, and pitch-shifting through it would be audible. Rate-matching is the wrong cure.

**What a follow-up task should decide** (outside this brief):
1. Why the windowed sweep's race runs at 88.5% of real time on the rig. Task 077 measured 66 fps; this run shows
   fps 52-56 and guest 10-11 ms a frame. It may be the sweep's stdout into the pty (task 078) or the traces.
2. What the sink should do with a producer that falls behind. Options: a larger lead or resync threshold (512 and
   2048 frames, 12 and 46 ms, are tight for race frame-time jitter); not jumping a continuous channel but letting
   the ring play silence, which is then counted as `silent`; or the kernel's paced clock catching up instead of
   losing time. This touches the kernel or HLE audio, which this brief rules out.
3. Erik's stutter in play is probably those dips (seconds at 63-95% speed), not a steady drift. A play log with
   this counter would show whether resyncs cluster in the slow seconds.

Changed: patches/0023-audio-resync-counter.patch (new: the resync, resynced and lead counter only), patches/README.md
(the table row and the paragraph, upstream candidate), README.md (the `PURE_TRACE_AUDIO` fields),
docs/tasks/079-audio-rate-match.md (this Result). There is no fix, so docs/windows.md is unchanged and there is no
`PURE_NO_RATE_MATCH`.

Verify output (last 20 lines, git's whitespace warnings from `patches.sh check` left out):
```
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0603   0.12   32     0.049 +0.0113  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0475   0.11   32     0.048 -0.0005  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0526   0.09   32     0.045 +0.0076  PASS
zone_change   5679    0.0461   0.10   32     0.052 -0.0059  PASS
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (12m 12s)
flash_check: fade, shell vulkan, backend vulkan, out .../out/flash_check/fade-vulkan-vulkan
flash_check: PURE_SMOOTH_FLASHES=0: run_boot exit 0, frame 6400 reached: yes, 117 s, log .../0/run.log
  hud_check: 1 of 1 shots have the HUD
flash_check: PURE_SMOOTH_FLASHES=1: run_boot exit 0, frame 6400 reached: yes, 123 s, log .../1/run.log
  hud_check: 1 of 1 shots have the HUD
PURE_SMOOTH_FLASHES=0: flips 5600-6100: 164 at two vblanks, longest run 105; 105 before the race's first one-vblank flip (5705); the fade: flips 5709-5765, 57 flips, 1.90 s; the race clock starts at flip 6254, 546 flips and 10.04 s from the fade's first
PURE_SMOOTH_FLASHES=1: flips 5600-6100: 107 at two vblanks, longest run 102; 102 before the race's first one-vblank flip (5702); from the fade's first flip (5709) to 6100: 1 at two vblanks (5894-5894); the fade's 1.90 s span flips 5709-5823, 115 flips; the race clock starts at flip 6308, 600 flips and 10.43 s from the fade's first; '[pure] smooth flashes: on (game.smooth_flashes)' after flip 5700
flash_check: PASS (fade 57 flips off, 1 on; the race and its HUD in both)
ok: 23 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 33 files, 0 findings: PASS
```

Open questions:
- Keep patch 0023's slug, or rename it (for example 0023-audio-resync-counter)? It holds only the counter, and its
  README row says so.
- The task 077/078 race figures are "66 fps". This windowed sweep with sound and traces showed fps 52-56 and speed
  88.5%. Is that the harness's cost (pty stdout) or a regression? It decides whether the sweep can stand in for
  Erik's play.
- docs/status.md (not mine to touch) still states the fast-device premise for 079.

## Review

Merged 2026-10-12 as the counter it truthfully is (the patch renamed 0023-audio-resync-counter; no controller, no
PURE_NO_RATE_MATCH). The block was correct and the characterization overturned the brief's premise with the primary
measurement — the planning session's "1% fast device" was the perf trace's window arithmetic, not the DAC. What the
figures actually say: the race's resyncs (5.18/s, ~1959 frames each) track the guest's lost real time, and Erik's
play logs show the same shape — seconds at 63-95% speed whose guest time swells to 13-14 ms a frame at 60 fps.
The audio clicks and the visible slowdowns are one defect: the guest thread over budget in effect storms. Two named
follow-ups go to task 080: the depth write-back's CPU conversion runs on the guest thread at the full scaled size
(a GPU downsample to 480x272 before the copy cuts it 16-fold at 4x), and the sink's stalled-producer branch should
play counted silence rather than skip a continuous channel. The sweep's own speed figures (88.5% with sound and
traces) are the harness's cost and cannot stand in for play; Erik's next traced play run carries the new counter.

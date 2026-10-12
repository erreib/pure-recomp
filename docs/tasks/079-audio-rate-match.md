# 079: The audio sink clicks against a fast device clock

Milestone: Windows fidelity (Erik, 2026-10-12: audio stutter through every race, every build, every setting) |
Branch: task/079-audio-rate-match | Status: OPEN

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
One vendor patch, `patches/0023-audio-rate-match.patch`, its rows in patches/README.md, and the docs. Commits per
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
  `tools/patches.sh export 0023-audio-rate-match`; commit patches/, never vendor/
- patches/0023-audio-rate-match.patch (new), patches/README.md
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

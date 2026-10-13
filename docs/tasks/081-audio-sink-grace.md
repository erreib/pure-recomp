# 081: The sink plays counted silence instead of skipping

Milestone: Windows fidelity (Erik, 2026-10-12; tasks 079 and 080 both measured the skips) | Branch:
task/081-audio-sink-grace | Status: OPEN

## Goal
When the audio producer falls briefly behind the device, `AudioSink`'s stalled-producer branch
(vendor/portablekit/host/audio/audio_sink.cpp, the mix loop: `if (cursor < impl.read_position + kPrebufferFrames /
4u) cursor = impl.read_position + kPrebufferFrames;`) throws away ~46 ms of a continuous channel to rebuild its
lead — an audible click. Task 079 measured 5.18 of them a second through a swept race and task 080's baseline 17.4/s
at both scales, every one with `silent=0`: the shortfalls are real and the skips are how they reach Erik's ears.
After this task a late producer keeps its content: only frames already played are dropped, the rest land where they
belong, any unwritten stretch plays as silence that `retire` already counts, and the resync counter reads ~0 in a
race. The fix is patch 0023-audio-resync-counter's natural second half and shares its upstream case.

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

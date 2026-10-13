# 080: The guest's frame budget at scale, and the sink's grace

Milestone: Windows fidelity (Erik, 2026-10-12: the slowdown and the click are one defect, task 079's finding) |
Branch: task/080-guest-budget-and-sink-grace | Status: MERGED (d8fe8fc, 2026-10-12; BLOCKED as briefed, the baseline kept)

## Goal
Task 079's counter made the stutter legible: in effect storms at 60 fps the guest time swells to 13 to 14 ms of the
16.7 ms budget in Erik's play (out/play-trace.log on the rig: the dip seconds' `guest` field), the game loses real
time (speed 63 to 95%), and the guest-clocked audio producer falls behind the device, which the sink resolves by
jumping a continuous channel's cursor — an audible click (resyncs 5.18/s in the 079 characterization). Two fixes,
both vendor, each measurable alone:

**A. Take the depth conversion off the guest thread's budget.** `write_back_depth` runs at the lens flare's SIGNAL
on the guest thread, and `store_depth` (patch 0021) converts the depth staging buffer at the TARGET's full extent —
at Erik's internal scale 4 that is 1920x1088 texels read, converted and downsampled on the CPU every race frame,
inside the guest's 16.7 ms. The GPU should reduce first: render or copy the depth to a PSP-sized (480x272)
single-channel image as part of the recorded frame (the exact centre-texel rule store_depth already applies), and
let the CPU convert 480x272 texels whatever the scale. At 4x that is a 16-fold cut of this slice of guest time.

**B. The sink stops clicking when the producer is briefly behind.** The stalled-producer branch (audio_sink.cpp:
`if (cursor < read_position + kPrebufferFrames / 4u) cursor = read_position + kPrebufferFrames`) skips ~46 ms of a
continuous channel to rebuild its lead. Replace the jump with the smallest graceful rule: drop only the frames that
are truly in the past (before read_position), write the rest where they belong, and let any unwritten stretch play
as silence — which `retire` already counts (`silent=`). The resync counter stays and should read near 0 in steady
state; what shortfall remains becomes counted silence instead of an uncounted skip. The runaway-producer trim is
not the patient.

## Read first
- CLAUDE.md, docs/tasks/079-audio-rate-match.md (the whole file: the characterization figures, the Review, why
  rate-matching was rejected), docs/tasks/077-vulkan-readback-stutter.md (patch 0021: the async depth write-back
  this task builds on), docs/status.md (the 079 row), patches/README.md (0021 and 0023 as the models),
  docs/upstream.md
- The rig's play logs: out/play-trace.log and out/play-trace-100hz.log in the main checkout (the dip seconds'
  guest/render/wait split), and the 079 worktree's out/079-char/ (the counter's race figures)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `write_back_depth` and `store_depth` (patch 0021's shape: the
  per-slot staging, `record_depth_copy`, `centre_texel`), the 1x effect targets of patch 0018 (the model for a
  small auxiliary target and its pass), the depth format cases (D16/D32/D32S8 and the 24-bit default)
- vendor/portablekit/host/audio/audio_sink.cpp: the ring, the stalled-producer branch, `retire`'s silent
  accounting, the 0023 counters
- tools/stutter_check.sh (the gate; its env is the probe's), tools/campaign_sweep.py, tools/purelib/port.py (the
  pins), tools/patches.sh, docs/verification.md, README.md (the switches and PURE_TRACE_AUDIO rows)

## Deliverable
Two vendor patches so each fix reverts alone — `patches/0024-vulkan-depth-downsample.patch` and
`patches/0025-audio-sink-grace.patch` — their rows in patches/README.md (both upstream candidates), and the docs.
Characterize-then-fix per patch; commits per proven stage.
- **A's measure first:** one probe at Erik's config (`PURE_INTERNAL_SCALE=4 PURE_SIXTY_FPS=1` and the other
  shipped defaults, sound on, `PURE_TRACE_AUDIO=1 PURE_PERF=log PURE_TRACE_STALLS=1`) and the same at the default
  2x: the race's mean and dip `guest` ms a frame, the `store` stall figures, the resync rate — committed as the
  baseline the fix is judged against.
- **A:** the GPU-side reduction to 480x272 before the staging copy. Depth images do not blit with filtering, so a
  small pass samples the depth image at the centre texels into a 480x272 target (R16_UNORM or R32_SFLOAT as the
  depth format needs) recorded where `record_depth_copy` records today; the staging buffer shrinks to the PSP size
  and `store_depth` converts 480x272 whatever the scale. Byte-exactness of the guest's 16-bit depth against the
  old path at the same frame is the bar (the same rounding; say in the Result how D24 packs). The same probe after:
  the guest ms at 4x should fall by the store's old share and the 4x and 2x figures should converge.
- **B:** the graceful shortfall rule above, behind nothing (the old jump was never a behaviour anyone chose; the
  resync counter remains as the regression alarm). The probe after: resyncs ~0, the shortfall visible as `silent=`
  instead, and by ear on the rig if Erik is about (not a gate).
- **The gates:** `tools/stutter_check.sh` PASS; `tools/frame_regress.sh --shell vulkan --backend vulkan` 7/7 with
  the pins on (A must not move a pixel: the flare reads the same 16-bit depth); `tools/flash_check.sh --shell
  vulkan` PASS; `tools/patches.sh check` (25) and `python3 tools/docs_check.py` PASS.
- **Docs:** patches/README.md, docs/windows.md (the 2026-10-12 hunt's closing line updated: what the fix was),
  README.md if a switch or trace field is added, docs/tasks/080-guest-budget-and-sink-grace.md (the Result).

## Acceptance criteria
- [ ] the baseline probe committed first (guest ms at 4x and 2x, the store share, the resync rate)
- [ ] after A: the 4x race's guest ms a frame down toward the 2x figure, the store stall at the PSP size; the
      figures in the Result
- [ ] after B: resyncs ~0 in the probe; the remaining shortfall counted as silent frames; the figures in the Result
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` PASS 7/7, unchanged scenes (the depth the flare
      reads is bit-equal: say how you proved it)
- [ ] `tools/stutter_check.sh` and `tools/flash_check.sh --shell vulkan` PASS
- [ ] `tools/patches.sh check` (25 patches) and `python3 tools/docs_check.py` pass; nothing committed under vendor/

## Verify
`tools/stutter_check.sh && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/flash_check.sh --shell vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/vulkan_renderer.hpp,
  vendor/portablekit/host/gpu/shaders/ (a new small shader for A's reduction pass if one is needed),
  vendor/portablekit/host/audio/audio_sink.cpp: only through `tools/patches.sh export` of the two patches named
  above; commit patches/, never vendor/
- patches/0024-vulkan-depth-downsample.patch, patches/0025-audio-sink-grace.patch (new), patches/README.md
- README.md, docs/windows.md, docs/verification.md, docs/tasks/080-guest-budget-and-sink-grace.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, src/, tools/, vendor/portablekit/host/kernel/, the HLE audio modules,
  ge.frag's draw paths (A's pass is its own), ref/, docs/decisions.md, docs/status.md, anything not listed above

## Estimated turns
60

## Escalate when
- A cannot reproduce the old path's 16-bit depth exactly (report the rounding difference and the scene fractions
  before choosing any tolerance)
- the device has no format for the reduction target or the suite moves with the pins on
- B's grace changes flash_check or stutter_check beyond their bounds
- the baseline probe shows the guest dips are NOT dominated by the store (report the split; the brief's A targets
  the wrong slice then)

## Result
Status: BLOCKED. The brief's last escalation condition fired: the guest time is not dominated by the depth store.
The baseline probe is done and its figures are below. No patch was written, nothing under vendor/ changed, and
patches 0024 and 0025 do not exist.

**The baseline probe.** I ran `PURE_TRACE_AUDIO=1 [PURE_INTERNAL_SCALE=4] tools/stutter_check.sh --out
out/080/base-{4x,2x}`. That is the gate's own environment: sound on, `PURE_PERF=log PURE_TRACE_STALLS=1`,
`PURE_SIXTY_FPS=1` and the other shipped defaults. Logs are in this worktree's out/080/. Figures are means per
frame over the `[perf]`/`[stalls]` seconds from the paced flip, with the results screen's tail left out:

| | race s | speed | fps | guest | render | wait | gpu | store | fence | copy | resyncs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 4x | 231 | 78.7% | 47.2 | 11.03 | 5.74 | 4.75 | 6.18 | 0.519 | 3.93 | 0.198 | 17.4/s |
| 2x | 209 | 89.5% | 53.6 | 10.84 | 5.43 | 2.45 | 3.95 | 0.487 | 1.97 | 0.131 | 17.4/s |
| Erik's play-trace.log, race | 153 | | 60 | 9.20 | 3.79 | 3.94 | ~5 | 0.505 | 3.24 | 0.174 | (no counter) |
| the same, dip seconds (speed < 96%) | 23 | 63-95% | | 11.69 | 4.04 | 3.51 | | 0.507 | 3.01 | 0.177 | |

(play-trace-100hz.log reads the same: race guest 9.24 and store 0.509; dips guest 11.37 and store 0.508.)
- stutter_check: 4x FAIL (49 of 239 seconds over 25 ms, readback 0.00). 2x PASS (18 of 217, readback 0.00).
- `[audio] total`: 4x `frames=24182144 silent=0 dropped=0 resyncs=7077 resynced=27195008`; 2x
  `frames=24641920 silent=0 dropped=0 resyncs=7258 resynced=27552640`.

**Why I stopped.**
1. The store costs about 0.5 ms a frame at both scales (0.519 at 4x, 0.487 at 2x), and the same in Erik's play.
   That is about 5% of the guest's 11 ms. In Erik's dip seconds the guest time rises by about 2.5 ms (9.2 to
   11.7) while the store stays at 0.51. The dips do not come from the store.
2. The code agrees, and the brief's premise is wrong here. `store_depth` (vulkan_renderer.cpp ~7382) already reads
   only the 480x272 centre texels (`centre_texel` for each row and column). It does not convert the target's full
   1920x1088. A GPU reduction to 480x272 would save at most the 0.5 ms, and the cache misses behind that cost are
   mostly the same at both scales. What does grow at 4x is the full-extent `vkCmdCopyImageToBuffer`, which is GPU
   time (copy 0.13 to 0.20 ms), not guest time.
3. What grows with scale is the GPU. `gpu` goes from 3.95 to 6.18 ms. The `fence` stall goes from 1.97 to 3.93 ms:
   this is write_back_depth waiting for the frame before's fence (`wait_fence(ready->fence, ...)`). frame_stats
   counts it under `wait` (`add_wait_time`), not `guest`. The guest figure barely moves with scale (10.84 to 11.03),
   so the brief's goal of making 4x converge on 2x does not depend on the guest's slice.

**On B (not started, because the caller said to stop at this condition).** The probe makes the sink's case
stronger. Resyncs run at 17.4/s at both scales, against 5.18/s in 079's run, with `silent=0`: every shortfall is an
uncounted skip. B does not depend on A and could go ahead as its own task.

Changed: docs/tasks/080-guest-budget-and-sink-grace.md (this Result). Nothing else.

Verify output: not run. The task stopped at the escalation condition with no change to verify. The baseline's own
gate runs are above (stutter_check 4x FAIL, 2x PASS).

Open questions:
- What should the 4x slice target? The fence wait for the frame before (a full frame of GPU at 4x), which would
  mean the depth copy two frames late or the write-back on another thread? The GPU frame cost at 4x? Or the guest's
  scale-independent ~11 ms, and what in the effect storms swells it (a profile of the guest thread, not the
  renderer)?
- Should B be re-briefed alone as 0024-audio-sink-grace?
- The sweep's race runs at 78.7% (4x) and 89.5% (2x) speed, against Erik's 98 to 99% in play. The harness's cost,
  noted in 079, still makes the sweep a pessimistic stand-in.

## Review

Merged d8fe8fc (2026-10-12). The third consecutive block-or-redirect earned by characterizing first, and the second
brief premise of the planning session's to die on primary evidence: store_depth already reads only the centre
texels, so A targeted a 0.5 ms slice that does not move with scale or with the dips. The baseline table is the
deliverable — the guest's ~11 ms is scale-independent, Erik's dips add ~2.5 ms of unnamed guest work in effect
storms, 4x costs GPU time and the depth fence wait, and the sink skips 17.4/s with silent=0 in the gate's config.
B goes ahead alone as task 081 (0024-audio-sink-grace): it never depended on A, and both 079's and 080's own
measurements make its case. The dip profile (what swells the guest in effect storms: the SAS voices of the
explosions are the natural suspect, being both guest work and audio demand in one) is the follow-up after 081, and
it needs a guest-side instrument, not a renderer one. The 4x fence wait is real but not the dips' cause; it waits
with the GPU figures for whoever next works the 4x path.

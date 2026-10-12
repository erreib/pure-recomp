# 080: The guest's frame budget at scale, and the sink's grace

Milestone: Windows fidelity (Erik, 2026-10-12: the slowdown and the click are one defect, task 079's finding) |
Branch: task/080-guest-budget-and-sink-grace | Status: OPEN

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

# 077: The Vulkan block-transfer readback stalls the race

Milestone: Windows fidelity (Erik, 2026-10-12: the race stutters on the rig) | Branch: task/077-vulkan-readback-stutter | Status: OPEN

## Goal
A race on the Windows rig (RTX 3080, the Vulkan renderer) misses its frame budget on about 15% of frames: Erik heard
the audio stutter and the planning session measured it. The cause is `VulkanRenderer::read_back_framebuffer`
(vendor/portablekit/host/gpu/vulkan_renderer.cpp, the body around line 7208): the game issues two GE block transfers
from a framebuffer every race frame, and each one submits the half-recorded frame and fence-waits the whole queue
before copying — a synchronous drain of 9 to 16 ms, twice a frame, measured by `PURE_TRACE_STALLS` (`readback 10.72
x2` on a 38 ms frame is typical; the full probes are reproduced below). The drain, not the bytes: at internal scale
1x the stall is the same (~10 ms), so shrinking the copy does not help. The Metal backend has the same architecture
but Apple-silicon unified memory makes the wait invisible; no suite measures wall time, which is why nothing caught
it. After this task a race on the Vulkan renderer holds 60 fps with the shipped defaults, the guest-visible bytes
of the transfer are exactly what they were (or a trace proves the game never reads them and the Result says so), a
switch restores the old synchronous path, and a check proves the smoothness and will catch a regression.

The planning session's probes (2026-10-12, the rig; each a swept race, `tools/campaign_sweep.py single_race
vineta_k --no-damage --shell vulkan --backend vulkan` with `PURE_PERF=log PURE_TRACE_STALLS=1
PURE_TRACE_STALLS_MS=25 PURE_NO_AUDIO=0 PURE_SIXTY_FPS=1 PURE_SMOOTH_FLASHES=1 PURE_TEXTURE_DETAIL=1`):
- defaults (FIFO, auto scale = 2x): 1685 frames over 25 ms after flip 6200, typical line `[slow-frame] 6253 38.0 ms
  | guest 11.7 render 4.3 wait 22.0 | readback 10.72 x2 pacing 16.55 x6`
- mailbox in place of FIFO: unchanged. audio off: unchanged. internal scale 1x: unchanged (readback still ~10 ms;
  1517 slow frames)
- the per-second `[stalls]` lines put readback at 1.6 to 6.4 ms a frame averaged, x2 a frame, race only; menus clean

## Read first
- CLAUDE.md, docs/windows.md ("Updating the rig": the 2026-10-12 session's findings), docs/status.md (the E3
  follow-up row: the write-back costs measured by bytes; E4's rig note: the game clock loses about 1% to stalls the
  pacer forgives — this task's stall is that loss), patches/README.md (the series; 0011-vulkan-texture-mapping and
  0015-vulkan-fb-texture-wrap as the model rows), docs/upstream.md
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `read_back_framebuffer` (the drain: `vkQueueSubmit` then
  `wait_fence(impl.frame_fence, "a framebuffer read back")` with `perf::Stall::Readback` around it),
  `record_writeback`, `collect_writeback` (an async half already exists: an older slot's write-back is taken
  without a new wait), `take_writeback`, `store_frame`, `writeback_ready` / `writeback_has_pixels` (a write-back
  can already sit ready), `Impl::FrameSlot` (`writeback_in_flight`, `writeback_recorded`), `end_gpu_segment` /
  `frame_batch` (what the drained submit contains), `PURE_NO_FB_TEXTURES` (the kill switch at the top of
  `read_back_framebuffer`), `PURE_TRACE_FB_TEXTURES` (the trace at its bottom)
- vendor/portablekit/host/gpu/vulkan_ge_backend.cpp (`block_transfer` hands `transfer.source` to the readback),
  vendor/portablekit/host/gpu/ge_backend.hpp (the contract comments for `block_transfer()` and
  `read_back_framebuffer()`: what the kernel expects in guest memory afterwards and who copies what)
- The kernel side of a block transfer: where `block_transfer` is called from (grep; likely the GE display-list
  handler) — what reads the destination afterwards, CPU or GE
- vendor/portablekit/host/perf/frame_stats.hpp (`Stall`, `PURE_TRACE_STALLS`, `PURE_TRACE_STALLS_MS`),
  vendor/portablekit/host/kernel/kernel.cpp around line 500 (the pacer: `ahead_us`, the 100 ms debt drop — why a
  stall also slows the game clock)
- tools/campaign_sweep.py (the probe's vehicle; its own data directory), tools/flash_check.sh (the race lane: how a
  sweep's log is bounded and summarised — the model for the new check), tools/purelib/port.py (ENHANCEMENTS_OFF:
  the pins reach every run; the new check must name its own), tools/patches.sh, docs/verification.md, README.md
  (the tools and switches tables)

## Deliverable
One vendor patch, `patches/0021-vulkan-async-readback.patch` (through `tools/patches.sh export`), its rows in
patches/README.md, a new check, and the docs. Commits per proven stage.
- **First, characterize** (one run, before changing anything): the defaults probe above with
  `PURE_TRACE_FB_TEXTURES=1` and `PURE_TRACE_GE=1` long enough to see the race's two transfers: which framebuffer
  is read, into what destination, and what consumes the destination (GE texture? CPU read? saved?). Paste the
  finding into the Result — it decides the design below.
- **The fix, smallest that holds 60 fps** (in preference order; stop at the first that passes the checks):
  1. If the destination is consumed only by the GE (drawn as a texture, never CPU-read): satisfy the transfer
     GPU-side the way 0015-vulkan-fb-texture-wrap serves framebuffers as textures, and skip the drain; guest
     memory keeps the stale bytes, and the Result proves no CPU read with the trace (escalate if the game reads
     them).
  2. Otherwise make the wait cheap instead of whole-queue: take a write-back recorded and submitted at the END of
     the previous frame (the `collect_writeback` path — the mechanism is half-built: `writeback_ready`,
     `writeback_has_pixels`), so the bytes the game sees are one frame old. That changes guest-visible data, so it
     must be proven harmless: the suite to the digit, and the transfer's consumers by eye in the race. If the
     suite moves, escalate with the scene and the fraction rather than widening anything.
  3. If neither holds, reduce the drain itself (submit the frame's work eagerly in segments so the mid-frame fence
     has little left to wait for) and say in the Result what the stall became.
- **The switch**: `PURE_SYNC_READBACK=1` restores the old synchronous path exactly (the new behaviour is the
  default). README.md's switches table gains the row. The checks that need byte-exact guest memory can pin it.
- **The check**, `tools/stutter_check.sh`: one swept race (the probe's exact environment and pins, sound on, the
  shipped defaults on), reading the sweep's log: PASS when, after the race's first paced flip, (a) the seconds
  whose worst frame exceeds 25 ms are at most 1 in 10, and (b) the `[stalls]` readback mean is at most 2 ms a
  frame; prints both figures and the worst second either way. About 6 minutes. `--shell` and `--backend` as
  flash_check takes them (default vulkan/vulkan under MINGW, metal/metal elsewhere so the Mac can run it too).
- **Docs**: patches/README.md (both tables; the upstream column — this is an upstream candidate), docs/windows.md
  (the rig checklist gains the check; the 2026-10-12 findings paragraph gains one line naming the fix),
  docs/verification.md (the new check in the table and in "Which path for which change"), README.md (the tools
  table row and the switches row), docs/status.md is NOT yours (the planning session records the outcome).
  `python3 tools/docs_check.py` and `tools/patches.sh check` pass.

## Acceptance criteria
- [ ] `tools/stutter_check.sh` PASS on the rig with the figures in the Result (before the fix it FAILs: run it once
      unfixed and paste that too — the FAIL path proven)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` PASS 7/7, the figures unchanged to the digit from
      out/071-suite.log's scenes (the pins are on: the fix must not move a pixel there)
- [ ] `tools/frame_regress.sh --all-scenes` headless PASS 18/18
- [ ] `tools/flash_check.sh --shell vulkan` PASS (fade 57 flips off, 0 on: the readback change must not disturb the
      fade's two-vblank rhythm)
- [ ] `tools/framerate_check.sh --shell vulkan` PASS; `--race` run once and its game-clock figures in the Result
      (expected to land inside 0.99 to 1.01 now that the forgiven stalls are gone; if still outside, say by how
      much — do not change the bound)
- [ ] with `PURE_SYNC_READBACK=1` a probe run shows the old stall again (the switch proven, the line in the Result)
- [ ] `tools/patches.sh check` and `python3 tools/docs_check.py` pass; no change under vendor/ beyond the patch

## Verify
`tools/stutter_check.sh && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/flash_check.sh --shell vulkan && tools/framerate_check.sh --shell vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/vulkan_renderer.hpp,
  vendor/portablekit/host/gpu/vulkan_ge_backend.cpp: only through `tools/patches.sh export
  0021-vulkan-async-readback`; commit patches/, never vendor/
- patches/0021-vulkan-async-readback.patch (new), patches/README.md
- tools/stutter_check.sh (new)
- docs/windows.md, docs/verification.md, README.md, docs/tasks/077-vulkan-readback-stutter.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, src/ (the profile does not change), tools/purelib/,
  tools/campaign_sweep.py, tools/flash_check.sh, tools/framerate_check.sh, tools/frame_regress.sh,
  vendor/portablekit/host/kernel/ (the pacer's forgiveness stays), vendor/portablekit/host/gpu/ge_backend.hpp (the
  contract; if the fix needs it changed, escalate), ref/, docs/decisions.md, docs/status.md, any vendor file not
  listed, anything not listed above

## Estimated turns
60

## Escalate when
- the characterization shows the game's CPU reads the transferred bytes and design 2's one-frame-old bytes move any
  suite scene (report the consumer, the scene and the fraction)
- the fix needs the GE backend contract (ge_backend.hpp) or the kernel's scheduler changed
- the drain is not the dominant stall after all on a fresh probe (report the new [slow-frame] shape before changing
  anything)
- a full rebuild or the corpus is needed (it should not be: this is renderer-only)

## Result

Status: (draft: characterization done, the fix in progress)

### Characterization (2026-10-12, the rig, one swept race before any change)
The defaults probe (`tools/campaign_sweep.py single_race vineta_k --no-damage --shell vulkan --backend vulkan`,
`PURE_PERF=log PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=25 PURE_NO_AUDIO=0 PURE_SIXTY_FPS=1 PURE_SMOOTH_FLASHES=1
PURE_TEXTURE_DETAIL=1`) with `PURE_TRACE_FB_TEXTURES=1` (it prints every GE block transfer, `[fbtex] block transfer
SRC -> DST`, and every `read framebuffer ... back for a block transfer`) and `PSPRECOMP_TRACE_VRAM_READS=1` (guest
CPU loads from VRAM by 64 KiB block). `PURE_TRACE_GE=1` was left off: it prints per draw and would have run the sweep
over its 400000-line bound; the fbtex trace prints the transfers themselves. PASS (no damage), 3 laps, 374 s.
- **The brief's premise does not hold: `read_back_framebuffer` never runs in the race.** 0 `read framebuffer` lines
  in 33199. All 7319 block transfers in the run are main RAM to VRAM (texture uploads, e.g. `0x968a4b0 -> 0x41e68c0
  32x64 x2`); none has a source in VRAM, so none reaches the readback (the source is in no render target).
- **The `readback x2` stall is the depth write-back** (`write_back_depth`, the other user of `perf::Stall::Readback`;
  it counts the fence wait with `add_wait_time` and the whole call with `note_stall`, hence `x2` for ONE call a
  frame). The log names it: `[render] depth written back to guest memory at 0x4110000 for signal 0x200` (the lens
  flare's CPU depth test, task 019), once per race frame at the GE SIGNAL, and the same submit-and-fence-wait drain
  of the half-recorded frame. Shape unchanged from the planning probe: 2919 `[slow-frame]` lines over 25 ms after
  flip 6200, typical `[slow-frame] 6204 28.6 ms | guest 18.0 render 5.2 wait 5.4 | ... readback 10.60 x2`; the
  `[stalls]` lines' readback mean over the race 7.55 ms a frame (max 12.60).
- **The consumer is the guest CPU**: `[vram] guest reads 0x4120000-0x4130000: 300 to 600 loads` a second through the
  race (the depth buffer at 0x04110000, stride 512, runs to 0x04154000), i.e. a handful of depth samples a frame.
- So design 1 (GE-only consumer) cannot apply. Design 2 applies, to the depth write-back: record the depth copy at
  the SIGNAL without submitting, and store the copy recorded in the previous frame (its fence is long signalled),
  so the flare's depth test sees depth one frame old. The guest-visible bytes change (one frame late), so the suite
  must hold to the digit (escalate otherwise). `read_back_framebuffer` is left as it is (it does not run here).

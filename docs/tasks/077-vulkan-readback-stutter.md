# 077: The Vulkan block-transfer readback stalls the race

Milestone: Windows fidelity (Erik, 2026-10-12: the race stutters on the rig) | Branch: task/077-vulkan-readback-stutter | Status: MERGED (685f2a3, 2026-10-12)

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

Status: PARTIAL

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

### The check, unfixed (the FAIL path proven)
`tools/stutter_check.sh --out out/077/unfixed` on the rig before the fix (303 s):
```
race: PASS, paced from flip 6100; 232 seconds, 11304 frames
(a) seconds with a frame over 25 ms: 232 of 232 (100.0%)
(b) readback: 7.38 ms a frame
worst second: #228 after the paced flip, frame avg 31.5 max 216.8 ms
stutter_check: FAIL (232 of 232 seconds over 25 ms, readback 7.38 ms a frame; 232 of 232 seconds have a frame over 25 ms (at most 10%); readback 7.38 ms a frame (at most 2))
```

### Changed
- patches/0021-vulkan-async-readback.patch (new; vendor/portablekit/host/gpu/vulkan_renderer.cpp only), patches/README.md
  (the series row, upstream: candidate; the section)
- tools/stutter_check.sh (new)
- README.md (tools row, `PURE_SYNC_READBACK` row), docs/verification.md (table row, "Which path" Vulkan row),
  docs/windows.md (the rig checklist item naming the real cause and the fix)

### The fix (design 2, applied to the depth write-back)
`write_back_depth` no longer submits and fence-waits mid-frame: each frame slot has its own depth buffer; the SIGNAL
records the copy into the frame and stores the newest copy an earlier frame recorded (its fence waited, normally
long signalled; counted as `fence`). The first SIGNAL stores nothing. `PURE_SYNC_READBACK=1` takes the old path
exactly (the start-up line says `synchronous` or `a frame late`). `read_back_framebuffer` is untouched (it never runs
in the race).

### Figures
- Readback stall, rig, `tools/stutter_check.sh` on the swept race: **7.38 ms a frame unfixed, 0.00 fixed**.
  Race render rate ~66 fps (`[perf] fps 64.5 to 68.3 game 60.0`, `frame avg 14.6 to 15.5 ms`) against ~30 to 37
  unfixed.
- **stutter_check (a) still FAILs after the fix** (out/077/fixed1, re-read with the committed check):
  `(a) seconds with a frame over 25 ms: 118 of 209 (56.5%); apart, the live-file flips (a multiple of 10) over it:
  960, worst 187.2 ms` / `(b) readback: 0.00 ms a frame` / `stutter_check: FAIL (118 of 209 seconds over 25 ms,
  readback 0.00 ms a frame; ...)`. What remains is not the readback: (1) every flip that is a multiple of 10 has
  15 to 25 ms of render time in both runs (946 of 951 render spikes after flip 6300 fixed, 989 of 1014 unfixed): the
  window input script's read of the sweep's live file (`PURE_INPUT_LIVE`, host/ui/input_script.cpp `s.frame % 10u`,
  host/shell/script_steps.cpp `read_live` opens the file each time). A player has no live file; the check now
  leaves those flips out and prints them apart. (2) the flip after each of those: 114 of the 146 other slow frames
  are at flip%10 == 1 with `pacing 13 to 17 ms x5-6` (the pacer realigning after the long frame) — a knock-on of
  (1), still counted by the check. (3) about 30 others over 209 s: pacing waits of 14 to 17 ms and four render
  spikes of 110 to 176 ms (no stall named; compiles or loads). The stutter_check rerun was not repeated after the
  check's edit: the fixed1 log was re-parsed instead.
- `tools/frame_regress.sh --shell vulkan --backend vulkan` (it runs all 18 scenes on this shell): **17/18**, FAIL on
  zone_change 0.1078 (limit 0.10, measured 0.052). Not reproducible: re-run alone on the async default 0.0475 PASS;
  with `PURE_SYNC_READBACK=1` (zone_change, zone_hud, race_hud) 0.0254, 0.0541, 0.0467 PASS. So the windowed suite
  on the rig moves by more than the depth lag between runs with either path (against out/071-suite.log: race_hud
  0.0502 -> 0.0500, tt_hud 0.0481 -> 0.0469, fp_hud 0.0600 -> 0.0582, zone_hud 0.0480 -> 0.0461 fixed; race_hud
  0.0467, zone_hud 0.0541 synchronous), and "unchanged to the digit" cannot be shown here in either direction.
- `tools/flash_check.sh --shell vulkan`: PASS (fade 58 flips off, 0 on; the race and its HUD in both).
- `tools/framerate_check.sh --shell vulkan`: PASS (frontend 33.4/33.4 ms, race 33.4/16.7 ms and 29.97/59.95 flips a
  second, off/on; the HUD drawn at 60).
- `tools/patches.sh check`: ok, 21 patches. `python3 tools/docs_check.py`: PASS.
- Not run (turns): `tools/framerate_check.sh --shell vulkan --race` (the game-clock figure), `tools/frame_regress.sh
  --all-scenes` headless (the patch is Vulkan-only; headless runs the Metal backend), and a stall probe with
  `PURE_SYNC_READBACK=1` showing the readback return (the switch is proven only by the suite runs above taking it).

### Verify output
The Verify line stops at its first command (stutter_check FAIL, figures above). The rest run separately:
```
stutter_check: FAIL (118 of 209 seconds over 25 ms, readback 0.00 ms a frame; 118 of 209 seconds have a frame over 25 ms (at most 10%))
zone_hud     5260    0.0461   0.09   32     0.045 +0.0011  PASS
zone_change   5679    0.1078   0.10   32     0.052 +0.0558  FAIL
frame regression: FAIL, 17/18 scenes pass, shell vulkan, backend vulkan (9m 0s)
zone_change   5679    0.0475   0.10   32     0.052 -0.0045  PASS   (re-run alone)
frame regression: PASS, 1/1 scenes pass, shell vulkan, backend vulkan (1m 9s)
flash_check: PASS (fade 58 flips off, 0 on; the race and its HUD in both)
framerate_check: PASS (frontend 33.4/33.4 ms, race 33.4/16.7 ms and 29.97/59.95 flips a second, off/on; the HUD drawn at 60)
ok: 21 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 33 files, 0 findings: PASS
```

### Open questions
1. The brief's premise was wrong: the stall is the depth write-back (lens flare, CPU-read), not a block-transfer
   readback. The fix gives the game depth one frame old. Accept that for the flare (by eye in a race: does the flare
   flicker when the sun passes behind scenery?), or keep it per game?
2. stutter_check's (a) cannot pass on a swept race while the follower's live file costs a 15 to 25 ms frame every 10
   flips plus the pacer's realign frame after it. Options: leave the realign flip out as well (then ~30 seconds of
   209 remain, about 14%: still over 1 in 10), make `read_live` cheap (vendor/host/shell, outside this brief), or
   bound (a) differently. The planner's call; the bound was not changed.
3. The windowed Vulkan suite is not reproducible to the digit run to run on the rig (zone_change 0.025 to 0.108), so
   the brief's "unchanged to the digit" criterion needs a different baseline (several runs, or headless replay).
4. Still to run: framerate_check --race, the headless --all-scenes suite, and a stall probe with PURE_SYNC_READBACK=1.

## Review

Merged 685f2a3 (2026-10-12) after the review closed the Result's open items on the branch:
- **The remaining gates, run by the review on the rig:** the 18-scene suite PASS 18/18 on the fix (8m 59s; the 13
  non-race scenes within ±0.0008 of the column, the race scenes within their limits with tt_hud +0.0257 the largest
  move — inside the windowed variance the Result documents, which swings zone_change by 0.08 on the synchronous path
  too). `tools/framerate_check.sh --shell vulkan --race` PASS: the game clock 0.9919/0.9946 against the 0.99 bound it
  failed twice before the fix (0.9864 to 0.9921) — the forgiven stall was the drain, as diagnosed. The sync probe:
  `PURE_SYNC_READBACK=1 tools/stutter_check.sh` FAILs with the stall back (readback 7.24 ms a frame, 63 of 238
  seconds; the unfixed figures were 7.38 and 65 of 232), so the switch restores the old path.
- **A review fix on the branch (f73d069):** stutter_check judges a frame without its own pacing sleeps — the pacer
  sleeps only when the game is ahead of real time, so a realign frame is the schedule holding, not a stutter. With
  that, the committed check PASSes the fix end to end (8 of 222 seconds over 25 ms, readback 0.00) and still FAILs
  the unfixed log on both bounds. The Result's open question 2 is thereby answered: the bound stands, the pacing is
  taken off.
- **Open question 1 (one-frame-old depth and the lens flare) stays with Erik:** watch a race for flare flicker as
  the sun passes behind scenery. Open question 3 (a windowed baseline sturdier than "to the digit") is a tools
  follow-up for the Mac session. The brief's premise was wrong (block transfers never reach the readback; the depth
  write-back was the stall) and the worker's characterization-first order caught it — the brief's design 2 applied
  to the right call.
- The stutter probe logs are under out/077/ and out/stutter_check/ on the rig.

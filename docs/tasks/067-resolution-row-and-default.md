# 067: The Resolution row for the Metal backend, Auto as this game's default, the perf run (E3, step 3)

Milestone: E3 (D-015) | Branch: task/067-resolution-row-and-default | Status: OPEN

## Goal
Task 066 gave the Metal backend an internal scale, read once at start from `video.internal_scale`, whose default is
the framework's 2. After this task the Esc menu's Resolution row (Auto, x1 to x6) shows under the Metal shell and
changes the scale live; this game's default is Auto, so the packed app draws at the display's resolution out of the
box; and the on-screen frame timing at Auto is measured with the window visible, for the record.

## Read first
- CLAUDE.md, docs/decisions.md (D-014, D-015), docs/tasks/064-menu-rows-by-capability.md (the gating pattern and
  its patch), docs/tasks/066-metal-internal-scale.md (Result and Review: Auto, the scale line, open questions 4
  to 6), docs/metal-backend.md ("Internal scale", "The Metal shell", "Frame times")
- vendor/portablekit/host/ui/menu.cpp (`video()`: the Resolution row and its `renderer()` gate, "Restore video
  defaults"), vendor/portablekit/host/gpu/ge_backend.hpp (`BackendConfig`, the `GeBackend` virtuals),
  vendor/portablekit/host/hle/hle_media.cpp (`active_backend()`, where `BackendConfig::internal_scale` is filled),
  vendor/portablekit/host/settings/settings.cpp (`defaults_for`, `parse_scale`), host/profile.hpp (`GameProfile`)
- src/gpu/metal_backend.{hpp,mm} (`scale_`, `internal_scale(config)`, the targets map), src/profile/pure_profile.cpp
- tools/frame_times.py, tools/scale_check.sh, tools/menu_check.sh (the expected lists: the Video tab gains a row)

## Deliverable
1. **Patch `0017-internal-scale-by-backend`** (vendor): `GeBackend` gains `supports_internal_scale()` (default
   false) and `set_internal_scale(std::uint32_t)` (default no-op); the Vulkan backend answers true and forwards to
   the renderer; the menu's Resolution row, its value text and the restore line gate on the active backend's answer
   instead of `renderer() != nullptr` (the texture filter and texture pack rows keep their renderer gate), and call
   the backend's setter. `GameProfile` gains `default_internal_scale` (optional; the framework's games keep 2) that
   `defaults_for` applies. `tools/patches.sh export`, patches/README.md, docs/upstream.md.
2. **The Metal backend** answers true and implements `set_internal_scale`: the scale takes effect at the next frame
   (the targets map cleared, the shared buffers resized; nothing read back mid-frame), Auto as task 066 defines it
   from the shell's drawable, and the start line's clause printed again as `[metal] internal scale now S: ...`
   (once per change; the counts' line set is unchanged otherwise).
3. **The profile** sets `default_internal_scale = 0` (Auto). A data directory that already holds
   `video.internal_scale=2` keeps it (a setting is the player's); say so in docs/release.md's settings row.
4. **The perf run.** With the window visible (not occluded: the trace's shown column says so), the race route in the
   Metal shell at Auto (the drawable 1920x1088 on this Mac, so 4), 60 s of race with `PURE_METAL_TRACE`:
   `tools/frame_times.py --long 25 --fps 60 --from 6250`. Report the mean, p99, longest, frames over 25 ms, and the
   share of rows shown. Repeat at x6 and at x1. If the window gets occluded, rerun; do not report an occluded run as
   the result. The table goes into docs/metal-backend.md "Internal scale".
5. **The checks.** tools/menu_check.sh's expected Video list for the Metal shell gains "Resolution" (the Vulkan list
   already has it); `tools/scale_check.sh` unchanged. README.md's `PURE_INTERNAL_SCALE` row and the settings row in
   docs/release.md say the default is Auto for this game.

## Acceptance criteria
- [ ] `tools/menu_check.sh` PASS (Metal: Video 10 rows with Resolution first) and `--shell vulkan` PASS.
- [ ] A windowed run with the Resolution row changed by script or by hand from Auto to x1 and back logs the scale
      change lines and keeps drawing (no halt, no black frame: a shot after each change at the same screen matches
      the 1x and Auto captures within the scale check's 5%); say how you drove it.
- [ ] `tools/frame_regress.sh` 18/18 headless and `--shell metal --backend metal` 18/18 (test runs stay at 1);
      `tools/refactor_check.sh` PASS at scale 1 (the main checkout's before captures are from the merged 066
      build; take your own on your starting commit).
- [ ] `tools/patches.sh check` ok with 17 patches; the framework's defaults unchanged (the Vulkan backend's answers
      give the menu the same rows as before).
- [ ] The perf table, from un-occluded runs.

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/menu_check.sh && tools/refactor_check.sh`

## May touch
- vendor/portablekit/host/ui/menu.cpp, host/gpu/ge_backend.hpp, host/gpu/ge_backend.cpp (if the defaults live
  there), host/hle/hle_media.cpp (only where the Vulkan backend adapter answers the new virtuals),
  host/settings/settings.cpp, host/profile.hpp: through `tools/patches.sh export 0017-internal-scale-by-backend`
  (commit patches/, never vendor/), patches/README.md, docs/upstream.md
- src/gpu/metal_backend.{hpp,mm}, src/gpu/metal_targets.mm (if clearing the targets needs it), src/profile/pure_profile.cpp
- tools/menu_check.sh (the expected lists), docs/metal-backend.md, docs/release.md, README.md, docs/verification.md

## Must not touch
- vendor/portablekit/include/psprecomp/, the Vulkan renderer's drawing (vulkan_renderer.cpp beyond forwarding
  the setter), src/host/, tools/frame_regress.sh, tools/refactor_check.sh, tools/run_boot.py, tools/scale_check.sh,
  tools/gerec/, ref/, config/

## Estimated turns
40

## Escalate when
A live scale change cannot be made safe mid-frame without a change to the seam's frame protocol (report what the
backend holds across the change); the Vulkan backend adapter cannot answer the virtuals without touching the
renderer's drawing; the perf run cannot be made un-occluded after three tries (report the occluded figures, marked).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

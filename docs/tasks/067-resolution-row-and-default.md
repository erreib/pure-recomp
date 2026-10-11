# 067: The Resolution row for the Metal backend, Auto as this game's default, the perf run (E3, step 3)

Milestone: E3 (D-015) | Branch: task/067-resolution-row-and-default | Status: MERGED (790e628, 2026-10-10)

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
Status: DONE

The branch is task/067-resolution-row-and-default, taken from batch/m2 at 01f0e8e. It has five commits, then this Result:
- 488d93d: patches/0017-internal-scale-by-backend.patch (new), with its row and section in patches/README.md, and a
  Dependencies row, a section and its place in the offer order in docs/upstream.md. The patch touches vendor
  host/gpu/ge_backend.hpp, host/gpu/vulkan_ge_backend.cpp, host/hle/hle_media.cpp, host/profile.hpp,
  host/settings/settings.cpp and host/ui/menu.cpp.
  - `GeBackend` gains `supports_internal_scale()` (default false), `set_internal_scale(std::uint32_t)` (default no-op)
    and `target_size()` (default 480x272). `target_size()` gives the row its value text; see Open questions 2.
  - `gpu::running_backend()` is the menu's way to the backend that draws. It is declared in ge_backend.hpp and is one
    line in hle_media.cpp over its `active_backend()`.
  - The Vulkan backend answers true and forwards `set_internal_scale` and `target_size` to its renderer.
  - In the menu, the Resolution row, its value and its "Restore video defaults" line now gate on the backend's
    answer. The texture filter and texture pack rows keep their `renderer()` gate.
  - `GameProfile::default_internal_scale` is a `std::optional<std::uint32_t>`, unset by default, so the framework's
    games keep 2. `settings::defaults_for` applies it.
- 93020ec: src/gpu/metal_backend.hpp, metal_backend.mm, metal_targets.mm and metal_trace.mm. The Metal backend answers
  true. `set_internal_scale` stores the setting. With nothing drawn since the last flip, which is where the paused
  menu runs, it applies the setting at once. Otherwise it applies it at `begin_frame()`, right after the flip. Each
  `begin_frame()` also lets Auto follow the drawable.
  - `change_scale` moves the screen-wide targets out of the target map into `retired_`. The next frame makes them
    again at the new size. The 1x targets stay.
  - It makes the three shared buffers again at 480S x 272S and prints `[metal] internal scale now S: targets WxH,
    effects 480x272` once per change.
  - Nothing is read back. The pending frame write-back keeps its target and the buffer its copy went into
    (`PendingFrame::buffer`).
  - A flip that has no new display target yet shows the retired one. The retired targets are freed at the first flip
    that shows a target of the new scale. `copy_to_buffer` makes a buffer that is too small again at the right size.
- 901c70c: src/profile/pure_profile.cpp sets `.default_internal_scale = 0u` (Auto). README.md's `PURE_INTERNAL_SCALE`
  row and docs/release.md's settings.ini row say this game's default is Auto and that a file that already holds a
  value keeps it.
- f84c2d3: tools/menu_check.sh's Metal Video list gains Resolution first. The Vulkan list is unchanged. The
  menu_check row in docs/verification.md is updated to match.
- 0390a3e: docs/metal-backend.md. "Internal scale" gains a new subsection, "A change while the game runs", with the
  windowed checks, and the on-screen perf table under "The cost". The Metal shell no longer leaves Resolution out,
  and "What is not done yet" is updated.

Acceptance:
- `tools/menu_check.sh` PASS. Metal: tabs 4, Video 10 with Resolution first, Audio 4, Controls 31, System 12.
  `--shell vulkan` PASS with Video 16 and Controls 37, the same lists as before the task.
- Live change, in the Metal window with input scripts. The scripts are kept outside the repo because config/ is
  Must not touch.
  - Setup: a fresh data directory, so the scale started at the new default, Auto (4), and settings.ini was written
    with `video.internal_scale=auto`. `tools/run_boot.py` sets `PURE_INTERNAL_SCALE=1`, which locks the row, so I ran
    without that default (a wrapper around it). The route is frontend.txt's steps to the title. Each shot is reduced
    to 480x272 by its blocks' centre pixels and compared at tol 24.
  - The change: Esc, Right on Resolution, Esc, then Esc, Left, Esc. The log has `[metal] internal scale now 1: targets
    480x272, effects 480x272`, then `... now 4: targets 1920x1088 ...`. The menu shots show "×1 480×272" and "Auto
    1920×1088".
  - The title 80 frames after the change to x1 differs from a `PURE_INTERNAL_SCALE=1` run's title in 0 of 130560
    pixels. The title after the change back differs from the Auto title before the changes in 0 pixels. The run did
    not halt and showed no black frame.
  - Auto following the window: Window size x2 to x3 and back printed `now 6` (2880x1632 targets) and `now 4`. The title
    at 6 differs from the 1x title in 0.03% of pixels; the title back at 4 matches the earlier one exactly.
  - A data directory whose settings.ini holds `video.internal_scale=2` drew at 2 and kept the value.
- `tools/frame_regress.sh` headless: 18/18. `--shell metal --backend metal`: 18/18 in 19m 51s, with test runs at
  scale 1. Every delta is within ±0.0021 except zone_change at +0.0128 (0.0481 against a 0.10 limit); the windowed
  race scenes vary from run to run.
- `tools/refactor_check.sh` PASS: 18/18 scenes with 0 differing pixels, and the counts are the same (86 [metal]
  lines).
  - The before captures are this worktree's own, taken with the build of the untouched 01f0e8e (sha1 531a9936).
  - Their info.txt reads "01f0e8e+changes" because my source edits had begun while the captures waited 9 minutes for
    another worktree's suite. The binary was not rebuilt until they were done.
- `tools/scale_check.sh 4` still passes: 18/18 within 5%, and the bloom regions move +1.07%, -0.16% and -0.17%.
- `tools/patches.sh check`: ok, 17 patches reproduce the pin.
- Framework defaults unchanged: the Vulkan backend answers true and forwards to its renderer, so the Vulkan shell's
  dump lists the same 16 Video rows as before. The game default only applies when a profile sets it.
- Perf table, Metal shell, window visible. The race route is main_menu.txt + single_race.txt without shots, to flip
  9850, with `PURE_PACED_FROM=6000`, an empty memory stick per run and `PURE_METAL_TRACE`. Each trace was read with
  `tools/frame_times.py --long 25 --fps 60 --from 6250`. No row was occluded in any of the three runs.

| S | Targets | Frames | Mean | 99th pct | Longest | Over 25 ms | Rows shown | On screen: mean, 99th, longest | GPU waits a frame | Depth wait median |
|---|---|---|---|---|---|---|---|---|---|---|
| Auto (4) | 1920x1088 | 3601 | 16.68 ms | 18.35 ms | 19.39 ms | 0 | 3600 of 3601 (99.97%) | 16.68, 16.67, 25.00 ms | 0.94 ms | 0.96 ms |
| 6 | 2880x1632 | 3601 | 16.68 ms | 18.43 ms | 21.23 ms | 0 | 3601 of 3601 | 16.68, 16.67, 25.00 ms | 1.24 ms | 1.03 ms |
| 1 | 480x272 | 3601 | 16.68 ms | 18.55 ms | 20.59 ms | 0 | 3601 of 3601 | 16.68, 16.67, 25.00 ms | 0.77 ms | 0.86 ms |

Verify output (last 20 lines, `tools/verify_task.sh 067`). Earlier in the same run: `frame regression: PASS, 18/18
scenes pass, shell headless, backend metal (0m 21s)` and `menu_check: PASS`, with Video 10:
```
fp_track_select             0  PASS
lang                        0  PASS
league_select               0  PASS
main_menu                   0  PASS
profile                     0  PASS
race_hud                    0  PASS
single_player               0  PASS
team_select                 0  PASS
title                       0  PASS
tournament_select           0  PASS
track_select                0  PASS
tt_hud                      0  PASS
tt_track_select             0  PASS
zone_change                 0  PASS
zone_hud                    0  PASS
zone_track_select           0  PASS

counts: the same in every route (86 [metal] lines)
refactor check: PASS, 18/18 scenes with 0 differing pixels, counts PASS (0m 22s)
verify 067: PASS
```

Open questions:
1. File placement. "May touch" names hle_media.cpp as the place where the Vulkan backend adapter answers the new
   virtuals, but the adapter is vulkan_ge_backend.cpp, so it answers there; I made no change to the renderer.
   hle_media.cpp carries one line: `gpu::running_backend()`, which the menu needs to reach the backend. I declared
   it in ge_backend.hpp because hle_common.hpp is not in May touch.
2. A third virtual, `target_size()`, beyond the two the brief names. The row's value text ("Auto 1920×1088") showed
   `renderer()->target_size()`, which is null under the Metal shell. Its default is 480x272.
3. Auto follows the drawable at every flip, not only at start. The row's own text says Auto "follows" the window. A
   resize or full screen changes the scale at the next flip; full screen here gives 6.
4. Vulkan shell with the Metal, null or record backend:
   - With the Metal backend, the row now changes the Metal backend's scale (Auto is 1 there) rather than the Vulkan
     renderer's. The shell's target stays at its start scale, and `show_in_shell` scales Metal's picture into it as
     before.
   - The null and record backends answer no, so the row is hidden there, where the renderer gate used to show it.
   - The record backend could forward to its inner backend. Then a change made during a recording would be missing
     from the .gerec file, and record_backend.cpp is outside May touch, so I left it.
5. settings.hpp's comment on `defaults_for` ("Desktop is Settings{} as declared above") is now inexact for a game
   that sets `default_internal_scale`. settings.hpp is outside May touch.
6. The Auto default reaches the Vulkan path too: our Vulkan renderer also starts at Auto, which follows the window.
   The Vulkan suite and the checks still draw at 1 through run_boot. Task 068's effects at 1x apply to that path.
7. A change discards the screen-wide targets' contents. A game frame that draws over the previous picture instead
   of clearing would start from black once, and a bind of a retired target's memory decodes guest memory until the
   target is drawn again. Neither showed in the runs.
8. menu_check runs with `PURE_INTERNAL_SCALE=1`, so it sees the row locked. It checks that the row is there, not a
   change. If a check of the change is wanted, it needs a pad script under config/pad_scripts/ (Must not touch here)
   and a way past run_boot's default.
9. The perf runs needed the window in front.
   - Most of the session, Erik's screen was on Chrome's full-screen Space, or locked. A game window opened on another
     desktop and never reached the screen, and asking the process to come forward (NSRunningApplication) had no
     effect.
   - Earlier runs at Auto were not visible, and one reused the worktree's game/ms0 and went off the route. I deleted
     the saves those runs left in game/ms0.
   - Another Auto run, and one each at 6 and 1, ran while the screen was locked. They are not in the table.
   - The runs in the table are from when the desktop was up: the Auto run from an ungated attempt that turned out
     fully visible, and the 6 and 1 runs from a gated launch that checked the game's window was the frontmost
     ordinary window 10 s in.
   - The hidden runs' backend figures were the same (means 16.68 to 17.22 ms). Their only frames over 25 ms waited
     for a drawable that macOS held back while the window was hidden.

## Review
Verify rerun: from the main checkout after the merge and patch 0017 applied to the vendor tree (17 patches
reproduce the pin), 2026-10-10: PASS (headless 18/18, menu_check Metal Video 10 with Resolution first, refactor
check 0 differing pixels). The gate: `--shell metal --backend metal` 18/18; `--shell vulkan --backend vulkan`
18/18 (the Vulkan runs at their 2x: Auto in a 960x544 window); `tools/hud_check.sh` 61/61; `tools/menu_check.sh`
PASS in both shells; `tools/gerec/metal_check.sh` PASS; `tools/scale_check.sh 4` PASS.
Spot-read: the three virtuals default to today's behaviour; `running_backend()` is one line over
`active_backend()`; the Vulkan adapter forwards to its renderer; `default_internal_scale` optional, unset for the
framework's games; `change_scale` retires the screen-wide targets and frees them at the first flip of the new
size, the pending write-back keeping its copy. The perf table was taken with the window visible (rows shown
3600/3601, 3601, 3601).
Merged: `git merge --no-ff` into batch/m2, 790e628.
Notes: open question 2 (`target_size()`) accepted as the row's value text; 3 (Auto follows the drawable at every
flip) is D-015's intent; 4 (the record backend answers no, so the row hides under it) is right: a change during a
recording would be missing from the file. Follow-ups: settings.hpp's comment on `defaults_for`; a scripted check
of a live change needs a pad script and a way past run_boot's pin; a game frame drawn over the previous picture
would start from black once after a change (none seen).

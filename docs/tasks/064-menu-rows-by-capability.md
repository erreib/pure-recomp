# 064: The Esc menu shows only what this game and this shell can do

Milestone: enhancements (D-014) | Branch: task/064-menu-rows-by-capability | Status: MERGED (b92537a, 2026-10-10)

## Goal
The framework's Esc menu (vendor/portablekit/host/ui/menu.cpp) draws rows for Monster Hunter's features and for
host features the Metal shell does not implement, and its System tab says "Vulkan on" an Apple GPU. After this task
a row is drawn only when its feature exists, decided by two sets of gates: the game profile's (what the game has)
and the shell's (what the host implements). The framework's own games are unchanged by default, so the patch is an
upstream candidate.

## The audit (Fable, 2026-10-10, the menu as the packed app 0.1.0-0fa3e4f shows it on macOS)

| Tab | Row | Verdict | Gate |
|---|---|---|---|
| Video | Resolution, Texture filter, Texture pack (+ its rows) | already hidden under the Metal shell (`renderer()` null); keep on Vulkan | as is |
| Video | Display, Window size, Aspect ratio, Scaling filter, Vsync, Game speed, Fast loading | keep | none |
| Video | Aspect ratio's Fill choice | Metal takes Fill as Original: offer Original and Stretch only there | shell `supports_aspect(Aspect)` |
| Video | Frame rate, Lower when behind | Metal ignores `set_frame_rate`: hide there; keep on Vulkan (interpolation to 90/120 Hz is a real option) | shell `supports_frame_interpolation()` |
| Video | Performance | Metal's `set_perf_overlay` does nothing: hide there (`PURE_PERF=log` stays a switch) | shell `supports_perf_overlay()` |
| Video | Restore video defaults | keep; restores only the rows shown | none |
| Audio | Output, Volume, Mute, Device, Restore | keep | none |
| Controls | Connected, Confirm button, Stick dead zone, Trigger point | keep | none |
| Controls | Trigger profile | already hidden (the profile has no trigger profiles) | as is |
| Controls | Right stick: Camera / D-pad / Off | drop the Camera choice (the HD release's camera is Monster Hunter's); D-pad and Off stay | profile `features.right_stick_camera` |
| Controls | Analog camera, Camera speed, Aim speed, Invert camera (2) | already hidden (no `camera` driver) | as is |
| Controls | Right stick D-pad point | keep (with the D-pad choice) | none |
| Controls | Pilot name: When the game asks for a name, the name | keep: the game imports the system keyboard (sceUtilityOsk*, config/imports.csv) | none |
| Controls | Keyboard and mouse: Mouse, Mouse sensitivity, Invert mouse (2) | the pointer capture and the camera rows are for a mouse camera the game has not: hide the four; the bindings list below them stays (mouse buttons bind to actions) | profile `features.mouse_camera` |
| Controls | the bindings list, Esc / F3 info rows, Use the classic keyboard layout, Restore | keep; the F3 row only where the overlay exists | shell `supports_perf_overlay()` |
| Controls | Touch screen: On-screen controls, opacity, size, Touch camera speed | hide where the shell has no touch controls (Metal: `touch_controls_visible` false; the Vulkan shell on a desktop without a touch device too) | shell `supports_touch()` |
| Network | the whole tab (Play together's halls, Ad hoc play, Server, Nickname, Status) | hide: ad hoc play is not a feature of this port yet (the game's sceNet* imports are stubs); the tab bar shows four tabs | profile `features.adhoc` |
| System | Resume, Pause the game when the menu opens, Save the log, Open the data folder, Set up game data again, Quit, Saves, About | keep | none |
| System | Pause during multiplayer | hide with the Network tab | profile `features.adhoc` |
| System | Graphics: "Vulkan on <device>" | say the shell's API: "Metal on Apple M4 Pro", "Vulkan on NVIDIA ..." | shell `api_name()` (or `name()` capitalised) |

## Read first
- docs/decisions.md (D-014), docs/controls.md, docs/metal-backend.md ("The Metal shell": what it leaves out),
  docs/upstream.md (the patch table's shape), patches/README.md
- vendor/portablekit/host/ui/menu.cpp (video(), controls(), network(), system(), frame()'s tab bar),
  vendor/portablekit/host/profile.hpp (`GameProfile`: `camera`, `trigger_profiles`, `adhoc_product_code`),
  vendor/portablekit/host/shell/shell.hpp (the `Shell` virtuals), the Vulkan shell's implementation of them
  (vendor host/shell/ or host/gpu/vulkan_renderer.cpp, as docs/vendor-map.md says), src/host/metal_shell.mm
- src/profile/pure_profile.cpp (the `GameProfile` our game fills), src/profile/test_hooks.{hpp,cpp}
- vendor/portablekit/host/ui/input_script.cpp (the `key` step: `N:key Escape` opens the menu in a window)

## Deliverable
1. **Patch `0016-menu-rows-by-capability`** (vendor, through `tools/patches.sh export`): 
   - `GameProfile` gains a `MenuFeatures features` member with defaults that keep the framework's games as they are
     (`adhoc = true`, `right_stick_camera = true`, `mouse_camera = true`); the menu reads them where the table says.
     Hidden rows keep their settings keys and values (settings.ini is unchanged by hiding); a hidden Network tab
     also forces `s.adhoc` off at menu open so the game sees the wireless switch off.
   - `Shell` gains `supports_frame_interpolation()`, `supports_perf_overlay()`, `supports_aspect(settings::Aspect)`,
     `supports_touch()` and `api_name()`, with defaults that return what the Vulkan shell does today (so the
     framework's build is unchanged), and the menu gates the rows the table names on them. The System tab's
     Graphics line reads `api_name() + " on " + device_name()`.
   - A menu-rows dump: when `<prefix>_MENU_DUMP=1` and the menu opens, one line per tab on the console,
     `[menu] Video: Display, Window size, Aspect ratio, ...` (the row labels in draw order, including choice rows'
     labels; the tab bar's names first as `[menu] tabs: Video, Audio, Controls, System`). Test-only; documented in
     README.md's switch table.
2. **The profile and the shell** (ours): `pure_profile.cpp` sets `features{adhoc = false, right_stick_camera =
   false, mouse_camera = false}`; `metal_shell.mm` answers false to interpolation, the overlay, Fill and touch, and
   `api_name()` "Metal".
3. **tools/menu_check.sh** (new): runs the frontend route in the Metal shell's window (`PURE_SHELL=metal`) with an
   input script that presses Escape at the title (`N:key Escape` after "PRESS START" is up, about flip 2100) with
   `PURE_MENU_DUMP=1`, and checks the dump lines against the expected lists for this shell (the table above: no
   Network tab; no Frame rate, Lower when behind, Performance, no Fill; no Camera choice; no Mouse rows; no Touch
   section; Graphics "Metal on"). `--shell vulkan` checks the Vulkan shell's expected lists (Frame rate and
   Performance present; Fill present; no Network tab). Exit 0 when every list matches; print the differences
   otherwise. If the Escape key does not reach the menu from the script, add a test hook
   (`PURE_TEST_OPEN_MENU_AT=<flip>` in src/profile/test_hooks) rather than stop.
4. Docs: docs/controls.md (the rows that no longer show and why, one paragraph), docs/metal-backend.md ("The Metal
   shell": the System line now says Metal; the rows are hidden by the shell's answers), docs/upstream.md (the
   patch's row), README.md (`PURE_MENU_DUMP`), docs/verification.md (menu_check's row), patches/README.md.

## Acceptance criteria
- [ ] `tools/menu_check.sh` PASS in the Metal shell and `--shell vulkan`.
- [ ] `tools/frame_regress.sh` 18/18 headless, and `--shell metal --backend metal` 18/18 (the menu is not open in
      the suite; this proves the shell change drew nothing differently). `tools/hud_check.sh` 61/61.
- [ ] `tools/patches.sh check` ok with 16 patches; the framework's defaults unchanged (every new gate defaults to
      today's behaviour: state in the Result how you checked, e.g. the Vulkan shell's dump with the profile's flags
      temporarily true shows every row the menu had).
- [ ] settings.ini keys unchanged (a settings file from before the task loads and saves the same keys).

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/menu_check.sh`

## May touch
- vendor/portablekit/host/ui/menu.cpp, host/profile.hpp, host/shell/shell.hpp and the Vulkan shell's source (only
  to add the new virtuals' defaults), host/ui/layer.* if the dump needs it: through `tools/patches.sh export
  0016-menu-rows-by-capability` (commit patches/, never vendor/), patches/README.md
- src/profile/pure_profile.cpp, src/profile/test_hooks.{hpp,cpp}, src/host/metal_shell.mm
- tools/menu_check.sh (new), config/pad_scripts/ (a new script for the check only)
- docs/controls.md, docs/metal-backend.md ("The Metal shell"), docs/upstream.md, docs/verification.md, README.md
  (the switch table)

## Must not touch
- vendor/portablekit/include/psprecomp/, src/gpu/, the game's HLE, tools/frame_regress.sh, tools/gerec/, ref/,
  the settings keys or their defaults (hiding a row never changes a value except `adhoc` forced off), anything
  not listed above

## Estimated turns
45

## Escalate when
A row cannot be hidden without changing a setting's value or key; the Vulkan shell's build would change behaviour
for the framework's games (a default that is not today's); the menu's `key Escape` and a test hook both fail to
open the menu in a scripted window run (report what the Layer saw).

## Result
Status: DONE

Changed (branch task/064-menu-rows-by-capability from batch/m2 f0bc2ba, four commits in the brief's order, then this
Result):
- e8e5931 patches/0016-menu-rows-by-capability.patch (new; vendor host/profile.hpp, host/shell/shell.hpp,
  host/ui/menu.cpp), with its row and section in patches/README.md.
  - `GameProfile::features` is a `MenuFeatures` with `adhoc`, `right_stick_camera` and `mouse_camera`, all true by
    default.
  - `Shell` gains `supports_frame_interpolation()`, `supports_perf_overlay()`, `supports_aspect(Aspect)` and
    `supports_touch()` (all true by default). It also gains `api_name()`, which by default is the shell's
    registered name with a capital: "Vulkan" for the Vulkan shell. The defaults are in shell.hpp, so
    vulkan_shell.cpp is untouched.
  - menu.cpp hides the rows the audit table names. The tab bar is built from the tabs shown. A hidden Network tab
    turns `s.adhoc` off at menu open (`note_menu_opened`: save, then `adhoc_apply_settings`). The Graphics line is
    `api_name() + " on " + device_name()`. "Restore video defaults" restores only the rows shown.
  - `<prefix>_MENU_DUMP`: when the menu opens, it prints the tabs, then draws one tab a frame and prints its rows.
    Then the menu goes back to Video with the focus reset.
- 290dbd2 src/profile/pure_profile.cpp (`.features = {.adhoc = false, .right_stick_camera = false,
  .mouse_camera = false}`) and src/host/metal_shell.mm (false for interpolation, the overlay, Fill and touch;
  `api_name()` "Metal").
- 11d62d6 tools/menu_check.sh (new) and config/pad_scripts/menu_check.txt (new).
  - The route: frontend.txt's steps to the title, `2100:key Escape`, a menu shot, then `2170:key Escape`. The run
    ends at flip 2250, with `PURE_PACED_FROM=2050`, and takes about 25 s.
  - The tool waits up to 600 s for another game, compares each dump line with the shell's expected list (`*`
    matches the device name) and prints any difference.
  - The Escape key reached the menu from the script in both shells, so no test hook was needed and test_hooks is
    untouched.
- c02cef1 docs:
  - docs/controls.md: a new "Rows the menu leaves out" paragraph. It also corrects the tab list, the Controls tab's
    rows (now 7 Downs to Move forward and 13 to × (back)), the mouse section, the tuning table's Mouse cell and the E1
    bullet. `tools/controls_check.py` is OK.
  - docs/metal-backend.md ("The Metal shell"), docs/upstream.md (a Dependencies row, a section and its place in the
    offer order), README.md (`PURE_MENU_DUMP`) and docs/verification.md (menu_check's row). `tools/docs_check.py`:
    0 findings.

Acceptance:
- `tools/menu_check.sh`: PASS in the Metal shell. In the Verify run the counts were tabs 4, Video 9, Audio 4,
  Controls 31 and System 12, and Graphics read "Metal on Apple M4 Pro". `--shell vulkan`: PASS, with Video 16 and
  Controls 37.
- `tools/frame_regress.sh` headless: 18/18. `--shell metal --backend metal`: 18/18 (19m 53s), every delta within
  ±0.0124. `tools/hud_check.sh`: 61 of 61 shots.
- `tools/patches.sh check`: ok, 16 patches reproduce the pin.
- Framework defaults unchanged. With patch 0016 applied but before the profile commit (flags at their defaults),
  the Vulkan shell's dump showed every row the old code draws (out/064/vk_defaults.log):
  - tabs: Video, Audio, Controls, Network, System.
  - Video: Resolution, Texture filter, Texture pack and its rows, Frame rate, Lower when behind and Performance.
  - Controls: Right stick (Camera / D-pad / Off), both camera invert rows, Mouse, Mouse sensitivity, both mouse
    invert rows, F3 and the five Touch screen rows.
  - Network: the whole tab.
  - System: Pause during multiplayer and "Graphics (Vulkan on Apple M4 Pro)".
- Fill gate, checked with a temporary no-op `view_aspect_frame` in the profile (not committed): the Vulkan shell
  offered Original / Stretch / Fill and the Metal shell Original / Stretch.
- settings.ini keys unchanged. I copied the main checkout's out/data/hud_check/settings.ini, written by a pre-task
  build, and set `network.adhoc=1`. After the Metal menu route the key list was identical, and the only changed line
  was `network.adhoc=1` to `0` (the forced off). `input.right_stick=camera` stayed as it was.

Verify output (last 20 lines, `tools/verify_task.sh 064`):
```
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
menu_check: shell metal, out out/menu_check/metal
menu_check: run_boot exit 0, 26 s, log out/menu_check/metal/run.log
tabs: ok (4)
Video: ok (9)
Audio: ok (4)
Controls: ok (31)
System: ok (12)
menu_check: PASS
verify 064: PASS
```

Open questions:
- Fill under `--shell vulkan`. The brief expects Fill to be present, but our profile has no `view_aspect_frame`.
  The framework's existing game gate (`VulkanRenderer::supports_fill()`) therefore keeps Fill out of every shell,
  as it already did before this task. The Vulkan list expects "Aspect ratio (Original / Stretch)". The shell gate
  itself was checked with the temporary experiment above.
- The camera invert rows. The audit says they are "already hidden (no camera driver)", but the code drew them
  outside the driver block, and enabled, because the default right stick is Camera. They act only on the stick's
  Camera mode (gamepad.cpp), so they are now gated on `features.right_stick_camera`. This is a gate the table did
  not name.
- The Right stick value. When Camera is not offered, the default `camera` value shows as Off: the game never reads
  the second stick's bytes, so the two behave the same. The value stays `camera` in settings.ini until the player
  changes the row.
- Touch rows on the Vulkan shell. The audit wanted them hidden on a desktop without a touch device too. The
  `supports_touch()` default stays true, since anything else would change the Vulkan shell for the framework's games
  (an escalation condition). The Vulkan shell still shows the Touch screen section, and a later change could answer
  from SDL's touch devices.
- How the dump is wired. widgets.cpp is outside "May touch", so the dump records rows through function objects in
  menu.cpp that shadow widgets.hpp's row functions (objects, so that argument-dependent lookup cannot make the calls
  ambiguous). Rows that font_menu.cpp, texture_pack_screen.cpp and save_screen.cpp draw appear as one entry each:
  `[font rows]`, `[texture pack rows]`, `[save rows]`. docs/upstream.md suggests a hook in widgets.cpp for upstream.
- The two Restore buttons behave differently. "Restore video defaults" now skips hidden rows, including the renderer
  rows under the Metal shell. "Restore control defaults" is unchanged (the table says keep): it still restores the
  hidden camera, mouse and touch settings, as it did for the rows hidden by a missing camera driver.
- Side effect of the dump. On a game with ad hoc play, drawing the Network tab for the dump starts the discovery
  listener, as opening that tab does. This happens only under `PURE_MENU_DUMP`.

## Review
Verify rerun: from the main checkout after the merge and patch 0016 applied to the vendor tree (16 patches
reproduce the pin), 2026-10-10: PASS (frame suite 18/18; menu_check Metal: tabs 4, Video 9, Audio 4, Controls 31,
System 12, Graphics "Metal on Apple M4 Pro"). The gate: `tools/menu_check.sh --shell vulkan` PASS; `--shell metal
--backend metal` 18/18 (19m 52s); `tools/hud_check.sh` 61/61.
Spot-read: the patch's gates (profile `features`, shell `supports_*`, `api_name()`) all default to today's
behaviour in shell.hpp and profile.hpp, so the framework's games are untouched; the menu's hidden rows keep their
keys; `s.adhoc` forced off at menu open for a game without the feature. The dump is confined to `PURE_MENU_DUMP`.
Merged: `git merge --no-ff` into batch/m2, b92537a.
Notes: Fill is hidden under both shells (the framework's own `supports_fill()` gate, which needs a game that
widens its view: E2), so the brief's Vulkan expectation was wrong and the worker's list is right. The two camera
invert rows were drawn before (the audit's "already hidden" was wrong) and are gated now. Follow-ups: the
bindings list's labels are the framework's ("Move forward" for the stick, four "Camera" bindings that press a
second stick this game never reads): a profile-provided label table, or hiding the camera bindings without the
feature, is the next menu change; the Vulkan shell still shows the Touch screen section on a desktop (a
`supports_touch()` answer from SDL's touch devices would hide it without changing the framework's default);
"Restore control defaults" still resets hidden rows' settings.

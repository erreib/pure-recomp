# 064: The Esc menu shows only what this game and this shell can do

Milestone: enhancements (D-014) | Branch: task/064-menu-rows-by-capability | Status: OPEN

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

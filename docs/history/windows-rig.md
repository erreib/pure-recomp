# The rig: the update checklist (2026-10-11 to 2026-10-15)

docs/windows.md's section "Updating the rig" as it stood on 2026-10-19, moved here by task 092 as written: the
checklist for bringing Erik's Windows machine up to the Mac's patches, each check's expected last line and what the
rig's runs gave. docs/windows.md keeps how to bring the rig up to date and what is open there.

## Updating the rig for 0017-internal-scale-by-backend, 0018-vulkan-effects-at-1x and 0019-game-option-rows (checklist, 2026-10-11)

The Windows build last ran with patches up to 0016 (task 061). Since then E3 added 0017-internal-scale-by-backend and
0018-vulkan-effects-at-1x, and E6 added 0019-game-option-rows with the Flashes row (D-016, task 070). None of the
three has Windows-only code; this is the rebuild and the checks. Git Bash in the checkout, one game at a time, each
command finished before the next. Expected last lines in brackets. The rig's session of 2026-10-11 did steps 1 to 3,
the suite of step 4 and step 5 (and task 071 on top); what is left is marked **open**.

1. **Pull** to 1101ce0 or later (`git pull`), on the branch the rig tracks. Done 2026-10-11.
2. **Vendor:** `tools/patches.sh check || tools/vendor_setup.sh`, then `tools/patches.sh check`
   [`ok: 19 patch(es) reproduce vendor/portablekit at 8b0c3fe`]. The corpus is untouched: no `tools/regen.sh`. Done.
3. **Build:** `tools/build.sh profile` (host and profile only, a few minutes). Done.
4. **Checks** (the Vulkan shell is the one that draws here, so every check that reads a picture names it):
   - `tools/frame_regress.sh` [`frame regression: PASS, 7/7 scenes pass, the window scenes, shell vulkan, backend
     vulkan`; `--all-scenes` for 18]. Done 2026-10-11 with all 18: 18/18 in 12m 17s on the RTX 3080, every scene
     within 0.012 of the Mac-measured Vulkan column (out/071-suite.log on the rig; docs/status.md's E3 row).
   - `tools/menu_check.sh --shell vulkan` [`menu_check: PASS`; the Video tab now ends `30 fps modes, Flashes, Text
     and sprites, Texture detail` since E4/E7/E5]. Done 2026-10-12: PASS, all five sections, after the game's first
     non-ASCII output (the dump's button glyphs) found three Windows encoding defects in the tools — the run log,
     Python's stdout and the pseudoconsole's OEM codepage — fixed in tools/ (commit "Tool runs survive the game's
     non-ASCII output on Windows").
   - `tools/flash_check.sh --shell vulkan` [`flash_check: PASS (fade 57 flips off, 0 on; the race and its HUD
     in both)`; windowed, paced from flip 5500; about 2 minutes]. The default shell is headless, which draws nothing
     on Windows, so `--shell vulkan` is required here. Done 2026-10-12: PASS with exactly that line on the second
     run; the first run's cold pipeline cache put a 0.6 s compile stall inside the race start, splitting the fade's
     two-vblank run so the detector latched onto a 2-flip fragment. Run it with the data directory's pipeline cache
     warm (a prior run suffices).
   - `tools/flash_check.sh --shell vulkan --race` [`flash_check: PASS (race: stretches N off, 0 on; mean lap
     ...)`; two swept races, about 8 minutes. The lap bound is coarse (two different races); a FAIL on the lap figure
     alone with 0 stretches is worth a second run before it is believed]. Done 2026-10-12: PASS on the second run
     (stretches 5 off, 0 on, mean lap +2.3%); the first run FAILed on the lap figure alone (+6.0%, 0 stretches on),
     the exact case above — the sweeps' laps vary run to run on this rig too.
   - **open**, by hand: a Single Race in a window, Esc, Video, Performance on, and watch the frame time through the
     start fade and a bomb or mine near the ship: with Flashes Smooth no 33 ms frames; set Original and the same
     moments show them, as the PSP does. The row's choice is saved to settings.ini (`game.smooth_flashes`).
   - **not wanted** (2026-10-12): the upscaled art as a texture pack (task 074, E7; docs/metal-backend.md "The texture
     pack"). Erik judged the upscale soft beside the sharp 3D and uneven against the elements it leaves alone, and the
     Mac app's Text and sprites row now defaults to Original (D-018, amended). Do not install the pack on the rig: the
     Texture pack row is on by default once a pack is installed, so the rig would show the look he rejected. The
     check, `tools/sprite_pack.sh --check --pack DIR`, is still worth one run there when a texture pack is next wanted,
     since it proves the Vulkan loader finds the framework's keys; the recipe stays below for that. The pack is
     made on the Mac, which has the Metal backend's scaler: `tools/sprite_pack.sh` there [`sprite_pack: built`; about
     8 minutes] writes `out/sprite_pack/pack` (textures.ini and 48 PNGs, 3.5 MB: the game's art, never committed nor
     put in the zip). Copy that folder to the rig, then: `tools/sprite_pack.sh --check --pack DIR` (DIR the copied
     folder; the script installs it in a scratch data directory of its own and captures main_menu and race_hud in the
     Vulkan window without and with it, 1 to 4 minutes) [`sprite_pack: PASS`; the pack opened, at least 10 of its
     pictures drawn, both scenes changed by at least 1% and within their limits after the reduction, the HUD found].
     To play with it, copy the folder into the rig's data directory as `textures/UCUS98612`
     (`%APPDATA%\pure-recomp\PureNative\textures\UCUS98612\textures.ini`), or install it from the game: Esc, Video,
     Import texture pack…, choose the folder; the Texture pack row (on by default) then notes `48 textures, ...`.
   - (task 076, E5's Vulkan half, patch 0020-vulkan-texture-detail; after `tools/patches.sh check`
     [`ok: 20 patch(es) ...`] and `tools/build.sh profile` with it): `tools/texture_check.sh --shell vulkan`
     [`texture_check: PASS`; race_hud, tt_hud and fp_hud at least 1% changed by the option with an energy ratio above
     1.0, all four within their limits after the reduction, the HUD found, `[render] texture detail: on` and `off` in
     the logs; 2 to 5 minutes. S is the capture's width over 480, so the rig's window size is fine as long as it is a
     multiple of 480x272]. Ran 2026-10-12, three times (28, 28 and 14 minutes here): the option's assertions each
     passed — race_hud's energy ratio 1.07 to 1.08 in all three runs, tt_hud 1.12, fp_hud 1.09 to 1.13, zone_hud
     exempt, the on/off render lines every time — but no single run went 4/4: each run one or two of the Enhanced
     lane's routes ran late (a capture at Team Selection, a HUD still fading in), always lane 1, never the twelve
     Original-lane routes. The pad presses fire at identical flips in both lanes; the divergence is the virtual load
     time, which quantizes off real IO (the lanes' first loads differ by 1 ms of game time), so a menu transition can
     cross a vblank and eat a press. A finding for texture_check's robustness follow-up (docs/status.md E5: the
     capture rerun on pipeline creation wants the same treatment for load-boundary drift), not a defect of
     0020-vulkan-texture-detail. Then, by hand: a Single Race in a window, Esc, Video, Texture detail Original, then Enhanced:
     with Enhanced the crowds, the far banners and the walls at a grazing angle resolve, the near track is the same, and
     Performance shows the same frame rate both ways (on this Mac's M4 Pro, 60 fps either way, 0.3 ms more GPU time a
     frame at internal scale 4). A device without `samplerAnisotropy` says so on a `[render]` line and samples
     isotropically.
   - (task 072, E4, added after this checklist was written) `tools/framerate_check.sh --shell vulkan` and `--race`.
     The route variant PASSed first try 2026-10-12 with the Mac's own figures: frontend 33.4/33.4 ms, race 33.4/16.7
     ms and 29.97/59.94 flips a race-clock second off/on, the HUD drawn at 60. The race variant ran twice and FAILed
     both times on one figure only, the game clock against the wall (off 0.9901 then 0.9873, on 0.9864 then 0.9921,
     bound 0.99 to 1.01; which lane fails floats between runs): the rig loses about 1% of wall time to stalls the
     pacer forgives past its 100 ms debt cap, and the compiles were warm (26 ms at worst), so the loss is
     environmental. Everything internal passes every run — flips a race-clock second 29.94 to 29.97 off and 59.66 to
     59.78 on, laps, contacts, the standing start within 5% — so E4's claim holds on this rig; the wall-clock bound
     is coarse here the way the E6 lap bound is (docs/status.md E4's follow-ups).
   - (task 077, added after this checklist was written) `tools/stutter_check.sh` [`stutter_check: PASS (...)`;
     one swept race in the Vulkan window with sound, about 6 minutes]. The stall in the 2026-10-12 findings was the
     depth write-back at the lens flare's SIGNAL, not a block-transfer readback; patch 0022-vulkan-async-readback
     stores the frame before's depth instead of draining the queue (readback 7.38 ms a frame to 0.00), and
     `PURE_SYNC_READBACK=1` restores the drain. See docs/tasks/077-vulkan-readback-stutter.md's Result for what
     still makes slow frames (the sweep's live-file reads every 10 flips and the pacer's waits after them).
     Task 078 found the probes' remaining "effects slowdowns" to be the probe's own: the guest-time spikes are the
     game thread blocked writing its `[pure] ship` lines to the sweep's ConPTY (up to 255 ms one line), and the
     100 to 160 ms present hitches were the sweep's window captures (patch 0023-vulkan-cached-window-capture: about
     4 ms now); neither happens to a player. See docs/tasks/078-vulkan-effect-slowdowns.md.
     Closed by task 083 (2026-10-13): the stutter that remained was the recompiled code itself, compiled without
     inlining. The vendor cmake's MSVC branch built the corpus `/O2 /Ob0`, so every guest memory accessor stayed a
     call and the `game` bucket of `PURE_TRACE_GUEST` took 10.08 ms a game frame on a fresh boot (stutter_check FAIL,
     164 of 248 seconds). Patch 0026-corpus-inlining passes `/Ob2`: 3.13 ms, stutter_check PASS 2 of 197, the whole
     guest frame 5.35 ms against PPSSPP's 6.5 on the same CPU. See docs/tasks/083-corpus-inlining.md.
   - **open** (patch 0029-windows-file-url, 2026-10-13): after `tools/patches.sh check` reports 29 and a rebuild, the Esc
     menu's folder buttons by hand: System's "Open the data folder", the saves tab's "Open the saves folder" and
     "Open the backups folder", Video's "Open the textures folder" and the fonts' folder: each opens Explorer at the
     folder and the log has no `[menu] cannot open` line (before the patch every one printed it, with the URL
     `file://C%3A%5C...`). `tools/menu_check.sh --shell vulkan` unchanged.
   - **open** (task 077-download-packs — the Mac line's 077, not this file's readback 077; docs/dlc.md): copy the twelve US pack folders (`UCUS98612D<PACK>`, 62 MB,
     on the Mac in `$HOME/dlc-packs`; the game's data, never in the repository or the zip) to the rig, outside the
     checkout, then `tools/dlc_check.sh --packs DIR` (DIR the copied folder) [`dlc_check: PASS`; PI.WAD opened in 12 of
     12 folders, league_select and team_select changed, the HUD in at least 4 of 6 shots of each of the Gamma, Delta and
     Classic 2 races and their TRACK SELECTION off Alpha's, no pack-related `[hle-stub]`, the boot cost printed]. On Windows its runs that take shots go
     through the Vulkan window (`purelib.port.DRAWING`, as frame_regress does), unpaced until 300 flips before the
     first shot and paced from there, so expect a few minutes; the cost runs stay headless. The two screen rows say
     little there: the Vulkan window's league_select and team_select differ from the references by 0.062 and 0.042
     without packs already (frame_regress's Vulkan column), above both bars; the opens and the races carry the
     check. To play with them:
     `tools/dlc_install.sh DIR` (into `%APPDATA%\pure-recomp\PureNative\ms0\PSP\SAVEDATA\`) [`dlc_install: 12
     installed, ...; the stick holds 12 of the twelve US packs`], then Single Race shows CLASSIC 2, DELTA and GAMMA.
   - **open** (task 089, E8; patch 0030-vblank-period): after `tools/patches.sh check` reports 30 and a rebuild,
     the rig's 100 Hz display. `tools/menu_check.sh --shell vulkan` [`menu_check: PASS`; the Video tab now ends
     `..., Texture detail, Display rate`]. A race by hand with the Display rate row at Display (the default): the log
     has the two `[pure] display rate` lines of the item below (task 091's margin: the game at 99.50 Hz, 10050 us a
     vblank), the Performance overlay reads game 99.5 in the race and 30 in the menus, and the Esc menu's Frame rate
     row opened during the race offers the game's own rate and "Match display 100 Hz" only (say what it shows). `PURE_DISPLAY_RATE=1 tools/stutter_check.sh` [`stutter_check: PASS`; its budget doubled for the faster
     race] for the 10 ms budget. With the row at Original the race runs at 60 as before.
     Measured 2026-10-14 (task 091-display-rate-storms, before the margin below): on this rig (RTX 3080, its CPU)
     the 100 Hz race does not fit 10 ms, storms or not. A race frame costs about 11.7 ms of host work whatever the
     rate (game 3.3, sceDisplay's host work 2.1, render 4.3, fence 1.6 ms), so the race holds 85 fps and runs at
     85% speed, with the effect storms dipping to 76 to 80%. Original (60, with 6 ms to spare a frame) is the
     smooth setting on this machine. A clean Display rate at 100 Hz needs about 2.5 ms a frame more headroom
     (25%: the mean overrun plus the storms' 0.7 ms), and more at 120 Hz. The margin's 10050 us vblank widens the
     budget by only 0.05 ms, so these figures stand with it.
   - **open** (task 091-display-rate-margin, E8's margin; no patch, a rebuild): the race now runs 0.5% under the display, so at the
     rig's 100 Hz the lines read `[pure] display rate: 100 Hz display, the game at 99.50 Hz in a race (margin
     0.005), the PSP's 59.94 Hz outside one` at start and `[pure] display rate: 100 Hz display, the game at
     99.50 Hz (margin 0.005, 10050 us a vblank)` at the race load. With the game window in front and nothing
     over it, `tools/display_rate_check.sh --audio --shell vulkan` [`display_rate_check: PASS (audio, vulkan,
     margin 0.005, 10050 us a vblank: 1 resync, 0 seconds under 95% ...)`; about 2.5 minutes; the probe
     refuses with exit 2 when the window is covered]. Say the seconds under 99% it reports. For the comparison,
     `--audio --shell vulkan --margin 0` (on this Mac's 120 Hz display it FAILed with 9 resyncs).
5. **Package:** `tools/bundle_windows.sh --zip` (rebuilds the Release binary when stale: 15 to 25 minutes cold), then
   `tools/bundle_windows.sh --check out/repack-win-070` [`bundle check: PASS`]. Done 2026-10-11: the zip
   pure-recomp-0.1.0-6393b67-windows-x64.zip, seven checks PASS (out/repack-071.log on the rig); then task 071 added
   the icon and version resource and the eighth check, all eight PASS (out/071-verify-main.log). A pack from the
   current tree carries the icon. Still **open** from task 071: open the staged folder in Explorer once and look at the
   exe's icon and Properties > Details, and whether the running window and its taskbar button show the icon.
   For a release, pack at the tag `v<version>` with a clean tree: the zip is then
   `pure-recomp-<version>-windows-x64.zip` with no commit in its name, and a `v` tag at HEAD that disagrees with
   CMakeLists.txt's version stops the pack (task 087; docs/release.md, "Publishing").
6. **Record** the last lines of each open check in this section (or send them to the Mac session); the
   docs/status.md E3 follow-up row is cleared, the E6 bullet names the two open checks. Done 2026-10-12: every
   scripted check above is recorded in place; what stays **open** is by hand and Erik's — the Flashes race with the
   Performance overlay, the Texture detail race by eye, and task 071's Explorer and taskbar look at the icon.

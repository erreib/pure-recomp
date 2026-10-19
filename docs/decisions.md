# Decisions

| ID | Date | Title | Status |
|---|---|---|---|
| D-001 | 2026-10-05 | Vendor base: TeamGDB/PortableKit pinned at 8b0c3fe | accepted |
| D-002 | 2026-10-05 | Renderer path: Vulkan/MoltenVK bootstrap, then native Metal behind a seam | accepted |
| D-003 | 2026-10-06 | GE backend seam: shell vs GeBackend; Vulkan adapted, Metal implemented against it | accepted |
| D-004 | pending | Determinism: virtual clock, fixed RTC, frame-indexed input | open (M3) |
| D-005 | 2026-10-12 | Savedata directory layout, DLC-ready: the PSP's memory-stick tree as it is, the download packs sibling folders the game loads unchanged | accepted (Erik; built in M5, proven by task 077) |
| D-006 | 2026-10-05 | Licence of our code: GPL-2.0-or-later | accepted |
| D-007 | 2026-10-06 | Shell seam: `host::Shell` behind the HLE; Vulkan shell adapted, headless shell added, Metal shell implemented against it | accepted |
| D-008 | 2026-10-06 | Metal shell and Metal backend are the default on macOS; Vulkan stays the portable path, selectable | accepted |
| D-009 | 2026-10-06 | Priority: as close to 1:1 with the original as possible before any enhancement; the host pause menu stays the framework's | accepted (Erik) |
| D-010 | 2026-10-07 | The SAS reverb's two constants are fitted to PPSSPP's output (the formula at 44.1 kHz, the sends at half), not taken from the documentation | accepted |
| D-011 | 2026-10-07 | Load times stay the port's own (no UMD read timing): fidelity difference 6 closed as accepted | accepted (Erik) |
| D-012 | 2026-10-07 | The expanded version gets its own save format (the game's profile blob in our container, with an extensions area); the PSP format stays as the import/export bridge; designed when the DLC loader and the first sequel feature are concrete | accepted (Erik), scheduled |
| D-013 | 2026-10-07 | VFPU dot products round as the real PSP does (pspautotests' truncating rule); PPSSPP's fused chain is a test-only mode for the scorecard's comparisons | accepted (Fable; Erik informed) |
| D-014 | 2026-10-10 | The Esc menu shows only what this game and this shell can do; enhancements are open (D-009's condition met) | accepted (Erik) |
| D-015 | 2026-10-10 | E3 opens: the Metal shell draws at the display's pixels and the Metal backend draws at an internal scale, effects buffers at 1x | accepted (Erik) |
| D-016 | 2026-10-11 | E6: the race keeps its frame rate through the full-screen flashes (the game's two-vblank lock cleared in the 60-fps modes), a game option row in the Esc menu, on by default; the checks run with it off | accepted (Erik) |
| D-017 | 2026-10-11 | E4: Time Trial, Free Play and Zone free-running at the display's rate (the frame object's lock byte set while the race backend lives), a "30 fps modes" row in the Esc menu, 60 fps by default; the checks run with it off; the frontend stays at 30 | accepted (Erik) |
| D-018 | 2026-10-11 | E7: the menus' and HUD's bitmap art upscaled 4x at decode in the Metal backend (through-mode draws' palette textures, an edge-preserving resample), a "Text and sprites" row in the Esc menu, on by default then, off since 2026-10-12 (Erik's judgement of the picture); the checks run with it off; a texture pack from the same scaler for the Vulkan renderer and as the base for an AI pass, second | accepted (Erik) |
| D-019 | 2026-10-12 | E5: texture detail at the internal scale: the mip level picked for the pixels drawn rather than the PSP's, anisotropic sampling on the mipmapped draws, a "Texture detail" row in the Esc menu, on by default; the checks run with it off; Metal first, the Vulkan renderer second | accepted (Erik) |
| D-020 | 2026-10-13 | E2: the 3D view at the window's shape (the framework's Fill aspect) through a profile hook on the game's perspective builder and its horizontal half-FOV, since the game bakes 480/272 into code; the 2D interface at square pixels about the centre; Vulkan first, the Metal shell's Fill after | accepted |
| D-021 | 2026-10-13 | VR, Windows only: an OpenXR shell on the Vulkan renderer, each game frame replayed once per eye through the frame interpolation's replay path with the headset's view and projection, the 2D interface on a panel in front; a Quest over Link on the rig; a stereo spike first (task 088), the milestone after it only if the spike holds 72 Hz | accepted |
| D-022 | 2026-10-14 | E8: the display rate. The kernel's vblank period becomes settable and a "Display rate" row (Original 59.94 Hz, or the display's refresh) runs the game's own vblank at the display's rate, so the free-running modes draw at 120 fps on a 120 Hz display and the two-vblank screens at 60; the game's step stays measured time; per-frame counters audited by a check | accepted |

## D-001  2026-10-05  Vendor base
Context: the research named Yakumo (MIT, complete MHP3rd port) as the base and asked to check TeamGDB/PortableKit
first. Spike S3 (`docs/vendor-map.md`) found PortableKit is the framework and the whole host layer moved out of
Yakumo into a generic `portablekit` namespace, built as a CMake subproject with `portablekit_add_game()` and a
`portablekit::game()` profile that lives in the game's own repo. Spike S4 ran both recompilers on BOOT.BIN.
Decision: vendor PortableKit at commit 8b0c3fe (2026-09-27) under `vendor/portablekit`, our profile in `src/`
out of tree, our HLE additions as an HLE extension module (`PORTABLEKIT_HLE_EXTENSION_DIRS`) so they need no
vendor patch. Yakumo stays a read-only reference under `~/dev/scratch/Yakumo` for renderer fixes newer than the
split.
Why: out-of-tree profile (Yakumo hard-codes `profiles/<name>`); PortableKit lowers every instruction of BOOT.BIN
(Yakumo leaves 76 sites unlowered); HLE name coverage 246/278 vs 165/278; the interpreter runs the game with no
corpus (Yakumo refuses), so bring-up starts before the 15 to 20 minute corpus compile; Bezier/spline patches are
tessellated; macOS CI; 20/20 tests pass here.
Consequences: PortableKit warns its interfaces change without notice, so updates happen only by decision; only
Yakumo has shipped a full-speed recompiled game, so renderer and kernel behaviour get conformance tests before we
rely on them (R10); the VulkanRenderer still owns SDL and ImGui in both repos, so the D-002 split is our patch.
Alternatives: Yakumo with a symlinked profile or an out-of-tree patch; PSPRecomp (Windows only).
Status: accepted.

## D-002  2026-10-05  Renderer path
Context: Yakumo ships a working Vulkan GE renderer that runs on macOS through MoltenVK. Erik wants a native
Metal renderer and a portable design.
Decision: Milestone 2 boots the game on Yakumo's Vulkan renderer so the CPU/kernel layer is debugged with a
known-good renderer. Fable then defines a backend-neutral seam fed by Yakumo's DrawCall/BlockTransfer stream;
the Metal backend is written against it (M6) with Vulkan as a second oracle. Vulkan stays as the portable
backend for other platforms.
Consequences: a MoltenVK/glslang dependency and a patch that splits VulkanRenderer from SDL/ImGui; two
backends to keep at parity, checked by ge_replay and fuzzing.
Alternatives: Metal from day one (renderer and CPU bugs arrive together, no A/B); Vulkan only (no native Metal).
Status: accepted (Erik, 2026-10-05).

## D-003  2026-10-06  GE backend seam
Context: the vendored VulkanRenderer fuses the window shell and the GE backend; the Metal backend (M6) must
replace only the latter, and the renderer patches of tasks 009 to 019 (now 0003-vulkan-renderer-fixes) define
what this game needs from a backend.
Decision: a `gpu::GeBackend` interface (docs/ge-backend.md) between the shell and the backend. The Vulkan
renderer is adapted through a thin wrapper, not split or rewritten. The Metal backend is written against the
interface, with a Metal presenter in the shell. `null` and `record` backends validate the split; ge_replay compares
backends on recordings and fuzz. Backends are chosen by `PURE_GE_BACKEND`.
Consequences: one vendor patch for the seam (upstream candidate), no change to Vulkan output (the regression
suite must be unchanged); the Metal work lives in src/gpu/ in this repo; the shell's Metal presenter is a second
patch. The render-target model (aliasing, stencil-as-alpha copy rule, depth write-back) is part of the contract.
Alternatives: split VulkanRenderer into shell and backend (cleaner, but a large patch against a moving upstream);
Metal only via MoltenVK (no native backend).
Status: accepted.

## D-005  2026-10-12  Savedata directory layout, DLC-ready
Context: planned in M5 as "the save layout must not close the DLC door": on a PSP a download pack is a save-data
folder `UCUS98612D<PACK>` beside the profiles, holding PI.WAD, which the game lists, opens, verifies and mounts
itself (docs/dlc.md). The port's saves live in a memory-stick tree, `<data dir>/ms0/PSP/SAVEDATA/`, through the
framework's save-data HLE (task 014) and the PSP's own file format since task 045 (the import and export bridge).
Decision (built, then proven): the layout stays the PSP's; nothing in the port learns what a pack is. Task 077
(2026-10-12) put the twelve US packs on a scratch stick as they came from consoles and the game loaded every one:
the pack leagues and ships appeared, three pack tracks raced with their HUD, half a second more at boot. The profile
lists the twelve pack folders so the Esc menu's save screen names them and its Import accepts them by name;
`tools/dlc_install.sh` and `tools/dlc_check.sh` are the tools; the packs are the game's data and never enter the
repository or a release archive.
Consequences: a pack installs by copying its folder, by the tool, or through the menu's Import (seven of the twelve
refused there until the save transfer skips a file-list entry that is not a name: task 078). D-012's container,
when it comes, presents the packs through the same save-data calls rather than folders, as decided there. The packs
of the other regions are signed and compressed for their own builds; a converter, a hash hook and zlib in the WAD
reader would be their own milestone (docs/dlc.md).
Status: accepted (Erik).

## D-006  2026-10-05  Licence
Context: the framework is MIT, FFmpeg is LGPL and linked dynamically, PPSSPP is GPL-2.0-or-later and may one
day be the source of a ported piece. Erik may publish the repo and is fine with GPL.
Decision: our code is GPL-2.0-or-later. No PPSSPP code is copied until a decision records it; game assets,
generated code and DLC keys never enter git.
Consequences: compatible with every dependency; porting from PPSSPP later needs only a decision entry.
Status: accepted.

## D-007  2026-10-06  Shell seam
Context: D-003 put the GE behind `GeBackend` but left the window shell fused in `VulkanRenderer`. Task 021 showed the
two consequences: a non-Vulkan backend's picture has nothing to show it, and a run without a window has no pad, so
every route runs windowed and the headless null backend proves nothing about the frontend.
Decision: a second interface, `host::Shell` (docs/ge-backend.md section 8), with three implementations: `VulkanShell`
adapting the existing renderer (no behaviour change: the regression suite is the gate), `HeadlessShell` reading the
input script at pad level with no window, and `MetalShell` in our sources (task 027). The SDL pad sampling is shared
code. `<prefix>_SHELL` selects; `<prefix>_NO_RENDER` keeps its meaning.
Consequences: the shell seam (task 026; since task 052 part of patch 0004-ge-backend-and-shell-seams with the GE
seam of task 021) is the second mechanical vendor change of the series and an upstream candidate like the first.
Headless routes become possible but stay slow until the kernel's host-wait sleep is changed (Fable, after task
026: patch 0005-kernel-host-waits-and-pacing). The Metal presenter can show a Metal texture directly rather than through a read-back.
Alternatives: showing Metal pictures through MoltenVK's Metal-object import in the Vulkan shell (keeps one shell, but
the port would still need Vulkan on macOS, against D-002's "native Metal"); a profile-level pad injection into
sceCtrl for headless runs only (smaller, but a second input path to keep in step with the script format).
Status: accepted.

## D-008  2026-10-06  Metal by default
Context: D-002 bootstrapped on Vulkan through MoltenVK and planned a native Metal backend behind a seam. Tasks 021 to
027 delivered the seam, the Metal backend (five regression scenes within 0.0002 to 0.038 of PPSSPP, closer than the
Vulkan path's 0.030 to 0.067, which draws at 2x and loses edges in the reduction), the shell seam and a Metal shell.
`PURE_SHELL=metal PURE_GE_BACKEND=metal` runs the game with no Vulkan or MoltenVK in the process at 60 fps.
Decision: on macOS the Metal shell and backend are the default (set by our entry point when the variables are unset;
task 028). The Vulkan shell and backend stay built and selectable (`PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan`) as the
portable path and as the A/B reference through ge_replay. The regression suite keeps a measured column per backend
and runs the Metal path by default; renderer changes are gated on both paths.
Consequences: MoltenVK is no longer needed to play, only to build and run the Vulkan path; the app bundle (M7) ships
Metal only unless the Vulkan path is asked for. Vulkan-specific interface rows (resolution, texture packs) are absent
under the Metal shell until the backend grows them (enhancements E3, E5).
Alternatives: keep Vulkan the default until the enhancements land (rejected: the Metal path is the more faithful one
today and is the one Erik asked for); drop Vulkan (rejected: it is the portable path and the differential reference).
Status: accepted.

## D-009  2026-10-06  Fidelity before enhancements
Context: after the first playable app Erik asked about redesigning the framework's Escape menu and unifying it with
the game's own pause menu. Both are possible (an overlay hook patch, then our own menu; the game's actions driven
through its pause screen) and were queued.
Decision (Erik): drop the pause-menu work. The next milestone is fidelity: the game as close to 1:1 with the
original as possible, measured against PPSSPP and the original's behaviour, across every track, mode, class and
screen. Enhancements (controls, widescreen, internal resolution, 60 fps in the 30-fps modes, filtering) are
discussed after that. The frame-time work (033) stays, since steady 60 fps in the race is part of faithful play, and
the test speed-up (034) stays, since the fidelity sweep depends on it.
Consequences: the host overlay remains the framework's menu with its cosmetic leftovers until further notice. The
fidelity work is a milestone of its own (M8 in docs/status.md): the breadth sweep's halts and unimplemented GE
features, PPSSPP comparisons beyond the five scenes, the 30-fps modes and higher classes on every track, audio and
save behaviour, the PSP system dialogs the framework replaces (the save list), and whatever the playtests find.
Status: accepted.

## D-010  2026-10-07  The SAS reverb's constants come from PPSSPP's output
Context: task 043 modelled the SAS reverb from the PlayStation SPU documentation (psx-spx's formula and preset
tables), which is the only published description of the unit the PSP's SAS inherits. Run as documented (the SPU's
22050 Hz between its resampling filters, the sends at unity) the pause tail is 3 to 14 times PPSSPP's and falls too
slowly; no gain fixes the slope. Two changes bring every 100 ms step of the first second within 1.05 to 1.27 of
PPSSPP's and the steady effects level of a race and of the Free Play idle within 1 percent: the formula ticks once per
sample at 44.1 kHz (the presets' delays are then half as long in time, which is the slope PPSSPP shows), and the
sends enter at half level (one constant, fitted independently by the tail and by the steady level). Neither comes
from documentation the worker could read, and the PSP SDK's sceSasCore reference, which might say where the half
belongs, is not at hand.
Decision: keep both. PPSSPP is this project's oracle with tolerance (the plan's fidelity rule), its SAS output is the
only reference we have for the reverb, and the fitted model matches it on every measure taken while the documented
one matches none. The documented path stays behind `PURE_SAS_REVERB_SPU_RATE=1` so the choice can be revisited, and
`PURE_NO_REVERB=1` turns the unit off.
Consequences: the reverb is faithful to PPSSPP, not proven faithful to a PSP; a capture from real hardware would settle
the two constants and is the one check that does not route through the emulator. The inferred parts no game here
exercises (RevParam's mapping for ECHO and DELAY, PIPE as "Half Echo", type -1 as OFF) are named in the patch's row.
Status: accepted.

## D-011  2026-10-07  Load times stay the port's own
Context: fidelity difference 6 (task 035): the loading screens before a race last about 0.3 s of game time in the
port against about 1.5 s in PPSSPP, because the port reads the disc image at the host's speed while PPSSPP emulates
a UMD drive's read timing. Being faithful here would mean emulating the drive's seek and transfer times, which PPSSPP
itself only approximates.
Decision (Erik): leave the faster loads. The difference stays in docs/fidelity.md as accepted, not as a task; the
scorecard reports the load length with the grade "accepted (D-011)" rather than "differs".
Consequences: nothing reads the disc with a delay; a later ad hoc multiplayer, if any, would need its own view of
load timing between peers. If a game behaviour ever turns out to depend on the load's length (a timer that runs
during it), that is a new finding, not this decision.
Status: accepted.

## D-012  2026-10-07  An own save format for the expanded version
Context: Erik plans an expanded version after fidelity: the DLC packs, and possibly features from the sequel
(Wipeout Pulse). He asked whether the save system could be rebuilt away from the PSP's proprietary format. The game
itself never encrypts: it hands a plain profile structure (41 KB) to the save-data utility, and everything
proprietary (the cipher, the hashes, PARAM.SFO, the folder layout) is the utility's work, which in the port is the
framework's HLE layer, not recompiled code. On a PSP each DLC pack is a save-data folder holding a WAD the game
decrypts itself; sequel features would be new native code needing state the original profile has no field for.
Decision (Erik): the expanded version gets its own save format: the game's profile structure as the payload (the
recompiled code reads that layout), inside our own versioned container with checksums and an extensions area for
state our native code keeps beside the game's. DLC packs become entries the loader presents through the same
save-data calls rather than memory-stick folders. The PSP format stays as the import and export bridge (task 045's
writer and the framework's menu), so a PSP or PPSSPP profile can be brought in and a port profile taken out. The
plain saves the port writes today migrate trivially, being the same blob.
Timing: designed and built as the opening task of the expanded version, once the DLC loader and the first sequel
feature are concrete, so the container holds what they need rather than guesses; not before the scorecard and not
under D-009's fidelity rule.
Consequences: task 045 proceeds as briefed (the bridge is wanted either way). The savedata HLE stays the one seam
for saves; nothing else should learn the memory-stick layout. When the format is designed, docs/savedata.md gets the
container's specification and a migration note, and the framework's import/export is kept working against it.
Status: accepted, scheduled for the expanded version.

## D-013  2026-10-07  The dot product rounds as the PSP does; PPSSPP's rounding is a test mode
Context: task 047 measured 1.17 million dot products at the game's own VFPU sites. Three rules exist: the real PSP's
(pspautotests' `vector.expected`, a hardware run: products aligned to the largest exponent with two extra bits,
truncated toward zero, summed exactly, cut to 24 bits toward zero; the only rule that gives all 150 results), PPSSPP's
(its JIT fuses vdot and vtfm in lane order and leaves vmmul unfused, its interpreter fuses vmmul's last element: the
emulator's own compiler on this machine, reproducing 40 percent of the PSP's results), and the port's (clang's fusion
of the framework's expression, starting at another lane). PPSSPP is the project's oracle with tolerance, but here its
output is an artefact of its build, not a model of the console, and D-009 asks for the original.
Decision: the port's generated code rounds dot products (vdot, vhdp, the rows of vtfm and vhtfm, the elements of
vmmul, the dot lanes of vcrsp and vqmul) by the PSP's rule, with contraction off for the whole corpus so every
translated instruction rounds on its own. PPSSPP's JIT rule is available as a test-only mode (`PURE_VFPU_DOT=ppsspp`)
for the scorecard's trajectory rows and `tools/ai_seed_check.sh`, which compare against PPSSPP's references and would
otherwise never be faithful by construction; a player's game never uses it.
Consequences: patch 0009-vfpu-rounding (task 047; the codegen header and the Vtfm/Vmmul emitters), a regeneration
and a full corpus rebuild; `tools/vfpu_probe.py port` and `tools/vfpu_model.py --check` verify the new code against
the samples under both rules; docs/scorecard.md's Trajectories section says the AI rows run under the PPSSPP mode. The PSP rule's unmeasured
corners (subnormals, cancelling sums' sign, prefix constants past the encoded length) follow IEEE until a hardware
sample says otherwise. The transcendentals stay as they are: the port's vrcp, vrsq and vsqrt match PPSSPP's JIT on
every sample; the PSP's own vrcp is known to be inaccurate in its lowest bits and no hardware sample of it exists here.
Status: accepted (Fable); Erik informed, may overrule.

## D-014  2026-10-10  The Esc menu shows only what this game and this shell can do
Context: D-009 kept the framework's Esc menu untouched until fidelity was done. Fidelity is done (M8, the Windows
bring-up, difference 15 fixed by task 063), and Erik's playtests on the packed app brought the menu up: it still
offers the framework's Monster Hunter rows (a right-stick camera, analog camera speeds, aim speed, mouse camera
sensitivity and inversion, "Play together" halls, "Pause during multiplayer"), rows the Metal shell does not act
on (Frame rate, Lower when behind, Performance, the Fill aspect) and a System line that reads "Vulkan on" an
Apple GPU.
Decision (Erik): audit the menu and remove what is not valid for this port. Done as capability gates, not deletions:
the game profile says which game features exist (ad hoc play, a right-stick camera, a mouse camera, a trigger
profile), the shell says which host features it implements (frame interpolation, the performance overlay, the Fill
aspect, touch controls), and the menu draws a row only when its feature exists. The framework's own games keep
every row; upstream gets the gates (docs/upstream.md). With this the enhancements E1 to E5 are open; a menu design
of our own (D-009's unification with the game's pause screen) stays unscheduled.
Consequences: task 064 (docs/tasks/064-menu-rows-by-capability.md: a vendor patch with the gates, the profile's
flags, the Metal shell's answers, a menu-rows dump and a menu check). The Network tab is hidden until ad hoc play
is a feature of this port.
Status: accepted (Erik).

## D-015  2026-10-10  E3: native resolution on the Mac
Context: Erik's first enhancement: the picture at the display's native resolution. Two gaps. The Metal shell makes its
window without SDL's high-pixel-density flag, so on this Mac (a 3024x1964 Retina panel, 2x backing) the layer's
drawable is 960x544 for a 960x544-point window and macOS upscales it: every pixel the game draws is shown blurred,
whatever the scaling filter says. And the Metal backend draws at internal scale 1 only (D-002: the native picture
first), while the Vulkan renderer draws at 2x by default or follows the window (Auto).
Decision (Erik): do both, in this order, as the enhancement E3.
1. The shell's drawable is the window's size in pixels (the high-pixel-density flag; `SDL_GetWindowSizeInPixels`),
   the present's viewport in those pixels, the window-size setting still in points (multiples of 480x272 points).
2. The Metal backend draws at an internal scale S of 1 to 6 (`video.internal_scale`, `PURE_INTERNAL_SCALE`; Auto
   follows the drawable: the smallest S whose 272*S covers the drawable's height, at most 6), on these rules:
   - a target at least 480 pixels wide (the display buffers, 512 stride) is 480S x 272S; a narrower one (the 128-wide
     billboard targets, the 256-wide bloom buffers) stays 480x272 as today, so the bloom's 11-tap blur keeps the
     PSP's radius on screen (PPSSPP's lesson for this game: its "lower resolution for effects" flag) and the adverts
     stay the PSP's;
   - the GE's coordinates (the viewport, the scissor, through-mode positions, the texture placement of a target
     sampled as a texture) scale by S; a draw's state is otherwise unchanged, dithering included (per drawn pixel);
   - what goes back to guest memory (the frame write-back, read-backs, the lens flare's depth read) is the centre
     pixel of each S x S block, so the game sees a 480x272 picture as before;
   - headless runs and every check on the Metal backend stay at S = 1 unless they say otherwise (`tools/run_boot.py`
     sets `PURE_INTERNAL_SCALE=1` by default for it; the bundle check's data directory says so; the Vulkan
     backend's checks keep its 2x, on which its columns were measured): at S = 1 the output is pixel-identical to
     today's (the refactor check proves it);
   - a scaled capture is reduced to 480x272 for a comparison by the centre pixel of each S x S block, the same rule
     as guest memory's (task 066: nearest neighbour's top-left pick sits 3/8 of a pixel off centre at S = 4 and
     moves every filtered edge, scoring up to 11% where the centre pick scores 3%);
   - the menu's Resolution row shows for a backend that reports the capability (a vendor patch in the pattern of
     0016-menu-rows-by-capability).
Consequences: tasks 065 (the shell) and 066 (the backend's scale), then 067 (the Resolution row, the perf table, the
Vulkan renderer's bloom buffers at 1x as a patch for Windows). The exit from the plan: at S = 4 a scene downsampled
to 480x272 differs from the S = 1 capture by at most 5% of pixels at tol 24, the bloom's brightness within 10%; a
race holds 60 fps at S = 4 on this Mac.
Status: accepted (Erik).

## D-016  2026-10-11  E6: a steady frame rate through the full-screen flashes
Context: Erik's playtest: the frame rate dips at the start of a race and in effects-heavy moments, a bomb going off
for one. The fidelity audit traced both to the game's own rule (docs/fidelity.md "The two-vblank stretches",
docs/timing.md step 5): the full-screen flash object FxScreen sets the frame object's countdown (`+0x117c`) to 2 on
every frame it runs, and the end-of-frame routine then waits two vblanks a frame. The race-start fade, a weapon
going off near the camera and the ship being put back on the track are flashes, so the race runs at 30 fps for 0.4
to 1.9 s each time, on the PSP and in PPSSPP too. The game's physics, camera and timers integrate a measured dt
(FUN_08804390, from the system clock, capped at 0.067 s), so the race's speed does not depend on the wait; the wait
was there for the PSP's fill rate.
Decision (Erik): the port offers the race without that lock, as the enhancement E6, before the other enhancements:
1. In the free-running modes (the frame object's `+0x116c` is 1: Single Race and Tournament) the countdown is cleared
   each frame before the end-of-frame routine reads it, so a flash frame waits for the GE and the vblank like any
   other. The 30-fps modes (`+0x116c` 0: Time Trial, Free Play, Zone) are untouched: their 60 fps is E4's question
   (per-frame logic), not this one.
2. The hook is the port's, in the profile, at an HLE call the end-of-frame routine makes before its pacing step
   (`sceGeDrawSync`, step 1), reading and writing the two fields in guest memory: no generated code is changed, no
   game bytes are kept.
3. The player's switch is a row in the Esc menu, through a generic framework patch (the pattern of
   0016-menu-rows-by-capability and 0017-internal-scale-by-backend): a game lists its options in `GameProfile`
   (key, row label, choices, help, default, tab), the framework stores each as `game.<key>` in settings.ini with a
   `<prefix>_<KEY>` variable for the tools, and the menu draws them in a "Game" section of the tab the option names.
   E4 and E5 will use the same rows. For this game the row is "Flashes", choices "Original" (the PSP's half rate)
   and "Smooth", default Smooth (`game.smooth_flashes=1`, `PURE_SMOOTH_FLASHES`).
4. The checks measure the PSP's behaviour: every tool run through `tools/purelib/port.py` sets
   `PURE_SMOOTH_FLASHES=0` unless the caller names it (as the Metal runs are pinned to internal scale 1), so the
   scene flips of the suites, the HUD check and the sweep stay where they were measured. `tools/flash_check.sh`
   is the one check that runs with the option on.
Consequences: task 070. The exit: on the Vineta K start route the race-start fade's 57 two-vblank flips become at
most 2 with the option on and stay at 57 with it off; a swept Single Race with the option on has no two-vblank
stretch, and its lap times are within 5% of the same race with it off (the game's speed unchanged); the menu dumps
of both shells show the row; the headless suite, the HUD check and a 2200-flip frontend run are unchanged with the
option off.
Status: accepted (Erik).

## D-017  2026-10-11  E4: the 30-fps modes free-running
Context: Erik's next pick after E6: 60 fps in the modes the game locks to two vblanks (Time Trial, Free Play, Zone).
The plan held E4 back for an audit of per-frame logic, since the CWCheat that NOPs the end-of-frame loop's branch
was reported to run those modes at double speed. The audit (the planning session, 2026-10-11, out/e4/ on the Mac):
- The lock is one byte, the frame object's `+0x116c` (docs/timing.md step 5). The race backend's constructor
  (`BackendRoot_cpp__0880c068`) sets it to 1 and stores the backend object at `DAT_08a8c5f4`; the Time Trial, Free
  Play and Zone race managers (`LinkObj_etc__08818d80`, `LinkObj_etc__08819a0c`, `LinkObj_etc__0881bc8c`) set it
  back to 0; the destructor (`BackendRoot_cpp__0880c328`) zeroes both. Its only readers in the corpus are the
  end-of-frame routine `FUN_0886511c` and MemStickUtil's save-dialog driver, which saves and restores it around a
  dialog. Nothing else branches on it.
- The frame timer `FUN_08804390` measures dt from the system clock (capped at 0.067 s). Its two fixed-step bytes
  (`DAT_08a8e964` forces 1/30, `DAT_08a8e965` 1/60) are 0 in the executable and nothing in the corpus writes them;
  their two other readers (`FUN_0881e6bc`, `FUN_0892195c`) only toggle a display flag. The timer also counts frames
  into `DAT_08a8c3d8`, which only it reads (it hands the count to every object's update beside dt).
- Measured with a temporary switch that stores 1 to the byte while `DAT_08a8c5f4` is set, in paced sweep cells
  against the same cells at the game's pacing: Time Trial on Vineta K ran at 59.95 flips a race-clock second
  (29.98 before); the game clock advanced 1.0001 s a virtual second (0.9993 before); the standing start reached the
  same speeds at the same race clock to within 3% up to the speed pad (12 to 647 km/h over 3.0 s, against 14 to
  647); the ghost ship samples by accumulated dt at 0.05 s (`FUN_0891e8a0`, 89 s at most). Zone 1 ran at 58.8 flips
  a second with the ship stuck against a wall: destroyed at 59.5 s of race clock with 7 zones cleared, against
  59.2 s and 6 (the zone timer and the shield drain follow time). Free Play on Vineta K: 60.6 flips a second
  against 30.5, the game clock 1.0002 against 0.9993, the standing start the same to 2.0 s (12 to 166 km/h against
  14 to 164). The follower's laps were faster at 60 (65.0, 55.1,
  58.2 s against 76.0, 69.0, 69.9) with fewer wall contacts (47 against 66), because it reads its steering file every
  10 flips, twice as often at 60: the driver's doing, not the game's speed, which the start and the clocks show
  unchanged. No per-frame logic was found in the race; the cheat's double speed is not reproduced by the port.
Decision (Erik): the port offers those modes free-running, as the enhancement E4, in E6's shape:
1. While the race backend lives (`DAT_08a8c5f4` points into user RAM) and the frame object's `+0x116c` is 0, the hook
   stores 1 to it each frame before the end-of-frame routine reads it, so Time Trial, Free Play and Zone take the
   free path (the GE sync and `sceKernelDelayThreadCB(150)`) and run at the display's rate. The frontend, whose byte
   is 0 outside the backend, keeps its 30 fps: its menus were not audited and the PSP's menus are 30 fps.
2. The hook is the port's, in `src/profile/enhancements.cpp`, in the same `sceGeDrawSync` wrap as E6 and before it,
   so a Smooth flash in a free-running Time Trial takes E6's path too; with Flashes Original a flash frame still
   waits two vblanks there, as it does in Single Race. No generated code is changed.
3. The player's switch is a game option row (patch 0019-game-option-rows): "30 fps modes" (named "Frame rate" in
   the brief; renamed at the merge, since the Vulkan shell's Video tab has the renderer's row of that name), choices "Original" (the
   PSP's 30 fps in those modes) and "60 fps", default 60 fps (`game.sixty_fps=1`, `PURE_SIXTY_FPS`), on the Video
   tab before Flashes.
4. The checks measure the PSP's behaviour: every tool run has `PURE_SIXTY_FPS=0` through `tools/purelib/port.py`
   beside `PURE_SMOOTH_FLASHES=0`, so the Time Trial, Free Play and Zone scenes of the suites stay where they were
   measured. The check task 072 adds (`framerate_check.sh`, beside `tools/flash_check.sh`) is the one that runs with the option on.
Consequences: task 072. The exit: on the Time Trial route the race's flips are two vblanks apart with the option off
and one with it on, while the frontend's stay two in both; a swept Time Trial with the option on runs at 58 to 61
flips a race-clock second, its game clock within 1% of real time, its standing start within 5% of the run with it
off; the menu dumps of both shells show the row; the headless suite and a frontend run are unchanged with the option
off. A Time Trial at 60 integrates its physics in 1/60 steps where the PSP took 1/30, so a lap record may differ in
its last digits from the same drive at 30: the price of the option, as in Single Race already. Not in this task: the
frontend at 60 (a follow-up if the menus prove dt-driven), the Vulkan window's actual rate on Windows (the rig's
check), and a window that cannot draw 60 (the game then runs at what it draws, dt measured, as Single Race does).
Alternatives: NOP the loop's branch as the CWCheat does (no instruction to NOP in a static recomp, and it would also
touch the frontend); set the byte from the race managers' constructors (generated code, three sites, no option).
Status: accepted (Erik).

## D-018  2026-10-11  E7: the frontend's resolution, the bitmap art upscaled
Context: Erik's next pick: the frontend (the game's menus) looks low-resolution, more so than the races, and he
wants that before the frontend's 60 fps. E3 did not touch it, and the main menu's draws say why (ref/main_menu.ppdmp
through `tools/ppsspp/ppdmp.py draws`; the planning session, out/fe_tex/ on the Mac): 32 draws, the text drawn glyph
by glyph from two bitmap font atlases in RAM (CLUT4, 256x128 and 256x256, glyphs about 15 texels tall, antialiased
in 16 alpha levels), the decoration from static art atlases the game keeps in VRAM (CLUT8 256x128: logos, the
katakana "wipeout" strip, the menu's bars), the rest untextured panels; every sprite drawn at one texel a screen
pixel of the 480x272 picture, in through mode. A higher internal scale (E3) magnifies those texels more sharply; the
detail is not there. The race HUD is drawn the same way. The 3D scenes gained from E3 and are not the problem.
Two ways to add the detail: replacement textures (PortableKit loads PPSSPP-format packs, `textures.ini` and PNGs
keyed by a content hash, on its Vulkan renderer; the Metal backend has no pack path yet but keys every texture by
its contents already), or an upscaler at decode. A pack holds the game's art and cannot be committed (CLAUDE.md), so
it would be built locally from the disc; an upscaler ships in the app and needs nothing. A prototype of an
edge-preserving resample on the real atlases (out/fe_tex/upscale_proto.py: separable Catmull-Rom 4x on premultiplied
RGBA with the alpha normalised to the texture's peak, then, for a texture whose texels are mostly empty or at the
peak, a smoothstep of half-width 0.22 about 0.5 coverage) gave crisp, smooth glyphs and logos where nearest
neighbour gives blocks; only hairline strokes thin out. An AI upscaler (Real-ESRGAN or similar) would do better on
the art and worse on text, and brings a model and a tool to install.
Decision (Erik, from the recommendation): the upscaler first, in the app; the pack second, from the same scaler.
1. The Metal backend upscales, at decode, the textures of through-mode draws that come from guest memory in a
   palette or 16-bit format (the fonts, the icons, the art; not the 32-bit movie and TV pictures, not targets, not
   mipmapped textures), by 4 whatever the internal scale, with the prototype's resample written in C++ in
   `src/gpu/`. The cache keys the upscaled texture apart from the plain one. Through-mode UVs are already normalised
   by the GE's texture size, so a larger texture samples in place; an upscaled texture samples linear, since the
   GE's nearest filter was for one texel a pixel.
2. The player's switch is a game option row (patch 0019-game-option-rows): "Text and sprites", choices "Original"
   and "Upscaled", default Upscaled at first, Original since 2026-10-12 (see the amendment below;
   `game.sprite_upscale`, `PURE_SPRITE_UPSCALE`), on the Video tab after the
   30 fps modes and Flashes rows. It is the Metal backend's: under the Vulkan renderer the row is shown but does
   nothing until the pack exists (point 4), and says so in its help.
3. The checks measure the PSP's picture: every tool run has `PURE_SPRITE_UPSCALE=0` through `tools/purelib/port.py`
   beside the other two, so the suites, the HUD check and the sweep stay where they were measured. One check runs
   with it on: a frontend scene and a race HUD scene at internal scale 4, each reduced to 480x272 by the centre
   pixel, within the scene's limit of the reference (the picture is the same picture), with the full-size shots
   differing from the plain ones (the detail is there), the HUD found, and the route's decode time bounded.
4. Second (task 074): a dump switch that writes the upscaled textures as a PPSSPP-format texture pack with the
   framework's keys, so the Vulkan renderer on Windows draws the same art through its pack loader, and so an AI pass
   can replace the PNGs of the art atlases in that pack and be compared. The pack is built locally from the player's
   disc and is never committed.
Consequences: task 073 (the scaler, the row, the pin, the check), then 074 (the pack). The exit for 073: the
frontend's text and art at 4x without blocks (Erik's eye, and the check's two scenes); the suite, the HUD check and
the menu dumps unchanged with the option off; a race at internal scale 4 still at 60 fps. The frontend at 60 fps
stays a later item.
Alternatives: a texture pack first (needs a local build step and the Metal pack path before anything is seen); a
pixel-art scaler of the xBR family (GPL-3 for xBRZ, which would change the binary's licence; and its look suits
pixel art more than antialiased type); vector fonts drawn by the port in place of the atlas (the text is drawn
glyph by glyph from the atlas by the game, so the hook would be deep).
Status: accepted (Erik); amended 2026-10-12.

Amendment (Erik, 2026-10-12, after playing the app at 0.1.0-56673a2): the row's default is Original. The resample
reads soft, "AI upscaled", against the sharp 3D picture at the display's resolution, and the elements the rule leaves
alone (32-bit, mipmapped and target textures) sit beside the upscaled ones at their own texels. Both are the method's
limits, not a tuning: no filter puts into a 15-pixel glyph the detail a 4x display wants. The code, the row, the pack
tools and the checks stay as they are (the one check with the option on names it, so nothing measured moves). A sharp
frontend, if it is wanted later, is an asset job delivered through the texture pack (task 074's machinery): the fonts
re-rendered from their typeface at 4x into the atlases' layout, the art redrawn, and a pack loader for the Metal
backend, which has none. Not started; Erik chose other enhancements first.

## D-019  2026-10-12  E5: texture detail at the internal scale
Context: after E7 (D-018, amended: the upscaled menus rejected) Erik chose texture filtering next. A race frame of
this port at internal scale 4 is sharp at its edges and soft on its surfaces: the track a few ship lengths ahead,
the walls at a grazing angle, the scenery. A recording of three Vineta K frames (the planning session, 2026-10-12;
out/e5/race3.gerec on the Mac, frames 6300 to 6302 of the single-race route on a fresh stick) says why. Of 883
textured draws a frame, 74% sample a texture with 2 to 5 levels (CLUT4 and CLUT8, almost all with 4), every one
with linear magnification, minification and mip filters (trilinear); 762 of the 1969 mipmapped draws over the three
frames use the GE's auto rule (648 of them lit: the ships and the moving things) and 1207 the slope rule with a bias
the game sets per draw (-90 to +74 sixteenths of a level, median +25: the track and the scenery), none the constant
rule. Both backends pick the level as the GE does for a 480x272 picture (task 037, task 058; D-015: the auto rule's
gradient per PSP pixel, the slope rule by depth alone), so at internal scale S a surface is drawn from a level
log2(S) coarser than the pixels could show: at 4x, two levels, a quarter of the texel density each way. That is the
softness. E3's samples of the level are isotropic too, so a wall at a grazing angle blurs along its length.
Decision (Erik, from the recommendation):
1. A "Texture detail" game option row (patch 0019-game-option-rows), key `texture_detail`, choices "Original" and
   "Enhanced", default Enhanced, `PURE_TEXTURE_DETAIL`, on the Video tab after the Text and sprites row. The row is
   the Metal backend's first (task 075); the Vulkan renderer follows in a task of its own (the same rule in
   `ge.frag`, a sampler with anisotropy, the device feature), and the row's help says so until then.
2. Enhanced moves the GE's D, whatever the rule, down by 16 x log2(S) at internal scale S: the level the GE would
   pick had the PSP S times the pixels each way, the game's per-draw intent (its slope and bias) kept relative. For
   the auto rule that is the gradient per drawn pixel; for the slope rule the same shift. D is still clamped to the
   levels the texture has, so a surface close by draws level 0 as before. At scale 1 the shift is 0.
3. Enhanced samples the mipmapped draws anisotropically (16 taps at most, the device's limit if lower): the level
   from the GE's shifted D through explicit gradients scaled to it, so the GPU takes its taps along the footprint's
   long axis at the finer level the short axis allows. Draws of a texture with one level, the 2D draws, the targets
   sampled as textures and the sprite upscale are untouched; Original is the path as it was, to the pixel.
4. The checks measure the PSP's picture: every tool run has `PURE_TEXTURE_DETAIL=0` through `tools/purelib/port.py`
   beside the other three. One check runs with it on: the four race HUD scenes at internal scale 4, each reduced to
   480x272 by the centre pixel within the scene's limit of the reference (the picture is the same picture), the
   full-size captures differing from the Original ones (the detail is there) and holding more high-frequency energy
   on the track, the HUD found, a race at scale 4 still at 60 fps in the window.
Consequences: a visible gain on every 3D surface beyond a few ship lengths and on every angled one, from the
texels the game already has; nothing invented, so none of E7's look. The frame costs anisotropic taps on three of
four textured draws; the M4 Pro has the margin, the check measures it. The Vulkan renderer does the same since task 076
(patch 0020-vulkan-texture-detail, the option named by `GameProfile::texture_detail_option`), so the rig gets it too. Not changed: the levels' texels, the GE's
filters, the lens flare and bloom chains at 1x (D-015).
Alternatives: forcing level 0 everywhere (the shimmer of docs/fidelity.md difference 2 at distance, the game's
blur-by-design on far scenery lost); a mip bias alone without anisotropy (the softness along a grazing wall stays);
letting the GPU pick the level itself for the auto draws (ignores the game's slope draws, three of five).
Status: accepted (Erik).

## D-020  2026-10-13  E2: the 3D view at the window's shape (ultrawide)

**Context.** Erik's pick after the DLC and the rig's stutter arc (2026-10-13): play at odd aspect ratios such as
21:9. The framework has the mechanism on its Vulkan renderer already, the Aspect ratio row's Fill (vendor
`VulkanRenderer`, `wanted_target_extent`, `interface_fit`): the target takes the window's shape, so a PSP pixel is
wider than square, the game is told the picture's width over height once a frame through
`GameProfile::view_aspect_frame` and is expected to draw its 3D view at that shape, and the 2D interface's draws into
the shown framebuffer are pulled in about the screen's centre to square pixels again (through-mode draws narrower
than 470 PSP pixels that do not sample a rendered picture). Fill is offered only when the profile has the hook
(`supports_fill`). The Metal shell has no Fill (D-008's shell answers Original for it).

The audit of the game (out/aspect/, Ghidra decompiles): Wipeout Pure keeps its camera's field of view in three floats
at 0x08b1fb10 (degrees, 65 by default), 0x08b1fb18 (the tangent of half the vertical angle) and 0x08b1fb14 (the
horizontal tangent, written as the vertical one times 480/272 by every writer: the Camera constructor at
0x0883f9b0, the camera modes at FUN_088467f0, FUN_088473e4 (the start sequence, once a frame while it blends),
FUN_08849970 and FUN_0884b400). The projection itself is built by FUN_08a31148(fovy in radians, aspect, near, far,
y scale, frame object): m00 = cot(fovy/2)/aspect, m11 = cot(fovy/2), uploaded through the matrix setter
FUN_088ee1a4 and copied back into the game's own projection at 0x08b18d80, which the CPU-side transforms read
(FUN_0881e048, FUN_08820728: the lens flare's sun position among them). Six call sites pass the aspect: the race
camera's apply FUN_0883ff34 passes the literal 1.7647059 (f13, a lui/ori immediate), the frontend's three 3D views
(FUN_088b31c8, FUN_088c99d4, FUN_088c9ce8) the literal 0x3fe1e1e2, and FUN_08869290 passes 1.0 (a square view,
left alone). Unlike the framework's own game, whose aspect sits in a camera object a memory write can change, the
constant here is in code, so the hook has to be a function override. The runtime offers one: `Runtime::
register_function(address, fn, name)` with a name that is not a generated unit's disables cross-unit chaining into
that unit and routes every call through the function table, where the profile's function runs with the guest
context; it can read and change the argument registers and then call the generated body
(`Runtime::lookup_function`, saved before the registration). All six callers lie outside FUN_08a31148's 16 KiB
unit, so all reach the override.

**Decision.**
1. The player's switch is the framework's Aspect ratio row, Fill; no new row. Fill does something only when the
   window's shape differs from 480:272 (a resized window, or fullscreen on a 21:9 or 32:9 display).
2. The profile implements `view_aspect_frame`: on the first call it saves the generated FUN_08a31148 and registers an
   override at 0x08a31148 that replaces an aspect argument within 1e-4 of 480/272 (f13) by the view aspect of the
   frame, then runs the generated body; other aspects pass unchanged. At each flip with an aspect other than 480/272
   it writes 0x08b1fb14 = 0x08b1fb18 x aspect, so the game's own uses of the horizontal tangent follow; when the
   aspect returns to 480/272 after a change it writes the PSP's value back once; at exactly 480/272 with nothing
   changed before it writes nothing. The override is a profile function, not a vendor change (task 084).
3. The 2D interface: Wipeout Pure's menus and HUD are transformed orthographic draws, not through mode (task 073's
   finding), so the Vulkan renderer's fit rule gains "or orthographic and unlit", the sprite rule of E7, as a vendor
   patch (task 085). Screen-wide draws (fades, backdrops) and draws that sample a rendered picture (the bloom chain)
   stay spread, as the rule already says.
4. The Metal shell and backend gain Fill: a target of the window's shape, the viewport scale per axis, the same fit
   rule, `supports_aspect(Fill)` true, the shell presenting the whole target (task 086). Until then the hook is a
   no-op on Metal, since the shell reports 480:272.
5. A check (`aspect_check.sh` under tools/, task 084): a 21:9 window (a test-only `<prefix>_WINDOW_SIZE=WxH` on the Vulkan window's
   creation, vendor, tooling), the race route twice, Original and Fill, the race_hud capture of each: the Fill
   picture's central 480/272 over the window's shape of its width, scaled to 480x272, matches the Original capture
   within a limit (the same vertical field of view), its outer strips hold the scene (not black, not a stretch of
   the edge), and the draw count at the frame is reported for both (culling that follows the aspect draws more).
6. What the player should see, by eye: at 21:9 the race shows more of the track to each side at the same height; the
   HUD and menus keep their proportions; the lens flare sits on the sun; no objects appear late at the edges.

**Consequences.** One profile override of a game function, the first in this port; a cost of per-PC dispatch for the
16 KiB unit around 0x08a31148 (a few render helpers), to measure in the stutter check. The frontend's 3D previews
(the ship and track views) widen too, which is right for a 3D view. The one-frame-late depth of patch
0022-vulkan-async-readback is unrelated. Effects stay in guest space (the screen is still 480x272 to the game), so
the bloom chain and the lens flare's depth read work unchanged. Culling that reads the horizontal tangent from
memory follows the flip write; culling built otherwise would show as pop-in at the edges, which the check's draw
count and Erik's eye would catch; the fix then is a second override at the culling function.

**Alternatives.** Rescaling the projection in the renderer (m00 = m11/aspect for perspective matrices at the PSP's
ratio): no game knowledge needed and both backends at once, but the game's CPU-side transforms keep the narrow
projection, so the lens flare and any screen-space placement land off the sun by up to a quarter of the width, and
culling never widens. Patching the code immediates: they are compiled into the recompiled units, so only a regen
could change them. A new Esc menu row: the framework's row already says Fill.

**Status.** Accepted 2026-10-13. Tasks 084 (the hook and the check, Vulkan), 085 (the Vulkan fit for orthographic
draws), 086 (Metal Fill).

## D-021  2026-10-13  VR on Windows: an OpenXR shell over the replay path

**Context.** Erik asked (2026-10-13) whether a VR mode could ever come, and that Windows only would be fine; the rig
has a Meta Quest over Link, which exposes the standard OpenXR runtime. Three pieces make it tractable rather than a
rewrite. The camera is in hand since E2: the projection builder FUN_08a31148 takes the field of view and the aspect
as arguments and the profile already overrides one of them (src/profile/aspect.cpp), and the camera's horizontal
tangent write widens the game's own culling. The Vulkan renderer re-draws a frame with a changed camera today: the
frame interpolation records every draw of a frame (`record_draw_for_replay`, the `DrawSummary`) and `replay()`
draws them again with blended view matrices (vulkan_renderer.cpp about line 8158), which is what stereo needs,
once per eye with the headset's view and projection in place of the blend. And the recompiled game leaves most
of a 72 Hz frame unused on the rig since the inlining fix. On the Mac there is no consumer VR runtime, and Vision
Pro would be a separate visionOS application, so this is Windows only by nature, not by choice.

**Decision.**
1. A spike first (task 088, on the rig): an OpenXR shell (a new file under src/host/, ours, Windows only) that
   opens a session on the Vulkan renderer's instance and device, and at each game flip replays the frame once per
   eye into the runtime's swapchain images with the eye's view (the head pose composed with the game's view) and the
   eye's projection (the runtime's asymmetric field of view), submitting through the OpenXR frame loop; the desktop
   window keeps showing the game. The 2D interface (through-mode and orthographic unlit draws, the classification
   E2 built) is drawn as a flat panel at a fixed distance in front of the eyes. No head tracking reaches the game in
   the spike: the game's culling stays at its 65 degree field of view, so the periphery pops in when the head turns;
   the FOV argument of the projection override closes that in the milestone. The game stays at 60 Hz; the runtime
   reprojects.
2. What the renderer needs from the vendor, as patches: instance and device extensions and a physical-device
   choice supplied by the shell through `RendererConfig` (OpenXR names what it needs before the instance exists),
   the instance, device and queue handed back, and a replay entry that takes a per-draw transform override and
   draws into a caller's image. Everything else is the shell's.
3. The milestone, only if the spike shows a race in stereo at the headset's rate without stalls: head tracking into
   the game's view matrix (the setter after the camera's apply), the FOV override for culling, the kernel's vblank
   at 72 or 90 Hz (the uncapped-fps question, with E4's audit), the panel's placement and the menu in VR, comfort
   options (a fixed horizon, the ship as the reference frame), and a check that renders both eyes headless from a
   recorded pose for the suite.
4. The spike's judge is Erik in the headset; its mechanical proof is the per-eye capture (`PURE_VR_DUMP`) and the
   frame-time line, since nothing of it can run on the Mac.

**Consequences.** A Windows-only feature in a port that has kept both platforms equal; the docs say so. The
rig needs the Meta Quest Link app (its OpenXR runtime active) and the Khronos OpenXR loader beside its SDL
(`deps/openxr`). A milestone on the scale of the Metal backend, five to eight tasks, all on the rig.

**Alternatives.** Rendering the scene twice from the game (two camera applies a frame) would double the guest's
work and fight the game's frame structure; the replay path draws the recorded frame for free. A head-tracked
desktop view without stereo is a smaller first step but proves nothing about the runtime. Waiting for a Mac VR
runtime: none is announced.

**Status.** Accepted 2026-10-13. Task 088 the spike, on the rig.

## D-022  2026-10-14  E8: the display rate (the vblank at the display's refresh)

**Context.** Erik's pick (2026-10-14): frame rates beyond 60. The game's frame rate is its vblank rate: Single
Race and Tournament wait one vblank a frame, the modes E4 freed do the same, the frontend and the two-vblank
screens wait two. The port's kernel ticks that vblank at the PSP's 59.94 Hz, one constant, `kVBlankPeriodUs =
16'683` (host/kernel/kernel.hpp:86, advanced at kernel.cpp:538). The game's speed is measured time, not frames:
its frame timer (docs/timing.md, "The game's clock in a race") takes `sceKernelGetSystemTimeWide`'s difference,
clamped to 0.067 s, and every object integrates that dt, so a vblank of 8.3 ms gives half-size steps, as a
dropped frame today gives double ones. E4's audit found no per-frame logic in the race beyond the frame object's
lock byte. What does count frames: the race-start fade's countdown (`+0x117c`, decremented a frame; D-016) and,
unaudited, the frontend's animations and the save dialog. The framework's "Frame rate" row on Vulkan is frame
interpolation (blended pictures), not the game running faster, and the Metal shell has no such row. Other uses
of the constant: the media HLE's hcount and vblank-flag arithmetic and its movie-frame step (hle_media.cpp), the
pacer's game frame (frame_pacing.hpp `kGameFrameUs`), and the Metal shell's present timing (`kPspFrameSeconds`:
a picture is asked for at its vblank's real time plus one PSP frame). The race costs about 3 ms of CPU and GPU a
frame at scale 4 on this Mac, inside a 120 Hz frame's 8.3 ms; Erik's display is 120 Hz.

**Decision.**
1. The kernel's vblank period becomes a runtime value with the PSP's as its default: `Kernel::vblank_period_us()`
   and `set_vblank_period_us()`, used by the tick, `last_vblank_us()`, the media HLE's hcount, vblank flag and
   movie step, the pacer's game frame and the Metal shell's present timing (a vendor patch, the task names it, plus
   the shell, ours). A change takes effect at the next vblank; the count of vblanks so far stands.
2. A game option, `display_rate`, the row "Display rate" (Original, Display) after Texture detail: Original is
   59.94 Hz; Display sets the period from the shell's `display_refresh()` when that is above 60 Hz, else nothing
   changes (a 60 Hz display plays as before). `PURE_DISPLAY_RATE=0|1` the run-control switch, and a test-only
   `PURE_DISPLAY_HZ=N` that names the rate when no display is there (headless) or to try one. Default Display,
   Erik's wish; the checks pin Original (`ENHANCEMENTS_OFF`, `SCRATCH_SETTINGS`), as for every enhancement.
3. What it means for the other rows: at the display's rate the "30 fps modes" row's Original (two vblanks) is half
   the display's rate, 60 on a 120 Hz display, and 60 fps (one vblank) the display's rate; the frontend runs at
   half the display's rate. The row's help says so. The Vulkan "Frame rate" row keeps its meaning (interpolation
   at or above the game's rate, which is now the display's).
4. Per-frame logic is measured, not assumed: a check runs the Time Trial route and the swept race at 59.94 and at
   120 (`PURE_DISPLAY_HZ=120`, headless) and compares what the game does per second of its own clock: flips (60
   against 120 in the race, 30 against 60 in the menus), the lap time and the standing start (physics at the
   finer step), the race-start fade's duration in race-clock time (the countdown is per frame: if it halves, a
   hook doubles the countdown at a faster vblank, the E4 way, in the same task), and the menus' and the save
   dialog's behaviour by eye. A finding the task cannot close by a hook is reported, not worked around.
5. The window: on this Mac's 120 Hz display the Metal shell presents every refresh at the display rate (the
   stutter check at 120 says whether the 8.3 ms budget holds); on the rig's 100 Hz display the game runs at 100.

**Consequences.** The frontend at 60 comes with it. VR (D-021) wants the same control for 72 or 90 Hz. The
pacer's constants and the Metal shell's present timing follow the period, which the frame-rate and stutter
checks at the PSP's rate must show unchanged. The media HLE's hcount arithmetic scales with the period (286 lines
a vblank), untraced by any game here. A per-frame counter missed by the check shows as something running at
double speed on a 120 Hz display with the row on, which the Original choice undoes.

**Alternatives.** Frame interpolation (the Vulkan row) is smoother motion, not the game running faster, and the
Metal shell has none. Decoupling the game's logic from the vblank (a separate render loop) would be a rewrite of
how the game draws.

**Amended 2026-10-14 (task 089's finding).** The period follows the display only while the race backend lives
(the backend pointer at 0x08a8c5f4 and the frame object both in user RAM, E4's gate; not the lock byte, which is
0 in the 30 fps modes at Original); outside a race it is the PSP's. The frontend's screen transitions count frames
(27 flips a build-in whatever the rate), so at the display's rate the menus would run at twice their speed, while
the boot cards, the language screen's build-in, the save confirm's flashing and the typed help line follow time;
the fade needs no hook (FxScreen re-arms it from measured time: 1.88 s in 113 flips at 120, 1.90 s in 57 at
59.94); the physics holds (the standing start matches through 1.5 s within a tenth of a km/h); one speed pad fires
0.085 to 0.1 s and 4.2 to 4.6 m early at 120 (a per-frame trigger test, reported, not bounded); the test follower's
per-flip steering moves the lap mean more than the race does. Points 3 and 5's "the frontend at half the
display's rate" are withdrawn: the frontend stays at the PSP's cadence, and the 30 fps modes row keeps its meaning
inside a race at the display's rate (Original: two vblanks of the display's period).

**Amended 2026-10-15 (task 091's measurement).** The race's period is the display's refresh times (1 + margin) in
time, round(1e6 / (rate x (1 - 0.005))): 119.40 Hz on a 120 Hz display, 99.50 Hz on a 100 Hz one. At exactly the
display's rate vsync paces the game, a missed refresh is real time lost for good, and the sound, made on the game's
clock, falls behind until the audio sink skips (Erik heard it on both renderers; 9 skips in a race on Vulkan, 105 on
Metal at Auto). The margin is the smallest of 0.005, 0.0025 and 0.001 at which every run on both shells kept the
sound whole (`tools/display_rate_check.sh --audio`: one skip, the race load's; no second under 95% speed); at 0.0025
Vulkan still skipped. The cost is one refresh shown twice every 1.7 s. The sink's own tolerance of a late producer
(task 081's fork) and the presents holding the game thread (Vulkan's two-image FIFO swapchain) stay open.

**Status.** Accepted 2026-10-14, amended the same day and 2026-10-15. Tasks 089 and 091.


## D-023  2026-10-19  E8: the audio sink keeps a late producer's content (task 081's fork b+)

**Context.** Task 081 found what the sink's stalled-producer jump really was: a continuous channel whose lead a dip
had eaten, its cursor at the device's read position, snapped 2048 frames forward, 46 ms of silence in that channel
after every dip (the clicks Erik hears, and the rig's early-race skips at 100 Hz, docs/timing.md "On the rig's 100 Hz
display"). It also showed that dropping the played frames without rebuilding a lead near-mutes a channel whose
producer stays below real time (the harness's 85% race). The fork it left: (a) a smaller jump; (b) keep the content
and gap only the lateness; (b+) b plus an inaudible lead rebuild by lowering the SDL stream's frequency ratio;
(c) HLE backpressure, ruled out by every brief.

**Decision.** (b+), with a stall floor: a cursor more than 2048 frames behind the device is a stall or restart and
snaps as before (counted `resyncs=`); a cursor less behind drops only the frames already played (`late=`, `lates=`),
writes the rest where it belongs, and the device runs at ratio 0.99 (17 cents low) until it has read 204800 more
frames (about 4.6 s), which rebuilds 2048 frames of lead for every channel that keeps real time. Patch
0031-audio-sink-late-writes; `PURE_AUDIO_SNAP=1` keeps the old rule for an A/B. Not (a): a smaller gap is still a
gap each dip. Not (b) alone: it rides at zero lead and crackles on jitter. Not (c): the HLE's blocking output is the
kernel's territory and would change the game's timing.

**Consequences.** A dip costs a few ms of one channel's content and 4.6 s of a 1% pitch drop instead of a click.
A producer persistently below real time still snaps, so the harness's slow races keep their resync counts; the
measure of this decision is `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio` at full speed (resyncs 0, the
dips visible as `lates=`) and Erik's ear on the rig at 100 Hz (task 097, row 7 and the rig's step 4).

**Status.** Accepted 2026-10-19; measured in a window on the Mac (task 097: a no-op there, nothing runs late at
119.4 Hz) and on the rig at 100 Hz (tasks 500 and 501).

**2026-10-19, task 501.** The rig measured a consequence the decision did not foresee. "A dip costs a few ms of one
channel's content" holds only while a lead is left: a producer at real time cannot close a deficit by itself, so
once its cursor is behind the device, every write drops its played frames and the device plays that many frames of
silence, write after write, until the 1% ratio has eaten the deficit at 441 frames a second (task 500, run 1: 19961
frames of silence in 84 pieces over 2 s, ten times the old rule's one jump). The three runs that stayed clean did so
because the race load's landing happened to arm the recovery while 777 to 2595 frames of lead remained. So the
arming threshold moved from a quarter of `kPrebufferFrames` to the whole of it, with a device present only (the
no-device ring sits at exactly that lead): the rebuild starts while a lead is left and the deficit never forms. The
ratio and the recovery length stand; a cursor more than `kLateLimit` behind still snaps.

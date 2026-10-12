# Decisions

| ID | Date | Title | Status |
|---|---|---|---|
| D-001 | 2026-10-05 | Vendor base: TeamGDB/PortableKit pinned at 8b0c3fe | accepted |
| D-002 | 2026-10-05 | Renderer path: Vulkan/MoltenVK bootstrap, then native Metal behind a seam | accepted |
| D-003 | 2026-10-06 | GE backend seam: shell vs GeBackend; Vulkan adapted, Metal implemented against it | accepted |
| D-004 | pending | Determinism: virtual clock, fixed RTC, frame-indexed input | open (M3) |
| D-005 | pending | Savedata directory layout, DLC-ready | open (M5) |
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

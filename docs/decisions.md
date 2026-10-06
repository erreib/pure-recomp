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
replace only the latter, and patches 0003-0008 now define what this game needs from a backend.
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
Consequences: patch 0010 (task 026) is the second mechanical vendor patch of the series and an upstream candidate
like 0009. Headless routes become possible but stay slow until the kernel's host-wait sleep is changed (patch 0011,
Fable). The Metal presenter can show a Metal texture directly rather than through a read-back.
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

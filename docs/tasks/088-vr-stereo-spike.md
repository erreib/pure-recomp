# 088: The VR stereo spike (Windows, the rig, a Quest over Link)

Milestone: VR (D-021) | Branch: task/088-vr-stereo-spike | Status: OPEN

## Goal
A race seen in the headset in stereo: at each game flip the frame is replayed once per eye with the headset's view
and projection and submitted to the OpenXR runtime, the HUD on a flat panel in front, the desktop window still
showing the game. No head tracking reaches the game and the game stays at 60 Hz. The spike decides whether the VR
milestone of D-021 goes ahead: the question it answers is whether the replay path holds the headset's rate on the
rig without stalls. Windows only; it runs on the rig, with the Quest over Link. Read D-021 first.

## Read first
- docs/decisions.md D-021 and D-020 (what the camera hooks are); src/profile/aspect.cpp (the projection override:
  `f12` the field of view, `f13` the aspect, how a profile override reaches a generated function)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `initialize` (the instance about line 2322: SDL's extensions
  plus the renderer's; the physical device and the device about lines 2399 to 2468), `RendererConfig`
  (vulkan_renderer.hpp:43), the frame interpolation's recording (`record_draw_for_replay`, about line 7830),
  `replay(commands, slot, t)` (about line 8158: how the recorded draws are drawn again with a transform rebuilt
  from the summaries, `state.push.transform`), `finish_interpolated_frame`, `submit_and_present`, and the targets
  the blended frames use ("a target per present slot", about line 1719); host/gpu/frame_interpolation.hpp
  (`DrawSummary`, `viewport_into_clip`, `is_orthographic`)
- The 2D classification (D-020 point 3, patch 0028-vulkan-orthographic-fit): through mode, or orthographic and
  unlit, into the shown framebuffer; these draws become the panel
- docs/ge-backend.md section 8 (the shell seam: what a shell implements; the Vulkan shell is the vendor renderer
  itself under `PURE_SHELL=vulkan`); src/host/pure_main.cpp (how a shell is chosen); docs/windows.md (the rig's
  build, deps beside the checkout, `tools/env.sh`); CMakeLists.txt (how our sources join the executable)
- The OpenXR 1.1 specification's Vulkan binding: `XR_KHR_vulkan_enable` (the instance and device the application
  creates must enable the extensions `xrGetVulkanInstanceExtensionsKHR` and `xrGetVulkanDeviceExtensionsKHR` name
  and use the physical device `xrGetVulkanGraphicsDeviceKHR` returns), `xrCreateSession` with
  `XrGraphicsBindingVulkanKHR`, swapchains (`xrEnumerateSwapchainFormats`, `xrCreateSwapchain`,
  `xrEnumerateSwapchainImages` giving `VkImage`s), the frame loop (`xrWaitFrame`, `xrBeginFrame`, `xrLocateViews`,
  `xrAcquireSwapchainImage`, `xrWaitSwapchainImage`, `xrReleaseSwapchainImage`, `xrEndFrame` with one
  `XrCompositionLayerProjection` of two views, and an `XrCompositionLayerQuad` for the panel), and the
  hello_xr sample of the Khronos OpenXR-SDK-Source as the reference for the order of calls

## Deliverable
1. Vendor patch `0029-vulkan-renderer-hooks` (the smallest set): `RendererConfig` takes extra instance extension
   names, extra device extension names and an optional physical-device chooser (a callback given the candidates,
   returning one, or null for the renderer's own choice); after `initialize` the shell can read the instance,
   physical device, device, queue and queue family; a `replay_into(image, extent, layout, override)` entry (or the
   closest shape the code allows) that draws the last recorded frame's draws into a caller's `VkImage` with
   `override(summary) -> transform` supplying each draw's clip transform (the eye's projection times the eye's
   view times the draw's world, or the panel transform for a 2D draw), on the renderer's queue, with the caller's
   synchronisation. Nothing changes for a shell that sets none of it; the suite proves that on the Mac later.
2. `src/host/openxr_shell.cpp` (Windows only, `PURE_SHELL=openxr`, built when the OpenXR loader is found beside the
   checkout at `../deps/openxr` or where `OPENXR_ROOT` says; otherwise the shell is absent and the name falls back
   to the Vulkan shell with a line saying so): the Vulkan shell plus an OpenXR session on the renderer's instance
   and device; two swapchains of the runtime's recommended size and a format the renderer can render into; a
   `LOCAL` reference space; at each game present, the frame loop: wait, begin, locate the views, acquire both
   images, replay the frame into each with the view's pose composed with the game's view and the view's
   field-of-view projection (`xrLocateViews` gives angles; build the asymmetric projection with the game's near
   and far planes), the 2D draws onto a quad layer at about 1.5 metres with the PSP's shape, release, end. The
   desktop window keeps the ordinary picture. `PURE_VR_DUMP=DIR` writes both eyes' images at the flips
   `PURE_SCREENSHOT_EVERY` names; `PURE_PERF=log`'s line gains the XR frame's wait and submit times.
3. A run on the rig: a Single Race on Vineta K in the headset (Erik's eyes), and the mechanical record: the two
   eye captures at a race frame (in the Result, as numbers: the images' size, the left and right view's pose and
   fov from the log), the `[perf]` line over a minute of racing (the XR wait, the replay, the submit; the share of
   frames late by `xrWaitFrame`), and the runtime's own frame-timing overlay if Link offers one.
4. Docs: docs/windows.md (the rig's VR setup: the Meta Quest Link app, its OpenXR runtime active, the loader at
   `../deps/openxr`, `PURE_SHELL=openxr`), docs/ge-backend.md 8.2 (the shell listed), docs/status.md (a VR bullet
   with the spike's figures and the judgement), patches/README.md and docs/upstream.md (the hooks: a candidate,
   any port wanting XR or a second view), README.md's known issues or features only if the spike ships in a
   release, which it does not.

## Acceptance criteria
- [ ] In the headset: a race in stereo, the world at a plausible scale, the HUD on a panel in front; turning the
      head looks around (with the periphery popping in at the game's own field of view, expected); no double
      images or swapped eyes.
- [ ] The mechanical record above in the Result; the eye captures exist and differ (a disparity).
- [ ] The frame-time line: the median XR frame within the headset's period (13.9 ms at 72 Hz) and the share of late
      frames reported, whatever it is (the spike's finding, not a bound).
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 7/7 on the rig with the patch (the hooks unused by
      the Vulkan shell change nothing); `tools/patches.sh check` 29; `python3 tools/docs_check.py` PASS.

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan && tools/patches.sh check && python3 tools/docs_check.py`
(the headset run is by hand: its record is the Result)

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp and .hpp, frame_interpolation.hpp/.cpp, exported as
  patches/0029-vulkan-renderer-hooks.patch (commit patches/, never vendor/)
- src/host/openxr_shell.cpp (new), src/host/pure_main.cpp (the shell's name), CMakeLists.txt (the loader found and
  the shell built on Windows only), tools/env.sh (a Windows `OPENXR_ROOT` default beside the checkout)
- docs/windows.md, docs/ge-backend.md, docs/status.md, patches/README.md, docs/upstream.md,
  docs/tasks/088-vr-stereo-spike.md

## Must not touch
- vendor/portablekit/include/psprecomp/; src/profile/ (no head tracking into the game in the spike); src/gpu/ (the
  Metal side); the kernel (no 72 Hz vblank in the spike); config/; generated/, game/, disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
60

## Escalate when
- The OpenXR runtime is not active on the rig (`xrCreateInstance` fails, or the Meta runtime is not the system's):
  stop, say what the runtime reported; Erik installs or switches it.
- The renderer's replay cannot draw into a caller's image or take a per-draw transform without rewriting the
  interpolation's recording (the summaries lack what an eye needs): stop with what is missing.
- The instance or device cannot be created with the runtime's extensions on this driver.
- Anything would touch include/psprecomp/, the kernel or the profile.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:

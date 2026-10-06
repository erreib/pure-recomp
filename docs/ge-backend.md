# The GE backend seam (D-003)

Written 2026-10-06, after patches 0003 to 0008 established what Wipeout Pure asks of a renderer. The vendored
`VulkanRenderer` (host/gpu/vulkan_renderer.cpp, ~8k lines) fuses two things: the **shell** (SDL window, events, pad
sampling, scripted input, ImGui, settings, frame pacing and interpolation, capture) and the **GE backend** (what the
PSP's graphics engine did: targets in VRAM, textures, blending, stencil-as-alpha, read-backs). The Metal backend
replaces only the second. The seam sits between them.

## 1. The backend interface

`portablekit::gpu::GeBackend` (new, vendor patch), implemented by `VulkanGeBackend` (a thin adapter over the existing
renderer's draw path; the renderer itself is not split) and later `MetalGeBackend` (ours). The shell owns a
`std::unique_ptr<GeBackend>` chosen by `<prefix>_GE_BACKEND` (`vulkan`, `metal`, `null`, `record`).

| Method | What it must do (from this game's needs) |
|---|---|
| `initialize(const BackendConfig&, std::string& error)` | device, internal scale (1x first; 2x the shell's default today), sharp/filtered textures |
| `begin_frame()`, `begin_display_list()` | per-frame and per-list bookkeeping (guest-word snapshots of targets are taken at a target's first draw of the frame: patch 0003's lookup depends on it) |
| `submit(const DrawCall&, const GuestMemory&)` | the whole GE state of one draw: vertex formats (s8/s16/f32 positions, uv, colours, normals, 8 bone weights, morph), through mode, PSP clip z in [-w, w], alpha test with GE numbering (0 NEVER, 1 ALWAYS: patch 0005), colour test, blend equations incl. FIX colours and the 2x/ABSDIFF modes, logic ops, per-channel write masks (PMSKC) and the alpha mask (PMSKA), **stencil ops as alpha writes** with a real stencil attachment and the alpha copy rule (patches 0004/0006), dual-source blending for REPLACE under source-alpha blends, fog, 4 lights, texture binds incl. CLUT4/8/16/32, DXT1/3/5 in the PSP block layout, swizzle, mip levels, and **framebuffer-as-texture binds resolved to the target that starts at the address** (patch 0003) |
| `block_transfer(const BlockTransfer&, const GuestMemory&)` | GE copies between VRAM rectangles, reading rendered targets back first when the source is one |
| `write_back_frame(GuestMemory&)` | the display target's pixels into guest VRAM when the CPU needs them |
| `read_back_framebuffer(address, GuestMemory&)` | one target into guest VRAM (block transfers, movie frames) |
| `write_back_depth(color, depth, stride, GuestMemory&, why)` | the depth target as Z16 into guest VRAM at a SIGNAL (patch 0008: the lens flare reads a 4x4 block around the sun) |
| `upload_frame(display, pixels, w, h, stride)` | a CPU-drawn picture (movies, `show_cpu_picture_in_vram`) into the display target |
| `present_image(display_address) -> PresentedImage` | the display target at the display address, as an image the shell composites with the UI and presents; the backend never touches the swapchain |
| `capture_frame(path)` | the presented image as BMP/PNG for the regression suite |
| `draws_submitted()`, `frames_presented()` | stats the HLE prints |
| `shutdown()` | **free every per-target resource before the pools they came from** (patch 0007) |

Out of the backend: window, swapchain, vsync, aspect, fullscreen, UI, pad, scripted input, texture packs, frame
interpolation (it works on presented images and stays in the shell), fast-forward.

## 2. Render-target model every backend must share

- A target is keyed by (guest address, stride, pixel format) and holds a colour image, a depth+stencil image, a
  dirty state and the guest-word snapshot used to tell whether the CPU wrote under it.
- VRAM aliasing is normal here: the depth bytes at 0x04110000 become a 256-stride colour target for the bloom,
  0x04132000 lies inside it, 0x04154000 is a 565 target sampled back as a texture (docs/ge-effects.md). A texture
  bind that lands in a target samples that target's image, exact-address target first.
- Alpha is the PSP's stencil. The stencil attachment is exact; alpha is the copy that sampling, blending, display and
  write-back read; the copy rule from patch 0006 (stale after ops alpha cannot express, resolved before a
  destination-alpha read and at the end of the pass) is part of the contract.
- Depth: PSP z in [0, 65535]; the vertex path remaps clip z from [-w, w]; MINZ/MAXZ and the clip-plane enable may
  stay ignored (nothing in this game needs them). `write_back_depth` stores round(z x 65535).

## 3. How Metal meets it (from the Bouncer backend, docs in ~/dev/bouncer-recomp/docs/metal-backend.md)

- Programmable blending through framebuffer fetch gives logic ops, per-channel masks and the odd PSP blend
  equations without extra passes; Metal's own blend units cover the common SA/1-SA cases and dual-source output.
- Shaders are MSL source compiled at runtime (no Xcode on this machine); one function-constant-specialised
  uber-shader per vertex-format class, as Yakumo's GLSL does.
- `mathMode = safe` and explicit `fma` where results must match the CPU rasteriser or the Vulkan backend.
- Stencil: `MTLPixelFormatDepth32Float_Stencil8`, the same copy rule.
- `present_image` returns an `MTLTexture`; the shell's Metal presenter (CAMetalLayer via `SDL_Metal_CreateView`,
  ImGui's Metal backend) composites and presents.

## 4. Validation

- `null` backend: proves the split (the game runs headless through the seam with no GPU).
- `record` backend: wraps any backend and serialises DrawCall/BlockTransfer/uploads/read-backs plus the presented
  images to a `.gerec`; `tools/gerec/ge_replay` feeds a recording to any backend and compares presented images
  (first differing draw by bisection) and runs `--fuzz` over the GE state space, backend against backend. This is
  the Bouncer method that found every bookkeeping fault there.
- `tools/frame_regress.sh --backend metal` (task 020) against the PPSSPP references.

## 5. Order of work

021 seam + null + record + Vulkan adapter (vendor patch; no behaviour change for Vulkan: frame_regress must be
unchanged) → 022 ge_replay → 023 Metal backend, first pictures (frontend, through-mode 2D) → 024 Metal 3D (race
frame against Vulkan and PPSSPP) → 025 Metal stencil/bloom/depth write-back → 026 Metal presenter + UI.

## 6. What landed (task 021, 2026-10-06)

Patch 0009 (`patches/0009-ge-backend-seam.patch`) adds the seam to the vendored framework. Files, all under
`vendor/portablekit/`:

| File | What |
|---|---|
| `host/gpu/ge_backend.hpp`, `.cpp` | `GeBackend`, `BackendConfig`, `PresentedImage`, the registry (`register_backend`, `make_backend`, `backend_names`, `BackendRegistration`), `selected_backend()` (`<prefix>_GE_BACKEND`, vulkan when unset or empty), a BMP encoder |
| `host/gpu/vulkan_ge_backend.cpp` | `vulkan`: the adapter over `VulkanRenderer` (renderer sources) |
| `host/gpu/null_backend.cpp` | `null` (system-layer sources: built without Vulkan) |
| `host/gpu/record_backend.cpp`, `ge_record_format.hpp` | `record` and the `.gerec` format (Writer and Reader, for ge_replay) |
| `host/gpu/vulkan_renderer.hpp`, `.cpp` | one new method, `display_image(address)`: the target `present()` would show, as a `PresentedImage`; it changes nothing |
| `host/hle/hle_media.cpp` | every GE call goes to the backend; the window shell stays the `VulkanRenderer` |
| `cmake/PortableKit.cmake` | the four new sources (outside the brief's "May touch", but the new files cannot be built without it) |

### The interface as landed

As in section 1, with these differences:

- `block_transfer(const BlockTransfer &, GuestMemory &)`: the memory is not const, because the backend writes a
  rendered source back into it. It is called before the HLE copies the rows; the copy itself stays in the HLE (it is
  guest memory), followed by `begin_display_list()` as before.
- Added: `name()`; `needs_window()` (asked before `initialize`: the Vulkan backend draws with the shell's device and
  targets); `gpu_decode()` and `check_gpu_decode()` (whether `GeState` hands transformed draws over undecoded; false
  unless a backend draws raw vertices, as Vulkan can with `<prefix>_GPU_DECODE=1`).
- `BackendConfig`: `vulkan_shell` (the window's `VulkanRenderer`, null without a window), `internal_scale` and
  `sharp_textures` (from the settings; the Vulkan backend keeps following the shell's settings itself).
- `PresentedImage`: `api` (None, Cpu, Vulkan, Metal), `address`, `width`, `height`, `pixels` (Cpu), `image` and
  `view` (the API handles as integers: for Vulkan the target's `VkImage` and `VkImageView`).
- The frame, as `present_frame` drives it: `upload_frame` (a main-memory framebuffer), the interface,
  `write_back_frame`, `present_image(address)`, then the shell's `VulkanRenderer::present`, the optional capture
  (`capture_frame`, `frames_presented`, `draws_submitted` for the `[render] frame N (D draws)` line), and
  `begin_frame()` for the next frame. `begin_frame()` is also called once after `initialize`.

What stays fused in the Vulkan pair, and why no output changed: the renderer still begins its frame lazily at the
first draw, upload or present, and ends it in `VulkanRenderer::present`, which also does the frame write-back's copy,
frame interpolation and the swapchain. So `VulkanGeBackend::begin_frame()` does nothing and `present_image()` only
names the image (`display_image`); the shell's present shows the same target. Every other method forwards to the
renderer method the HLE called before, with the same arguments, at the same point. The frame regression suite gave
the same fractions before and after (all five scenes +0.0000), and all five captures were pixel-identical to the
ones before the patch.

### Selection

`ensure_backend()` in `hle_media.cpp` (also behind `ensure_renderer()`, which the setup screens call first) makes the
backend `<prefix>_GE_BACKEND` names, and the window shell unless `<prefix>_NO_RENDER` is set:

| `GE_BACKEND` | `NO_RENDER` unset | `NO_RENDER` set (any value, also empty) |
|---|---|---|
| vulkan (default) | window, Vulkan draws (as before) | no rendering at all, no draw sink (as before) |
| null | window; the shell's present shows its own, empty targets (black); scripted input works | headless, no window, no GPU, every draw reaches the backend |
| record | as its inner backend | as its inner backend |

An unknown name prints the registered ones and falls back to vulkan. A backend that needs no window also runs when the
window cannot be made.

### null

Counts draws, block transfers and uploads, returns a black 480x272 Cpu image, writes it for `capture_frame`. It
prints `[render] null backend: frame N, D draws submitted (K in the last 600 frames, F fps)` every 600 frames and a
total at exit. `PURE_GE_BACKEND=null tools/run_boot.py --frames 2000 --env PURE_NO_RENDER=` boots headless to frame
2000 with 19615 draws submitted (the language screen draws 11 a frame from frame ~690).

Speed: 2000 frames take 106 s with the null backend and 106 s with `PURE_NO_RENDER=1` and no backend at all, about
19 game frames a second (63% of real time). `PURE_PERF=log` puts render time at 0.0 ms a frame, and the process
runs at about 4% of one core (`ps`: 1.95 s of CPU in 46 s), about 2 ms of CPU a frame, which would be some 450
frames a second if nothing slept. The limit is the kernel, not the seam: `user_main` waits for the main thread
to end (`sceKernelWaitThreadEnd`, a `WaitType::Host` wait) for the whole game, and while any thread is in such a wait
the unpaced clock sleeps up to 1 ms of real time per step (`Kernel::advance_clock`, kernel.cpp:451). The brief's
"> 200 fps" needs that changed (task 021, open questions).

### record and the .gerec format

`PURE_GE_BACKEND=record PURE_GE_RECORD=<file> PURE_GE_RECORD_AT=N PURE_GE_RECORD_FRAMES=M PURE_GE_RECORD_INNER=<name>`.
Frames are numbered as the inner backend's `frames_presented()` counts them once shown, the number the
`[render] frame N (D draws)` lines carry. Recording starts at the `begin_frame()` after frame N-1 and each frame ends at
the `begin_frame()` after its flip, where the inner backend's `capture_frame()` gives its image. The format is
documented at the top of `ge_record_format.hpp`: an 8-byte magic `PKGEREC\0`, a u32 version (1), then records of a u8
kind, a u32 size and a payload. Kinds: Begin, Memory (guest bytes a call reads: whole VRAM first, then texels and
palettes and block-transfer sources, each written only when it changed since last written), Words (one word every 256
bytes of a target's area at its first draw in a frame, what patch 0003's lookup compares), DisplayList, Draw (the
whole `DrawCall`, decoded vertices and indices, raw vertex bytes and bone matrices when present), Transfer, ReadBack,
WriteBackFrame, WriteBackDepth, Upload, FrameEnd (frame number, display address, the inner backend's counters, the
frame's draw and record counts, the image as a BMP), End.

`tools/gerec/gerec_dump.py FILE [--summary] [--images DIR]` lists the records, parses every Draw in full and checks
it fills its payload, and prints a per-frame table: Draw records counted in the stream, the count FrameEnd states, and
the change of the inner backend's cumulative counter since the frame before (Begin holds it before the first frame).
It exits 1 when they disagree or the file is cut short.

The race recording of the brief (`AT=6014 FRAMES=3`, Vulkan inner, `main_menu.txt` + `single_race.txt` on an empty
stick): 23.4 MB, 4250 records; frames 6014, 6015, 6016 hold 906, 905 and 906 draws, equal to the Vulkan counter's
steps (342830 before, then 343736, 344641, 345547) and to the screenshot line `[render] frame 6014 (343736 draws)` of
the same run. Frame 6016's recorded image is pixel-identical to the suite's `race_hud` capture, and the run's own
`race_hud` shot is identical too, so recording does not disturb what Vulkan draws. Each frame has one WriteBackDepth
(the lens-flare SIGNAL); frame 6016 has 12 block transfers (small 16-bit rectangles from RAM into VRAM at
0x041C9700 and up), the other two none. Memory: 4.8 MB in the first frame (VRAM included), 1.6 MB in each of the
others, mostly the 1 MB back buffer and the two 256 KB bloom buffers the bloom chain samples.

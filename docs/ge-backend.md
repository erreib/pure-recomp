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

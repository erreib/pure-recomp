# The GE backend and shell seams (D-003, D-007)

The vendored framework's `VulkanRenderer` (`host/gpu/vulkan_renderer.cpp`, about 8k lines) fused two things: the
**shell** (the SDL window, events, pad sampling, scripted input, ImGui, settings, frame pacing and interpolation,
capture) and the **GE backend** (what the PSP's graphics engine did: targets in VRAM, textures, blending,
stencil-as-alpha, read-backs). Two seams put each behind an interface, so the HLE (`host/hle/hle_media.cpp`) talks
to a `host::Shell` and a `gpu::GeBackend` and to nothing else, and a game adds a backend or a shell in its own
sources: ours are the Metal backend (`src/gpu/`, docs/metal-backend.md) and the Metal shell
(`src/host/metal_shell.mm`). Both seams are vendor patch 0004-ge-backend-and-shell-seams (the GE backend seam of task
021, the shell seam of task 026, the UI platform init of task 027; D-003, D-007), an upstream candidate
(docs/upstream.md). Paths without a prefix are under `vendor/portablekit/`.

This doc was the seams' design (2026-10-06) with what each task landed added after it; it describes them as they are
since task 053 (2026-10-07). The design as first written, the order of work, and what tasks 021, 022 and 026
measured: [docs/history/ge-backend.md](history/ge-backend.md).

## 1. The backend interface

`portablekit::gpu::GeBackend` (`host/gpu/ge_backend.hpp`). The HLE holds one, made by name (section 5), and calls it
for everything the GE does:

| Method | What it must do (from this game's needs) |
|---|---|
| `name()`, `needs_window()` | the registered name; whether it draws with the window shell's device (asked before `initialize`: the Vulkan backend does, null, record and metal do not) |
| `initialize(const BackendConfig&, std::string& error)`, `shutdown()` | device, internal scale, sharp or filtered textures (`BackendConfig`: `vulkan_shell`, the window's `VulkanRenderer` or null; `internal_scale`; `sharp_textures`). `shutdown` **frees every per-target resource before the pools they came from** (task 015) |
| `begin_frame()`, `begin_display_list()` | per-frame and per-list bookkeeping (a target's guest-word snapshot is taken at its first draw of the frame: the framebuffer-texture lookup of section 2 depends on it). `begin_frame()` is called once after `initialize` and after each flip |
| `gpu_decode()`, `check_gpu_decode()` | whether `GeState` hands transformed draws over undecoded (false unless a backend draws raw vertices, as Vulkan can with `<prefix>_GPU_DECODE=1`) |
| `submit(const DrawCall&, const GuestMemory&)` | the whole GE state of one draw: vertex formats (s8/s16/f32 positions, uv, colours, normals, 8 bone weights, morph), through mode, PSP clip z in [-w, w], the alpha test by the GE's numbering (0 NEVER, 1 ALWAYS), the colour test, blend equations with FIX colours and the 2x/ABSDIFF modes, per-channel write masks (PMSKC) and the alpha mask (PMSKA), **stencil ops as alpha writes** with a real stencil attachment and the alpha copy rule, dual-source blending for REPLACE under source-alpha blends, fog, 4 lights, the texture map modes, texture binds with CLUT4/8/16/32, DXT1/3/5 in the PSP block layout, swizzle, mip levels, dithering into 16-bit targets, CLIPENABLE's depth clamp, and **framebuffer-as-texture binds resolved to the target that starts at the address** (section 2). What `DrawCall` carries is the framework's GE state with patch 0002-ge-state-commands; what each backend draws of it: docs/metal-backend.md, "Where it differs from the Vulkan backend on purpose" |
| `block_transfer(const BlockTransfer&, GuestMemory&)` | GE copies between VRAM rectangles: called before the HLE copies the rows (the copy is guest memory, so it stays in the HLE), the backend writing a rendered source back into guest memory first; the HLE then calls `begin_display_list()` |
| `write_back_frame(GuestMemory&)` | the display target's pixels into guest VRAM when the CPU needs them |
| `read_back_framebuffer(address, GuestMemory&)` | one target into guest VRAM (block transfers, movie frames) |
| `write_back_depth(color, depth, stride, GuestMemory&, why)` | the depth target as Z16 into guest VRAM at a SIGNAL (the lens flare reads a 4x4 block around the sun: docs/ge-effects.md); returns whether it wrote |
| `upload_frame(display, pixels, w, h, stride)` | a CPU-drawn picture (movies, `show_cpu_picture_in_vram`) into the display target |
| `present_image(display_address) -> PresentedImage` | the display target at the display address (or the target drawn last when none is there), as an image the shell composites with the UI and presents; the backend never touches the swapchain. `PresentedImage`: `api` (None, Cpu, Vulkan, Metal), `address`, `width`, `height`, `pixels` (Cpu), `image` and `view` (the API's handles as integers), valid until the next call |
| `capture_frame(path)` | the presented image as a BMP for the regression suite and the script's `shot` without a window |
| `draws_submitted()`, `frames_presented()` | the counters the HLE prints |

The frame, as `present_frame` drives it: `upload_frame` (a main-memory framebuffer), the interface,
`write_back_frame`, `present_image(address)`, then the shell's `present` with that image, the optional capture
(`capture_frame`; `frames_presented` and `draws_submitted` for the `[render] frame N (D draws)` line), and
`begin_frame()` for the next frame.

Out of the backend: the window, swapchain, vsync, aspect, fullscreen, UI, pad, scripted input, texture packs, frame
interpolation (it works on presented images and stays in the shell), fast-forward.

## 2. Render-target model every backend must share

- A target is keyed by (guest address, stride, pixel format) and holds a colour image, a depth+stencil image, a
  dirty state and the guest-word snapshot used to tell whether the CPU wrote under it.
- VRAM aliasing is normal here: the depth bytes at 0x04110000 become a 256-stride colour target for the bloom,
  0x04132000 lies inside it, 0x04154000 is a 565 target sampled back as a texture (docs/ge-effects.md). A texture
  bind that lands in a target samples that target's image, exact-address target first.
- Alpha is the PSP's stencil. The stencil attachment is exact; alpha is the copy that sampling, blending, display and
  write-back read; the copy rule (task 011: stale after ops alpha cannot express, resolved before a
  destination-alpha read and at the end of the pass; docs/ge-effects.md) is part of the contract.
- Depth: PSP z in [0, 65535]; the vertex path remaps clip z from [-w, w]. With CLIPENABLE on (every transformed draw
  of this game) the GE clips at the near plane only, clamps each vertex's screen z to 0..65535 and tests MINZ/MAXZ
  per pixel; the Metal backend draws that rule (task 040), the Vulkan backend clips at both planes, and for this
  game the two give the same pixels. `write_back_depth` stores round(z x 65535).

## 3. The backends

| Name | Where | What |
|---|---|---|
| `vulkan` | `host/gpu/vulkan_ge_backend.cpp` (built with the renderer) | `VulkanGeBackend`, a thin adapter over `VulkanRenderer`'s draw path; it needs the Vulkan shell, whose renderer is `BackendConfig::vulkan_shell`. The renderer still begins its frame lazily at the first draw, upload or present and ends it in the shell's present, which also does the frame write-back's copy, frame interpolation and the swapchain, so `begin_frame()` does nothing and `present_image()` only names the target (`VulkanRenderer::display_image`). Every other method forwards to the renderer method the HLE called before the seam |
| `null` | `host/gpu/null_backend.cpp` (system layer: built without Vulkan) | counts draws, block transfers and uploads, presents a black 480x272 Cpu image and writes it for `capture_frame`; prints `[render] null backend: frame N, D draws submitted (K in the last 600 frames, F fps)` every 600 frames and a total at exit. It needs no window or GPU, so with `<prefix>_NO_RENDER` set it runs headless |
| `record` | `host/gpu/record_backend.cpp`, `host/gpu/ge_record_format.hpp` | wraps another backend (`<prefix>_GE_RECORD_INNER`, default vulkan) and writes the calls it sees with the guest memory each read, and each frame's presented image, to a `.gerec` file (section 6) |
| `metal` | ours: `src/gpu/` | the native backend, the default on macOS (D-008): docs/metal-backend.md. MSL compiled at run time (no Xcode), `Depth32Float_Stencil8` targets with the same stencil copy rule, `present_image` returns the target's `MTLTexture` for the Metal shell to draw (or hands a read-back to the Vulkan shell's window). Registered from our sources with a `BackendRegistration` |

The registry (`register_backend`, `make_backend`, `backend_names`, `backend_description`, `BackendRegistration`)
lets any source file add a backend before `main()`.

## 4. Validation

- The `null` backend proves the split: the game runs headless through the seam with no GPU.
- The `record` backend and ge_replay (section 7): a recording replayed into any backend, compared with its recorded
  pictures or backend against backend, the first differing draw found by bisection.
  `tools/gerec/replay_check.sh` checks the replay itself (Vulkan against its recordings, Vulkan against null);
  `tools/gerec/metal_check.sh` checks Metal against Vulkan on the TEAM screen and the race (docs/metal-backend.md,
  "The 3D check", "The race check").
- `tools/frame_regress.sh` against the PPSSPP references, on both paths (docs/verification.md).

The design also planned a `--fuzz` mode over the GE state space, backend against backend; it was not built.

## 5. Selection

`ensure_shell_and_backend()` in `hle_media.cpp` (also behind `ensure_renderer()`, which the setup screens call
first): the backend `<prefix>_GE_BACKEND` names is made first (it is asked `needs_window()`), then the shell
`<prefix>_SHELL` names (`headless` whenever `<prefix>_NO_RENDER` is set, with any value, also empty), then the backend
is initialised with `BackendConfig::vulkan_shell` set when the shell is the Vulkan one. Both default to `vulkan` in
the framework; on macOS our entry point (`src/host/pure_main.cpp`) sets both to `metal` when they are unset (D-008).
An unknown name prints the registered ones and falls back to vulkan; an empty value means vulkan.

| `GE_BACKEND` | `SHELL` `vulkan`, `NO_RENDER` unset | `SHELL` `metal` | `NO_RENDER` set, or `SHELL=headless` |
|---|---|---|---|
| vulkan | Vulkan shell, Vulkan draws | draws nothing (the backend needs the Vulkan shell) | no rendering at all, no draw sink, no shell |
| metal | the Metal backend draws; each picture is read back and shown in the Vulkan window (`PURE_METAL_SHELL=0` turns the hand-over off) | the Metal shell shows the backend's texture: no Vulkan or MoltenVK in the process | headless shell: no window, every draw reaches the backend, which still draws on the GPU |
| null | Vulkan shell; the null backend's black Cpu image uploaded into the display target and shown; scripted input through the virtual gamepad | the black Cpu image | headless shell: no window, no GPU, every draw reaches the backend, the pad from the script |
| record | as its inner backend | as its inner backend | as its inner backend |

When the Vulkan shell cannot be made ("Renderer: unavailable (...); running headless"), a backend that needs no
window runs in the headless shell. The kernel's clock is paced to real time when the shell has a window and unpaced
when it has none (`Kernel::set_paced`, set where the HLE makes the shell: patch 0005-kernel-host-waits-and-pacing);
`PURE_PACED_FROM` (docs/developing.md) overrides that per run.

## 6. The seam in the vendor tree, and the .gerec format

The GE backend seam's files, all under `vendor/portablekit/` (the shell seam's are in section 8):

| File | What |
|---|---|
| `host/gpu/ge_backend.hpp`, `.cpp` | `GeBackend`, `BackendConfig`, `PresentedImage`, the registry, `selected_backend()` (`<prefix>_GE_BACKEND`, vulkan when unset or empty), a BMP encoder (`encode_bmp`, `write_bmp_file`) |
| `host/gpu/vulkan_ge_backend.cpp` | `vulkan`: the adapter over `VulkanRenderer` (renderer sources) |
| `host/gpu/null_backend.cpp` | `null` (system-layer sources: built without Vulkan) |
| `host/gpu/record_backend.cpp`, `ge_record_format.hpp` | `record` and the `.gerec` format (Writer and Reader, for ge_replay) |
| `host/gpu/vulkan_renderer.hpp`, `.cpp` | `display_image(address)`: the target `present()` would show, as a `PresentedImage` |
| `host/hle/hle_media.cpp` | every GE call goes to the backend, every window and pad call to the shell |
| `cmake/PortableKit.cmake` | the new sources |

### record and the .gerec format

`PURE_GE_BACKEND=record PURE_GE_RECORD=<file> PURE_GE_RECORD_AT=N PURE_GE_RECORD_FRAMES=M PURE_GE_RECORD_INNER=<name>`
(defaults: N 1, M 3, the inner backend vulkan, which needs `PURE_SHELL=vulkan` now that the Metal shell is the
default; `metal` records the Metal backend's draws, headless too). Frames are numbered as the inner backend's
`frames_presented()` counts them once shown, the number the `[render] frame N (D draws)` lines carry. Recording
starts at the `begin_frame()` after frame N-1 and each frame ends at the `begin_frame()` after its flip, where the
inner backend's `capture_frame()` gives its image; a `[render] frame N (D draws) recorded: ...` line marks each.

The format, documented at the top of `host/gpu/ge_record_format.hpp`: the 8 bytes `PKGEREC\0`, a u32 version
(`kVersion`, 1), then records of a u8 kind, a u32 payload size and the payload, little endian, structures written
field by field in the order `ge_state.hpp` declares them, without padding (bool one byte, a string a u32 length and
its bytes, a vector a u32 count and its elements). A reader skips kinds it does not know by their size; kinds and a
record's fields only grow at the end. A frame is the records after the FrameEnd before it (or after Begin) up to its
own.

| Kind | Payload |
|---|---|
| Begin (1) | u32 first frame, u32 frames asked for, string inner backend, string environment prefix, u64 frames presented and u64 draws submitted by the inner backend before the first frame |
| Memory (2) | u32 address, u32 size, the bytes: guest memory as the call after it reads it, for each range a call reads (texels of every mip level the draw samples, palettes, a block transfer's source rows) that differs from what the recording last wrote there; the first is the whole of VRAM |
| Words (3) | u32 address, u32 step, u32 count, then count u32: one guest word every `step` bytes of a target's area at its first draw in a frame (what a backend compares to tell whether the CPU wrote under a target it samples) |
| DisplayList (4) | nothing: `begin_display_list()` |
| Draw (5) | a `DrawCall`, below: `submit()` |
| Transfer (6) | a `BlockTransfer`: `block_transfer()`, followed by Memory records of the source rows as the copy reads them, after the backend's read-back; the shell then copies the rows itself |
| ReadBack (7) | u32 address: `read_back_framebuffer()` |
| WriteBackFrame (8) | nothing: `write_back_frame()` |
| WriteBackDepth (9) | u32 colour address, u32 depth address, u32 depth stride, u8 whether it wrote, string why |
| Upload (10) | u32 display address, u32 width, u32 height, then width x height RGBA pixels: `upload_frame()` |
| FrameEnd (11) | u32 frame number, u32 display address asked for, u64 frames presented and u64 draws submitted (the inner backend's cumulative counters), u32 draws and u32 records in this frame, u8 `ImageApi` of the presented image, u32 width, u32 height, u32 size and the image's bytes as `capture_frame()` wrote it (a BMP; size 0 when there was none) |
| End (12) | u32 frames recorded, u64 records in the file before this one |

**The Draw record** (`Writer::put(const DrawCall &)`), in order:

| Part | Fields |
|---|---|
| geometry | u8 primitive; u32 vertex count and each vertex (four f32 position, three f32 normal, two f32 texcoord, u32 colour); u32 index count and each u16 index; u8 through |
| texture | `TextureState` without its mip levels: u8 enabled, u32 address, u32 buffer width, u16 width, u16 height, u8 format, u8 swizzled, u32 CLUT address, format, shift, mask, offset, format word, load bytes and max bytes, u32 function, u8 alpha from texture, u32 min filter, mag filter, wrap s, wrap t, f32 scale u, scale v, offset u, offset v |
| target and state | `RenderTarget` (u32 colour address, stride, format, depth address, depth stride); `BlendState` (u8 enabled, u32 source and destination factors, equation, the two FIX colours); `DepthState` (u8 test, u8 write, u32 function, u16 range near and far, MINZ/MAXZ); `AlphaTestState` (u8 enabled, u32 function, reference, mask); `ViewportState` (six f32 scales and offsets, u32 scissor x1, y1, x2, y2, f32 offset x and y) |
| draw flags | u8 culling, u8 cull clockwise, u8 clear mode, u32 clear flags; u32 vertex type, vertex address, index address, primitive count; u32 material colour, u8 lighting enabled, u8 has vertex colour |
| lighting and fog | `LightingState` (u32 material update, emissive, diffuse, specular, f32 specular power, u32 ambient colour, ambient alpha, mode, u8 reverse normals, then the four `LightState`s: u8 enabled, u32 kind, type, three f32 each of position, direction and attenuation, f32 spot exponent and cutoff, u32 ambient, diffuse, specular); `FogState` (u8 enabled, f32 end, f32 scale, u32 colour); u64 environment version, u64 material version |
| matrices | the world, view, projection and texture matrices, 16 f32 each |
| raw data | u32 raw count, raw stride and byte count, then the raw vertex bytes (none when the draw was decoded); u8 whether bone matrices follow, then 96 f32 |
| stencil and masks | `StencilState` (u8 enabled, u32 function, reference, mask, fail, depth-fail and pass operations); u32 colour write mask, u32 alpha write mask |
| texture map | u32 map mode, projection source, shade light u, shade light v |
| mip levels | `Writer::put_levels` (`kLevelBytes`, 100 bytes): u32 level count, then for levels 1 to 7 u32 address, u32 buffer width, u16 width, u16 height; u32 level mode, s32 level bias, f32 LOD slope |
| colour test, dither, clip | (`kPixelBytes`, 31 bytes) u8 enabled, u32 function, reference, mask; u8 dither enabled and four u32 matrix rows; u8 CLIPENABLE |

The last three parts were added after recordings had been made (tasks 036, 037 and 040), so a Draw may end before
them: the Reader takes one that ends before the texture map as map mode 0, one that ends before the levels as a single
level, and one that ends before the last part as no colour test, no dithering and CLIPENABLE off; `kVersion` stayed 1.
Since task 040 `RecordBackend::submit` also records the texels of every mip level a draw samples (levels 1 to
`level_count` - 1 when the minification filter's bit 2 is on), so a recording made since then replays mipmapped draws
exactly; one made between tasks 037 and 040 replays them only with `PURE_NO_MIPMAPS=1` (docs/metal-backend.md,
"Mipmaps").

`tools/gerec/gerec_dump.py FILE [--summary] [--draws] [--images DIR]` lists the records, parses every Draw in full
and checks it fills its payload, and prints a per-frame table: the Draw records counted in the stream, the count
FrameEnd states, and the change of the inner backend's cumulative counter since the frame before (Begin holds it
before the first frame). It exits 1 when they disagree or the file is cut short.

## 7. ge_replay (task 022, 2026-10-06)

`PureNative --replay FILE.gerec` feeds a recording (section 6) to any registered backend outside the game and compares
what it presents. It is part of the game's executable, because the host layer is compiled into it and into nothing
else: our own `main()` (`src/host/pure_main.cpp`) hands `--replay` to `src/tools/ge_replay.cpp` and everything else
to the framework's main, which `CMakeLists.txt` compiles as `portablekit_main` (`HOST_MAIN_NAME`). Without
`--replay` the game starts as before.

```
build/arm64/bin/PureNative --replay FILE.gerec [--backend NAME] [--out DIR] [--compare] [--tol T] [--max-frac F]
                                              [--frames A[-B]] [--cut N] [--a NAME --b NAME [--first-diff]] [--quiet]
```

| Option | Meaning |
|---|---|
| `--backend NAME` | the backend to replay into, by its registered name (default `null`) |
| `--out DIR` | each replayed frame's capture as `DIR/frame_N.bmp` (`DIR/a/` and `DIR/b/` with `--a`/`--b`); without it, captures go to a temporary file, and only when they are compared |
| `--compare` | each frame against the image its FrameEnd record holds |
| `--tol T`, `--max-frac F` | a pixel differs when any channel differs by more than T (default 0); a frame passes when at most F of its pixels differ (default 0) |
| `--frames A[-B]` | report and compare frames A to B only (A alone: that frame). Earlier frames are still replayed, silently, because they build the memory and targets the later ones use; later frames are not replayed |
| `--a NAME --b NAME` | replay into two backends at once and compare their captures per frame |
| `--cut N` | (task 025) the last frame replayed (B of `--frames`, or the recording's last) only up to and including its Nth draw, counted from 1 as `--first-diff` counts, then flipped and captured; earlier frames whole. With `--out` the pictures stay (`DIR/a/frame_B.bmp` and `DIR/b/frame_B.bmp` with `--a`/`--b`), and with `--a`/`--b` or `--compare` they are compared as a whole frame would be (against the recorded image, which shows the whole frame, a cut frame mostly fails). The frame's line says `cut after draw N (R records)`; an N past its last draw replays it whole. `--first-diff` on a cut frame bisects within its first N draws |
| `--first-diff` | with `--a`/`--b`: bisect the first failing frame to the first draw after which the two pictures differ |
| `--quiet` | only failures and the summary |

Per frame it prints `[replay] frame N: D draws, R records, X ms`, then, when comparing,
`diff F (tol T, P/N px at WxH) PASS|FAIL`. R counts the frame's records without its FrameEnd, the count the FrameEnd
states (`gerec_dump.py`'s table counts the FrameEnd too). X is the time spent in the backend from the frame's first
record through the flip and the capture, one figure per backend with `--a`/`--b`. A summary line ends the run. Exit 0
when every compared frame passed (or nothing was compared), 1 when one failed, 2 for bad arguments, a file that is not
a recording, is cut short or holds a record that does not parse, or a backend that does not exist or cannot be made.

The comparison is `tools/imgdiff.py`'s: both pictures read as RGB (24- and 32-bit BMP, as `tools/png.py` reads them),
resized to 480x272 by nearest neighbour when their sizes differ (a 960x544 Vulkan capture against null's 480x272) and
compared as they are when they agree, with the same tolerance and fraction. The numbers agree: imgdiff.py on the
replayed and recorded race frames gives 0.036493, 0.025461 and 0.001955, as the replay does.

`--first-diff` replays the file from its Begin into two fresh backends for each step, since memory and targets must be
rebuilt: every frame before the failing one whole, then the failing frame's records up to and including its Nth Draw,
then a flip (what `--cut N` does for one N). It searches for the smallest N whose pictures differ, about log2(draws)
replays, and prints each step, then `[replay] first difference in frame F: draw N of D (record R in gerec_dump.py's
listing)` and the draw's state: primitive, vertex and index counts, through mode, vertex type, target and depth
buffer, texture (address, format, size, swizzle, palette, function, filters, wraps), blend, alpha test, stencil, clear
mode with its flags, depth test and write masks. The search assumes that a prefix that differs stays different with
more draws, which holds when a backend gets a draw wrong. When the pictures agree after the frame's last draw, it says
the difference comes from the records after it.

### What the replay guarantees

- **Order.** Records are applied in file order, each as the call the shell made: DisplayList `begin_display_list()`,
  Draw `submit()`, Transfer `block_transfer()`, ReadBack `read_back_framebuffer()`, WriteBackFrame
  `write_back_frame()`, WriteBackDepth `write_back_depth()` with the recorded addresses, stride and reason, Upload
  `upload_frame()` (rows of the recorded width). A Transfer's row copy is made as `hle_media.cpp`'s `block_transfer`
  makes it, after the backend has seen the transfer and after the Memory records that follow it (the source rows as
  the game's copy read them), that is, at the next record of another kind. Unknown kinds are skipped by their size,
  and fields a later format adds at the end of a known record are ignored.
- **The flip.** A FrameEnd is a flip in `present_frame`'s order: `present_image(display address)`, then for a backend
  that needs the window the shell's `VulkanRenderer::present` (where the Vulkan backend's frame ends), then
  `capture_frame()`, `begin_frame()` and the shell's `pump_events()`. `begin_frame()` is also called once after
  `initialize`, as the HLE's `ensure_shell_and_backend` does.
- **Memory.** Each backend gets its own `psprecomp::GuestMemory` of the profile's size (32 MiB), zero at the start.
  Memory records are written into it before the call that reads them: the whole of VRAM first, then texels, palettes
  and transfer sources whenever they changed. What the backend itself writes back (the frame, depth, read-backs before
  transfers) lands there, as it did in the game's memory.
- **Words.** Words records are written into guest memory too, before their draw. So the snapshot a backend takes at a
  target's first draw of the frame, and the comparison the framebuffer-texture lookup (section 2) makes when the
  target is sampled, see the game's words.
- **The shell.** A backend that needs the window (`needs_window()`, the Vulkan one) gets a `VulkanRenderer`
  initialised as the HLE's `ensure_shell_and_backend` initialises the game's, passed as
  `BackendConfig::vulkan_shell`. Its window is titled `... ge_replay (NAME)`, and two Vulkan backends get a window
  each. The replay draws at the recording's internal scale,
  read from the first image's size (it calls the shell's `set_internal_scale` when the settings differ). The other
  settings (sharp textures, texture pack, frame rate, present mode) come from `settings.ini` and the environment, as
  in the game. null and metal need no shell.
- **Determinism.** Two Vulkan replays of the race recording (`--a vulkan --b vulkan`) give identical pictures, which
  are also identical to a single replay of the same file.

### What it cannot replay

- **What the shell did outside the backend**: the interface drawn over the frame (`ui::draw_over_game`), frame
  interpolation's presents between flips, fast-forward, frame pacing, the pad, the window's blit and aspect. Captures,
  recorded and replayed alike, are taken from the target before the window blit, so none of this enters a comparison.
- **Guest memory no call read.** Only what a backend call read is recorded. CPU writes that no draw, transfer or
  upload read are not in the file.
- **GPU-only state from before the first recorded frame**: render targets with their depth and stencil, and anything a
  backend caches. A replay starts with no targets, and a new Vulkan target is undefined until drawn (its attachments
  are loaded, not cleared). A frame that reads pixels an earlier frame drew therefore differs near the start of a
  recording.

The race reads such pixels. Its bloom chain (gerec_dump's draws #868 to #873 of frame 6014) blurs into the two bloom
targets 0x04110000 and 0x04132000 additively beyond the rectangles the frame clears: the clears (#869, #871) cover
240x136, while the blurs draw to x 245 and y 141, and the bilinear samples reach the bottom edge. So the bottom rows of
the bloom carry pixels from frame to frame, and the composite (#873) spreads them over PSP rows 260 to 270. Every
differing pixel of a cold race replay lies in those rows. Recordings that start at different frames decay the same way:

| Frames after the recording starts | 0 | 1 | 2 | 3 | 4 to 8 |
|---|---|---|---|---|---|
| `race.gerec` (starts at 6014): pixels differing at tol 0 | 19058 (0.0365), up to 16 levels | 13297 (0.0255), up to 3 | 1021 (0.0020), up to 1 | | |
| `race_warm.gerec` (starts at 6008): pixels differing at tol 0 | 19160 (0.0367) | 13627 (0.0261) | 1186 (0.0023), up to 1 | 32 (0.00006), up to 1 | 14 to 23, up to 1 |

From the fourth frame on, 14 to 32 pixels of the strip stay one level off: the accumulated rows settle on rounding
fixed points that depend on where they started. So a recording meant to be compared with its own images needs warm-up
frames before the frames that count. `race_warm.gerec` (frames 6008-6016) gives frames 6014-6016 within one level
(`--tol 1` passes; the check uses the brief's `--tol 4 --max-frac 0.001`), while `race.gerec` cannot pass frame 6014
from a cold start at any tolerance below 16. Comparing two backends with each other (`--a`/`--b`) does not need
warm-up, as both start equally empty. The frontend and title recordings, 2D screens without such state, replay exactly
(tol 0) from a cold start.

### The check

`tools/gerec/replay_check.sh` records `out/gerec/race.gerec` (frames 6014-6016), `out/gerec/race_warm.gerec`
(6008-6016), `out/gerec/frontend.gerec` (690-691) and `out/gerec/title.gerec` (1750-1751) when they are missing, each
by one windowed run of its route on an empty stick in the Vulkan shell over the Vulkan backend (named explicitly, as
the default is Metal), and checks each with `gerec_dump.py --summary`. Then it replays `race.gerec` into vulkan with
`--compare` from a cold start (reported, not a pass condition: the table above), `race_warm.gerec` frames 6014-6016
into vulkan at `--tol 4 --max-frac 0.001`, `race.gerec` into null, `race.gerec` into vulkan and null with
`--first-diff --frames 6014` (null draws nothing, so the bisection names draw 1, the clear), and `frontend.gerec` and
`title.gerec` into vulkan at tol 0. About 8 minutes when every recording has to be made, seconds when none has. Its
first run's numbers and the replay's times:
[the history](history/ge-backend.md#ge_replay-the-check-and-its-numbers-task-022-2026-10-06).

## 8. The shell seam (D-007)

The second seam puts the shell behind an interface too, so a Metal backend's `PresentedImage` has a window to show it
and a run without a window has a pad.

### 8.1 The interface

`portablekit::host::Shell` (`host/shell/shell.hpp`): the methods the HLE and the UI layer called on `VulkanRenderer`
outside the GE before the seam, minus what section 1 gives the backend and minus the texture-pack and
internal-scale settings, which are the Vulkan backend's own:

| Group | Methods |
|---|---|
| Lifecycle | `initialize(const ShellConfig &, std::string &error)`, `shutdown()`, `available()`, `name()`, `has_window()` |
| Events and input | `pump_events() -> bool` (false when the window closed), `sample_pad()`, `pad() -> PadState`, `take_mouse_motion()`, `take_touch_motion()`, `take_touch_menu()`, `touch_controls_visible()`, `touch_controls()`, `mouse_captured()`, `quit_requested()`, `request_quit()`, `set_game_input(bool)`, `set_pointer_free(bool)`, `set_scripted_key(int, bool)`, `set_scripted_input(bool)`, `set_event_hook(fn)`, `gamepad() -> SDL_Gamepad *`, `window() -> SDL_Window *` (null without one) |
| Presenting | `present(const PresentedImage &, std::uint32_t display_address, real_time) -> bool`, `present_due()`, `present_until(wake)`, `pause_interpolation()`, `set_fast_forward(bool)`, `hold_frame(bool)`, `capture_window(path)`, `game_aspect()`, `display_refresh()`, `frame_rate_now()`, `set_frame_rate(...)`, `set_frame_rate_auto(bool)`, `set_window_scale`, `set_fullscreen`, `set_present_mode`, `supports_present_mode`, `set_aspect`, `set_sharp_screen`, `set_perf_overlay`, `device_name()` |
| Interface (ImGui) | `initialize_ui(error)`, `shutdown_ui()`, `begin_ui_frame()`, `set_ui_draw_data(ImDrawData *)`, `present_ui(bool show_game)` |

`PadState`, `MouseMotion`, `CameraReading` and the scripted-mouse constant move to `host/shell/shell.hpp` (the
renderer header keeps using them). The registry is the backend's in form: `register_shell`, `make_shell`,
`shell_names`, `shell_description`, `ShellRegistration`, and `selected_shell()` (`<prefix>_SHELL`, vulkan when unset
or empty). Beside the table:

- `present(image, display_address, moment)`: `moment` is the `std::optional<steady_clock::time_point>` the
  renderer's `present` takes; there is no default argument (a virtual function's default would bind statically).
- `ShellConfig` is `{title, capture_frame}`. `title` is empty unless `<prefix>_WINDOW_TITLE` sets it, and the Vulkan
  shell then uses `gpu::default_window_title()`; that function needs the build label header, which only the
  renderer's sources see (the framework's `portablekit_host_check` compiles the system layer without it), so it stayed
  in `vulkan_renderer.cpp` and `gpu::RendererConfig` stayed the renderer's own. `capture_frame` is how a shell
  without a window takes a picture for `capture_window()` (the script's `shot`): the HLE passes the active GE
  backend's `capture_frame`.
- `default_window_title()` and `kFastForwardPresentInterval` stay in `vulkan_renderer.hpp`; `PadState`,
  `MouseMotion`, `CameraReading` and `kScriptedMouse` moved, and `gpu::` names them through `using` declarations, so
  `camera_probe.cpp` and the renderer are unchanged.
- `active_renderer()` (`hle_common.hpp`, unchanged) returns `host::vulkan_renderer(shell)`: the renderer under the
  Vulkan shell, null otherwise. Its users: the Vulkan GE backend's check in `active_backend()`, the camera probe, the
  menu's resolution, texture filter and texture pack rows (left out under another shell) and the texture pack
  screen. `ensure_renderer()` makes the shell and the backend; the setup screens now test `Layer::get().attached()`
  after it, which is the same test under the Vulkan shell and also right for a future windowed shell.
- `Layer::attach` refuses a shell without a window. It loads the fonts, calls `shell.initialize_ui`, then sets the
  gamepad mode: the shell starts ImGui's SDL3 platform backend for its own API (`ImGui_ImplSDL3_InitForVulkan` in
  the Vulkan shell before the renderer's ImGui Vulkan backend, `ImGui_ImplSDL3_InitForMetal` in ours; task 027).
- The kernel's idle and poll hooks (frame interpolation between flips) are set only for a shell with a window, as
  they were only set with the renderer before.

### 8.2 Implementations

The shell seam's files, all under `vendor/portablekit/`, and ours:

| File | Built with | What |
|---|---|---|
| `host/shell/shell.hpp`, `shell.cpp` | system layer | `host::Shell`, `ShellConfig`, `PadState`, `MouseMotion`, `CameraReading`, `kScriptedMouse`, the registry (`register_shell`, `make_shell`, `shell_names`, `shell_description`, `ShellRegistration`), `selected_shell()` (`<prefix>_SHELL`, vulkan when unset or empty) |
| `host/shell/vulkan_shell.hpp`, `vulkan_shell.cpp` | renderer | `vulkan`: owns the `VulkanRenderer` and forwards every call to it; `host::vulkan_renderer(Shell *)` gives the renderer when the shell is this one, else null |
| `host/shell/headless_shell.cpp` | system layer | `headless`: no window, no SDL, no GPU; the pad from the input script |
| `host/shell/sdl_pad.hpp`, `sdl_pad.cpp` | renderer | `host::SdlPad`: the pad sampling, the gamepad attach (open, scan, close, the script's virtual pad taking over) and the scripted keys, moved out of `VulkanRenderer::Impl`, which now derives from it |
| `host/shell/gamepad.hpp`, `gamepad.cpp` | system layer | the gamepad-to-PSP mapping moved out of the renderer (`read_gamepad`, `PadTuning`, `pad_tuning()`), over SDL-free button and axis numbers and SDL's names, so the headless shell maps a script's `pad a` exactly as the SDL shells map the virtual gamepad; `sdl_pad.cpp` checks the numbers against SDL's with `static_assert`s |
| `host/shell/script_steps.hpp`, `script_steps.cpp` | system layer | the input script's grammar moved out of `ui/input_script.cpp` (`Step`, `parse_step`, `name_and_frames`, the live file, `load()` of `<prefix>_INPUT_SCRIPT` and `<prefix>_INPUT_LIVE`), shared by both readers |
| `host/gpu/vulkan_renderer.hpp`, `.cpp` | renderer | moves only: the four types are aliases of the shell's, the pad code is `SdlPad`'s and `gamepad.cpp`'s; `Impl::sample_pad` calls `SdlPad::sample` with the window's pointer, touch controls and frame count |
| `host/hle/hle_media.cpp` | system layer | `media().shell` (before the backend, so the backend is destroyed first), `ensure_shell_and_backend()`, `present_frame` and sceCtrl through the `Shell` |
| `host/ui/*.cpp`, `.hpp` | renderer | the interface on a `Shell`: `Layer::attach(host::Shell &)`, `Layer::shell()`; `input_script.cpp` keeps its SDL path (events at `shell().window()`, the virtual gamepad) over the shared grammar |
| `cmake/PortableKit.cmake` | | the six new sources |

The `metal` shell (task 027) is in our sources, `src/host/metal_shell.mm`, registered with a `ShellRegistration`
(docs/metal-backend.md, "The Metal shell").

- `VulkanShell` owns the `VulkanRenderer` and forwards each call to it. `present()` ignores the image for the
  Vulkan backend (the renderer shows its own target) and, for a `Cpu` image from another backend, uploads it into a
  scratch target and presents that; the Metal backend's pictures reach this window that way, at the cost of a
  read-back a frame.
- `HeadlessShell`: no window, no SDL, no GPU (below).
- `MetalShell` (ours, task 027, `src/host/metal_shell.mm`): an SDL window with a `CAMetalLayer`, the shared SDL pad
  sampler, ImGui's SDL3 and Metal backends (`third_party/imgui_metal/`), the backend's texture drawn into the
  drawable, letterboxed at the PSP's shape, or under Fill (task 086) the whole drawable, the backend's targets then of its shape and `game_aspect()` reporting it (docs/metal-backend.md, "The Metal shell", "Fill").

The SDL pad sampling (the scripted keys, the gamepad attach) is `host/shell/sdl_pad.cpp`, shared by the Vulkan and
Metal shells; `ui/input_script.cpp` keeps pushing SDL events at `shell.window()` for the SDL shells.

### 8.3 The headless shell

`pad()` is built at `present()`, which counts the flips: one script frame per flip, as `ui::draw_over_game()` ticks the
script once per flip in a window, so a route's frame numbers mean the same in both (the frontend route's
`[script] frame N` lines and the movies opened match the windowed run's line for line). Releases run before the
steps due, the live file is read every 10 frames, as in `ui/input_script.cpp`. `pad` holds SDL-named buttons, `axis`
holds an axis at the value SDL's virtual joystick is given (`int16(clamp(v) * 32767)`; a trigger reads 0 until set,
then SDL's full-range-to-trigger mapping), and the pad is `read_gamepad` of those, exactly what `SdlPad::sample`
computes for the virtual gamepad with no key, mouse button or touch held. `<prefix>_TRACE_PAD` prints the same
`[pad] buttons ...` lines. `shot NAME` queues `capture_window(<prefix>_SCREENSHOT_DIR/NAME.bmp)` (`./` without the
variable, as in a window) and the capture is taken by the backend's `capture_frame` within the same `present()`, of
the image just presented; `quit` makes `pump_events()` false and the HLE stops the run ("quit from the input script").
`key`, `mouse`, `click`, `text` and `drop` print `[script] ACTION steps need a window; the headless shell ignores them`
once each. The UI methods do nothing and `initialize_ui` fails with a message; the interface never attaches.

### 8.4 Headless pace

An unpaced run (no window) used to sleep up to 1 ms of real time per clock step while any thread was in a
`WaitType::Host` wait, which `user_main`'s `sceKernelWaitThreadEnd` is for the whole run, so a headless run went at
about 19 frames a second. Patch 0005-kernel-host-waits-and-pacing (Fable, after task 026) gives `wait_host` a
`real_time` flag that only the adhoc network waits set, so the sleep covers waits on the outside world alone, and
`Kernel::set_paced(bool)`, which the HLE sets from the shell (`has_window()`): a headless shell runs unpaced, a
window paced. The headless frontend route reaches frame 2200 in about 1 s.

## History

[docs/history/ge-backend.md](history/ge-backend.md): the design as written on 2026-10-06 (the interface planned, how
Metal would meet it, the validation planned, the order of work), what task 021 landed with its numbers (the null
backend's speed before the headless pace, the race recording), ge_replay's first check (task 022), and the shell
seam's design, landing and numbers (task 026).

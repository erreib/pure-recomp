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
frame against Vulkan and PPSSPP) → 025 Metal stencil/bloom/depth write-back → 026 the shell seam (section 8: `Shell`
interface, Vulkan shell adapter, headless shell with pad from the input script; vendor patch 0010) → 027 Metal
presenter + UI (a `MetalShell` against section 8). 022 and 023 run in parallel after 021; 026 runs in parallel with
them (it touches the vendor only).

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
| vulkan (the framework's default; on macOS our entry point selects metal unless set, D-008) | window, Vulkan draws (as before) | no rendering at all, no draw sink (as before) |
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
  `initialize`, as `ensure_backend` does.
- **Memory.** Each backend gets its own `psprecomp::GuestMemory` of the profile's size (32 MiB), zero at the start.
  Memory records are written into it before the call that reads them: the whole of VRAM first, then texels, palettes
  and transfer sources whenever they changed. What the backend itself writes back (the frame, depth, read-backs before
  transfers) lands there, as it did in the game's memory.
- **Words.** Words records are written into guest memory too, before their draw. So the snapshot a backend takes at a
  target's first draw of the frame, and the comparison patch 0003's lookup makes when the target is sampled, see the
  game's words.
- **The shell.** A backend that needs the window (`needs_window()`, the Vulkan one) gets a `VulkanRenderer`
  initialised as `ensure_backend` initialises the game's, passed as `BackendConfig::vulkan_shell`. Its window is titled
  `... ge_replay (NAME)`, and two Vulkan backends get a window each. The replay draws at the recording's internal scale,
  read from the first image's size (it calls the shell's `set_internal_scale` when the settings differ). The other
  settings (sharp textures, texture pack, frame rate, present mode) come from `settings.ini` and the environment, as
  in the game. null, and later metal, need no shell.
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

### The check and its numbers

`tools/gerec/replay_check.sh` (the Verify of task 022) records `out/gerec/race.gerec` (frames 6014-6016, 23.4 MB),
`out/gerec/race_warm.gerec` (6008-6016, 63.6 MB), `out/gerec/frontend.gerec` (690-691) and `out/gerec/title.gerec`
(1750-1751) when they are missing, each by one windowed run of its route on an empty stick (197, 197, 24 and 59 s),
and checks each with `gerec_dump.py --summary`. Then it replays:

- `race.gerec` into vulkan with `--compare` from a cold start: reported, not a pass condition (the table above);
- `race_warm.gerec` frames 6014-6016 into vulkan at `--tol 4 --max-frac 0.001`: pass, no pixel over the tolerance;
- `race.gerec` into null with `--out out/gerec/null`: three black 480x272 frames, exit 0;
- `race.gerec` into vulkan and null with `--first-diff --frames 6014`: the frame fails, as null draws nothing, and the
  bisection names draw 1 of 906, the full-screen clear sprite that clears the back buffer 0x04088000 to white, in 10
  steps of about 50 ms each;
- `frontend.gerec` and `title.gerec` into vulkan at tol 0: pass.

It takes 8 minutes when every recording has to be made, and a few seconds when none has.

Time a frame in the Verify run (Apple M4 Pro). The first frame of a Vulkan replay also makes its targets and
pipelines:

| Recording | Backend | First frame | Later frames |
|---|---|---|---|
| race (906 draws a frame) | vulkan | 47 ms | 5.5 to 13 ms |
| race | null | 2.2 ms | 0.6 to 1.1 ms |
| frontend (11 draws) | vulkan | 27 ms | 5.1 ms |
| title (28 draws) | vulkan | 26 ms | 5.0 ms |

## 8. The shell seam (D-007, 2026-10-06)

Section 6 left the shell fused in `VulkanRenderer`: window, SDL events, pad sampling, scripted input, ImGui, frame
pacing and interpolation, the swapchain. A Metal backend's `PresentedImage` has nothing to show it, and a run without
a window has no pad (docs/status.md Blockers, "Headless input"). The second seam puts the shell behind an interface
too, so the HLE talks to a `Shell` and a `GeBackend` and nothing else.

### 8.1 The interface

`portablekit::host::Shell` (vendor patch 0010, `host/shell/shell.hpp`), the methods the HLE and the UI layer call
today on `VulkanRenderer` outside the GE (the list in `vulkan_renderer.hpp`, minus what section 1 moved to the
backend and minus the texture-pack and internal-scale settings, which are the Vulkan backend's own):

| Group | Methods |
|---|---|
| Lifecycle | `initialize(const ShellConfig &, std::string &error)`, `shutdown()`, `available()`, `name()`, `has_window()` |
| Events and input | `pump_events() -> bool` (false when the window closed), `sample_pad()`, `pad() -> PadState`, `take_mouse_motion()`, `take_touch_motion()`, `take_touch_menu()`, `touch_controls_visible()`, `touch_controls()`, `mouse_captured()`, `quit_requested()`, `request_quit()`, `set_game_input(bool)`, `set_pointer_free(bool)`, `set_scripted_key(int, bool)`, `set_scripted_input(bool)`, `set_event_hook(fn)`, `gamepad() -> SDL_Gamepad *`, `window() -> SDL_Window *` (null without one) |
| Presenting | `present(const PresentedImage &, std::uint32_t display_address, real_time) -> bool`, `present_due()`, `present_until(wake)`, `pause_interpolation()`, `set_fast_forward(bool)`, `hold_frame(bool)`, `capture_window(path)`, `game_aspect()`, `display_refresh()`, `frame_rate_now()`, `set_frame_rate(...)`, `set_frame_rate_auto(bool)`, `set_window_scale`, `set_fullscreen`, `set_present_mode`, `supports_present_mode`, `set_aspect`, `set_sharp_screen`, `set_perf_overlay`, `device_name()` |
| Interface (ImGui) | `initialize_ui(error)`, `shutdown_ui()`, `begin_ui_frame()`, `set_ui_draw_data(ImDrawData *)`, `present_ui(bool show_game)` |

`PadState`, `MouseMotion`, `CameraReading` and the scripted-mouse constant move to `host/shell/shell.hpp` (the
renderer header keeps using them). `ShellConfig` is today's `RendererConfig` (the title).

### 8.2 Implementations

- `VulkanShell` (vendor, patch 0010): an adapter over `VulkanRenderer`, as `VulkanGeBackend` is for the GE side. The
  `vulkan` GE backend needs this shell (`BackendConfig::vulkan_shell` is its renderer). `present()` ignores the image
  argument for the Vulkan backend (the renderer shows its own target, as today) and, for a `Cpu` image from another
  backend, uploads and shows it (`upload_frame` into a scratch target, then the usual present): that is how a Metal
  backend's picture reaches a window before task 027, at the cost of a read-back a frame.
- `HeadlessShell` (vendor, patch 0010): no window, no GPU. `pad()` comes from the input script
  (`<prefix>_INPUT_SCRIPT`, the same file format) read at pad level: `pad NAME [FRAMES]` and `axis NAME VALUE`
  set `PadState` by frame (the names `ui/input_script.cpp` accepts; `shot NAME` asks the GE backend for
  `capture_frame` into `<prefix>_SCREENSHOT_DIR`; `quit` ends the run; mouse, key and text events are not supported
  and are reported once). `pump_events()` is true until `quit`. `present()` counts frames. The live file
  (`<prefix>_INPUT_LIVE`, the sweep's steering channel) is read the same way. This gives every route a headless run.
- `MetalShell` (ours, task 027, `src/host/metal_shell.mm`): an SDL window with a `CAMetalLayer`
  (`SDL_Metal_CreateView`), the shared SDL pad sampler, ImGui's SDL3 + Metal backends (`imgui_impl_metal.mm` is not
  vendored; task 027 adds it under third_party or our sources), presents a `Metal` image by blitting the backend's
  texture to the drawable, with letterboxing by `game_aspect()`.

The SDL pad sampling (`VulkanRenderer::sample_pad`, the scripted keys, the gamepad attach) is extracted into
`host/shell/sdl_pad.cpp` so `VulkanShell` and `MetalShell` share it; `ui/input_script.cpp` keeps pushing SDL events
at `shell.window()` for the SDL shells.

### 8.3 Selection and the HLE

`<prefix>_SHELL=vulkan|headless|metal` (default vulkan). `<prefix>_NO_RENDER` keeps its meaning: the headless shell
with the backend `<prefix>_GE_BACKEND` names when that backend needs no window, and no rendering at all otherwise
(the default `vulkan` backend cannot run headless), exactly today's table in section 6. `ensure_backend` becomes
`ensure_shell_and_backend`: the shell first, then the backend with `BackendConfig::vulkan_shell` set when the shell is
the Vulkan one. `media().renderer` becomes `media().shell`; `active_renderer()` stays for the UI screens that need
Vulkan itself (texture packs, device name) and returns the renderer only when the shell is the Vulkan one.

### 8.4 Headless pace (solved by patch 0011, 2026-10-06)

Without a window `Kernel::pace_to_real_time` was off, but `Kernel::advance_clock` slept up to 1 ms of real time per
clock step while any thread was in a `WaitType::Host` wait, which `user_main`'s `sceKernelWaitThreadEnd` is for the
whole run: about 19 frames a second (section 6). Patch 0011 (Fable) gives `wait_host` a `real_time` flag that only
the adhoc network waits set, so the sleep covers waits on the outside world alone, and adds `Kernel::set_paced(bool)`,
which the HLE sets from the shell (`has_window()`): a headless shell runs unpaced whatever `<prefix>_NO_RENDER` says.
Measured: the null backend to frame 2000 in 0.5 s (was 106 s); the headless frontend route (`PURE_SHELL=headless
PURE_GE_BACKEND=null`, no `NO_RENDER`) to frame 2200 in 1.1 s (was 115 s), the same 20643 draws, the same movies
opened, the four `shot` captures written. Windowed runs are paced before the sleep is reached and are unchanged
(`lang` 0.0544).

### 8.5 What landed (task 026, 2026-10-06)

Patch 0010 (`patches/0010-shell-seam.patch`) adds the seam to the vendored framework. Files, all under
`vendor/portablekit/`:

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

The `metal` shell (task 027) is in our sources, `src/host/metal_shell.mm`, registered with a `ShellRegistration` (docs/metal-backend.md, "The Metal shell"); patch 0012 moved ImGui's SDL3 platform init from `Layer::attach` into `Shell::initialize_ui` for it.

#### The interface as landed

As in 8.1, with these differences:

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
- `Layer::attach` refuses a shell without a window; ImGui's SDL3 platform backend is still initialised with
  `ImGui_ImplSDL3_InitForVulkan` (task 027 picks the Metal one).
- The kernel's idle and poll hooks (frame interpolation between flips) are set only for a shell with a window, as
  they were only set with the renderer before.

#### Selection

`ensure_shell_and_backend()` (also behind `ensure_renderer()`): the backend is made first (it is asked
`needs_window()`), then the shell `<prefix>_SHELL` names (`headless` whenever `<prefix>_NO_RENDER` is set), then the
backend is initialised with `BackendConfig::vulkan_shell` set when the shell is the Vulkan one.

| `GE_BACKEND` | `SHELL` unset or `vulkan`, `NO_RENDER` unset | `NO_RENDER` set (any value, also empty), or `SHELL=headless` |
|---|---|---|
| vulkan (the framework's default; on macOS our entry point selects metal unless set, D-008) | Vulkan shell, Vulkan draws (as before) | no rendering at all, no draw sink, no shell (as before) |
| null | Vulkan shell; the null backend's black Cpu image is uploaded into the display target and shown; scripted input through the virtual gamepad | headless shell: no window, no GPU, every draw reaches the backend, the pad from the script |
| record | as its inner backend | as its inner backend |

An unknown `SHELL` prints the registered names and falls back to vulkan. When the Vulkan shell cannot be made
("Renderer: unavailable (...); running headless"), a backend that needs no window runs in the headless shell. The
pacing is unchanged: `Kernel::pace_to_real_time` still keys on `<prefix>_NO_RENDER` only, so `SHELL=headless` without
`NO_RENDER` is paced to real time.

#### The headless shell

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

#### Numbers

Frame regression suite (`tools/frame_regress.sh`), before on c394d8b (patches 0001-0009) and after on the patched
tree, both 7m 8s:

| Scene | Before | After | Captures, before vs after (`imgdiff.py --tol 0`) |
|---|---|---|---|
| lang | 0.0544 | 0.0544 | identical (0 of 522240 px) |
| title | 0.0302 | 0.0302 | identical |
| profile | 0.0543 | 0.0543 | identical |
| main_menu | 0.0331 | 0.0331 | identical |
| race_hud | 0.0672 | 0.0672 | identical |

The headless frontend route (`PURE_SHELL=headless PURE_GE_BACKEND=null`, `--script config/pad_scripts/frontend.txt
--frames 2200 --env PURE_NO_RENDER=`): 2200 frames, 20586 draws submitted, in 114.6 s (19.0 frames a second, the
kernel's headless pace of section 8.4; the seam adds nothing measurable). The script's presses take effect: Cross at
700, 1600 and 1650 (`[pad] buttons 0x4000` with `PURE_TRACE_PAD`), Start at 1800 (`0x8`), and the game opens
`Movies/WoFMVNew_US.PMF` after the second and `Movies/Profile_part1.PMF` after Start, as the windowed run does (a
run with a neutral pad stays on Language Selection from frame 690, task 021). With `--shots`, `lang`, `notice`, `title` and `profile` are written
(black 480x272, from null) at the script's frames. Other paths checked with short runs: null in the Vulkan window
(the uploaded black image is what the `shot` captures), `PURE_SHELL=bogus` (falls back to vulkan with the message),
`PURE_SHELL=headless` with the Vulkan backend (nothing drawn, with the message), `PURE_NO_RENDER=1` with the Vulkan
backend ("Renderer: disabled", as before), and the live file headless (lines appended during the run are read every
10 frames; `pad start`, `shot`, `key` reported as ignored, `quit` stops the run).

The patch is 3030 lines (1576 added, 608 removed); `vulkan_renderer.cpp` only loses code (the pad mapping, the
gamepad attach and the sampler, about 260 lines) and gains the base class and one call.

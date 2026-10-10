# GE effects on a race frame: bloom chain, stencil and lens flare

What Wipeout Pure's GE does in one race frame, with every change of render target and every texture bind that reads
VRAM the game rendered, taken from the PPSSPP GE dump (ground truth, task 008, 2026-10-05) and checked against the
port's own traces; then the rules the port draws them by: the framework's Vulkan renderer (patch
0003-vulkan-renderer-fixes, tasks 009 to 019) and the Metal backend, which follows the same rules
(docs/metal-backend.md, "The stencil and the alpha", "The bloom chain", "Guest memory"). How each rule was found,
what the renderer did before it and what each fix measured: [docs/history/ge-effects.md](history/ge-effects.md).

## Sources

| Source | Frame | How it was read |
|---|---|---|
| `ref/vineta_k_start.ppdmp` (task 006, PPSSPP 1.20.4, software renderer) | 7155, Vineta K grid, HUD in, before READY | `tools/ppsspp/ppdmp.py` (new, stdlib + the `zstd` CLI). 7124 dump commands, 871 draws, 2 DISPLAY records |
| Our port, `out/008/runA.log` | race on the same grid, frames 5707-6500 | route `~/dev/pure-recomp/out/race/route.txt` (presses only) with shots at 6000/6200/6400/6490, `--frames 6500`, `PURE_TRACE_FB_TEXTURES=1 PSPRECOMP_TRACE_VRAM_READS=1 PURE_FRAME_LOG=1 PSPRECOMP_HLE_HISTOGRAM=1` and `PURE_TRACE_CALLS` on the five sceGe list/sync imports |
| Our port, `out/008/runB.log` | 6483-6486 | same, plus `PURE_TRACE_GE_LIST=519241:1160`; frames 6484 and 6485 are complete and were replayed with `ppdmp.py gelist` (863 draws in 6485) |

The dump format (PPSSPP `GPU/Debugger/Record.cpp`, `RecordFormat.h`, `Playback.cpp`, read, not copied) parsed without
trouble, so the escalation fallback (the GE debugger window by hand) was not needed. `ppdmp.py` prints one line per
draw: target, scissor, primitive and vertex bounds, texture (address, format, size, bufw, swizzle, the dump's VRAM
flags), which earlier colour or depth target the texture's bytes overlap, texture function, blend, depth and alpha
test, write masks. `ppdmp.py tex` writes the VRAM bytes a draw sampled, as the dump holds them, to a PNG.

Draw numbers below are the dump's (0-870). Our port's frame 6485 has the same structure; its in-frame numbers are
given in brackets where they differ.

Run-to-run note: our port is not deterministic in GE list runs. Run A put frame 6449 at list run 519627; in run B
run 519241 fell at frame 6483 (the dump window was aimed by the run A count). A list-run index is not a stable
frame address; use `PURE_FRAME_LOG` lines to find frames in a `PURE_TRACE_GE_LIST` dump.

## VRAM layout during the race

| Range | Use |
|---|---|
| 0x04000000-0x04087FFF | display buffer A, RGBA8888, stride 512 (480x272 used) |
| 0x04088000-0x0410FFFF | display buffer B, RGBA8888, stride 512. The frame in the dump draws here |
| 0x04110000-0x04153FFF | depth buffer of both display buffers, 16 bit, stride 512, 272 rows (0x44000 bytes). After the scene the same bytes become two RGBA8888 bloom buffers of stride 256: 0x04110000 (256x136) and 0x04132000 (= 0x04110000 + 256 x 136 x 4) |
| 0x04154000-0x0415BFFF | billboard render target, RGB565, stride 128, 128x128 |
| 0x0415C000-0x04163FFF | its depth buffer, stride 128 |
| 0x04179640-0x041FFFFF | textures the game keeps in VRAM (CLUT4/CLUT8, swizzled) and their palettes (128 CLUTs, 0x04179640-0x041FF780) |

The depth address register (0x9E/0x9F) stays 0x04110000 / 512 for the whole frame, bloom included; the bloom passes
draw with the depth test off and no depth writes, so colour and depth alias the same bytes without conflict.

## The frame, in order (PPSSPP dump)

1. Clear. Target 0x04088000 8888 stride 512, depth 0x04110000 stride 512. Draw 0: CLEARMODE colour + alpha + depth,
   a through-mode sprite 0,0-480,272, colour 0x04FFFFFF (alpha, which is the stencil, cleared to 4).
2. Billboards, four render-to-texture rounds. Target 0x04154000 565 stride 128, depth 0x0415C000 stride 128, scissor
   128x128. Each round clears (draws 1, 27, 46, 70), draws a small 3D scene (21, 14, 19 and 6 draws), switches back to
   0x04088000 and draws a billboard frame whose last draw (26, 45, 69, 82) binds texture 0x04154000, 565, 128x128,
   bufw 128, linear, bilinear, transform mode, v scale -1 (flipped: the wrap is REPEAT, and the GE's REPEAT takes -v
   modulo 1, so the strip reads the target's rows from the far end; both backends since task 063). That texture is the
   colour target the round just drew (dump VRAM flags 5: a target, drawn to). Opaque, depth test GREATER with writes.
   [Ours: rounds of 37, 12, 7 and 6 draws after the clear at that moment; same addresses and formats.]
3. Opaque world into 0x04088000 (draws 77-602, the fourth billboard at 82 among them) with depth writes, ending with
   the five sky-cube faces (598-602, RAM CLUT8 256x256 textures). Materials write the bloom mask through the
   stencil, which on the PSP is the 8888 alpha channel: STENCILTEST ALWAYS with ref 0x04 for most materials, 0xFF for
   light strips (also 0x80, 0x78, 0x3A, 0x00 on a few), STENCILOP zpass REPLACE. At draw 833 the back buffer's
   visible 480x272 has alpha 4 on 99.0% of pixels, 255 on 0.4% (the lights), 0 on 0.6%.
4. GE SIGNAL 0x0E020200 + END (behaviour 2, signal id 0x0200), right after the last sky face. The dump does not
   record SIGNAL; our trace shows it once per frame (at list address 0x08B7EB58 in the four dumped frames,
   0x08B7EB38 or 0x08B7EC58 in others), after the sky [our 592] and before the first translucent draw [our 593]. The CPU reads the depth buffer in the signal handler: the lens-flare
   test (section below). No sceGeListSync or sceGeDrawSync comes before the read; the SIGNAL is the synchronisation.
5. Translucent world (603-831): ship trails (additive FIX, depth test, no write), engine glows, engine flares
   (texture 0x08CFF310 CLUT8 128x64, `grabbedEngineFlare128x64x8.mip`), and so on.
6. Lens flare, draw 832 [our 820]: one triangle strip of 60 vertices = 10 quads joined by degenerate triangles, each
   a quarter of the 64x64 CLUT8 atlas 0x0968A2B0 [ours 0x0968A4B0], vertex colour 0xB5B5B5 with alpha 0x3F-0x79, blend
   add(SA, FIXB 0xFFFFFF), depth test off, alpha writes masked. The per-element alpha carries the visibility the CPU
   worked out in step 4.
7. Bloom, draws 833-838 [our 821-826], in detail below. Result lands in 0x04088000.
8. HUD, draws 839-866: sprites (prim 6, transform mode, screen-space coordinates) from CLUT4 atlases in RAM,
   add(SA, 1-SA), depth test off, alpha writes masked. Then four transformed triangle strips with depth test off and
   alpha blending (867-870); not part of the bloom.
9. DISPLAY 0x04088000, stride 512, format 3 (sceDisplaySetFrameBuf). The next frame draws into 0x04000000 and its
   downsample reads 0x04000000; nothing else changes.

The frame has no block transfer and no CPU copy into VRAM (no TRANSFERSRC, MEMSET or MEMCPY records). The only VRAM
texture binds the dump flags as targets (flags 5) are 0x04088000, 0x04110000, 0x04132000 and 0x04154000; the other
190 distinct VRAM binds are resident textures at 0x04179680 or above, and all 128 VRAM CLUTs lie in
0x04179640-0x041FF780 (flags 0 or 2: never a target).

### The bloom chain (draws 833-838)

All six draws are through-mode sprites (prim 6) with depth test off and no depth writes, scissor 0,0-479,271,
texture filter 0x107 (bilinear), wrap 0x101 (clamp both), texture function modulate RGBA.

| # | Target (addr, fmt, stride) | What it draws | Texture bind (addr, fmt, size, bufw, swizzle) and what it aliases | Blend |
|---|---|---|---|---|
| 833 | 0x04110000, 8888, 256 | downsample: 8 sprites of 32x136, xy (0.25,0.25)-(256,135.75), uv (0.5,0.5)-(512,271.5), 2:1 each way, no vertex colour (material 0xFFFFFF/0xFF) | 0x04088000, 8888, 512x512, 512, linear: the back buffer drawn by 0-832. Columns 240-255 sample x 480-511, the unused strip of the 512 stride | add(SA, FIXB 0x000000): scene x its own alpha, the stencil mask of step 3 |
| 834 | 0x04132000, 8888, 256 | one black sprite 0,0-240,136 (colour 0x00000000, not a clear-mode draw) | none | opaque |
| 835 | 0x04132000, 8888, 256 | horizontal blur: 60 tiles of 16x34 times 11 taps at x offsets -5..+5 (660 sprites, 1320 s16 vertices), uv 0..240 x 0..136. Tap weights in the vertex colour: 0x14 0x1E 0x28 0x32 0x40 0x40 0x40 0x32 0x28 0x1E 0x14 (sum 472/255 = 1.85) | 0x04110000, 8888, 256x256, 256, linear: the 833 result; its bytes are also the first half of the depth buffer | add(FIXA 0xFFFFFF, FIXB 0xFFFFFF) = ONE + ONE |
| 836 | 0x04110000, 8888, 256 | one black sprite 0,0-240,136 | none | opaque |
| 837 | 0x04110000, 8888, 256 | vertical blur: the same 660 sprites with y offsets -5..+5 (dest y -5..141), uv 0..240 x 0..136, same weights | 0x04132000, 8888, 256x256, 256, linear: the 835 result. The same bytes are byte offset 0x22000 = row 136 of the 0x04110000 buffer, and the second half of the depth buffer | ONE + ONE |
| 838 | 0x04088000, 8888, 512 | composite: 4 sprites, 128 wide and 270 tall, covering xy (1,1)-(512,271) (the scissor stops them at 479), uv (0.5,0.5)-(256,135.5), 1:2 each way, shifted one pixel right and down | 0x04110000, 8888, 256x256, 256, linear: the 837 result | add(FIXA 0xAFAFAF, FIXB 0xFFFFFF) = dest + 0.686 x bloom; MASKALPHA 0xFF keeps the back buffer's alpha |

So the bloom is: (scene x stencil mask) at half size, an 11-tap box-ish blur in x then in y with a gain of 1.85 per
pass, added back at 0.686. On the PSP the 837 sprites that overshoot to y 136-141 write the first rows of the
0x04132000 buffer; the next frame's 834 clears them.

The textures as the dump holds them (`ppdmp.py tex`, out/008/tex83x_*.png): at 833 the 512x512 view of 0x04088000
shows the scene in rows 0-271 and, in rows 272-407, the depth buffer read as 8888 (two 16-bit depths per pixel, high
bytes in G and A): far geometry has small depths, so G is near 0 and the area looks magenta; the sky is 23-24. At 835 the
top 136 rows of 0x04110000 hold the downsample (dark, with the light strips); at 838 they hold the blurred bloom.

### How the renderer resolves the bloom's binds

A texture bind whose address lies in a render target with the same row length and pixel size, while guest memory
under it still holds the words the target had at its first draw of the frame, samples that target: the target that
starts at the texture's address first, else the one drawn last (patch 0003-vulkan-renderer-fixes, task 009). The
four bloom binds then read what the PSP reads: 833 the back buffer, 835 the downsample in 0x04110000, 837 the
horizontal blur in 0x04132000 (which lies inside 0x04110000's memory, row 136: the target starting there wins), 838
the vertical blur in 0x04110000. Before task 009 the most recently drawn containing target won, so 837 sampled rows
136 to 271 of 0x04110000, which nothing draws, and the race was magenta:
[the diagnosis](history/ge-effects.md#diagnosis-what-the-vulkan-renderer-samples-for-each-bloom-bind).

## The stencil and the alpha

The stencil state of the dump's frame (every draw, `0x24`/`0xDC`/`0xDD`/`0xE8`/`0xE9`):

| Draws | Stencil | Write masks | What they are |
|---|---|---|---|
| 0 | clear mode, alpha 0x04 | | the clear sets the mask to 4 |
| 77-602 (most) | ALWAYS, ref 0x04 (0xFF lights; 0x78, 0x3A on two draws), ops KEEP/KEEP/REPLACE | none, or alpha 0xFF on FIX-blended passes | opaque world and sky; several are z-equal decal passes blended add(FIXA ffffff, SA) |
| 83-92 | off | | track base pass, opaque, no depth write |
| 93-102 | ALWAYS, ref 0x80, REPLACE | | the same strips again, add(SA, 1-SA) |
| 103-112 | ALWAYS, ref 0xFF, REPLACE | colour 0xFFFFFF | stencil-only pass: the light strips' mask from texture alpha (alpha test > 0x80) |
| 339-356 | ALWAYS, mask 0, ops KEEP/INCR/KEEP and KEEP/DECR/KEEP | colour 0xFFFFFF | shadow volumes (depth-fail) |
| 357 | **GREATER** ref 0x04, ops REPLACE/REPLACE/REPLACE | | full-screen shadow darkening, add(FIXA 606060, FIXB 9f9f9f), depth test off |
| 603-831 | off, or ALWAYS ref 0x00 REPLACE (621-629 and every 27th run), ref 0xFF on 820 and 828 | | translucent world; 820/828 are add(SA, FIXB) with alpha test > 0 |
| 832-870 | off | alpha 0xFF on 832, 838, 839-866 | lens flare, bloom chain, HUD |

So the bloom mask is written with STENCILTEST ALWAYS throughout; the one other function is the shadow quad 357.

On the PSP the stencil is the alpha channel of a 5551, 4444 or 8888 target, and a draw stores its stencil result
there, never its fragment alpha. The renderer keeps a real stencil attachment and the alpha as its copy (task 011;
task 009 had the alpha alone, which `PURE_NO_STENCIL_BUFFER=1` gives back: then every stencil test is drawn as
ALWAYS and only a zpass REPLACE or ZERO reaches the alpha, so the ship shadows are missing).

The attachment: the depth image is D32_SFLOAT_S8_UINT (format 130; on the M4 Pro under MoltenVK, which also reports
`dualSrcBlend`), or D24_UNORM_S8_UINT; the render pass loads and stores the stencil, and the clear-load variant that
skips loading colour skips it too, because a full clear of colour and alpha clears the stencil. Every draw with the
stencil test on and a 5551/4444/8888 target puts the GE's state in the pipeline: the test function (0xDC; the GE
compares reference OP stencil under the mask as Vulkan does), the sfail, zfail and zpass ops (0xDD; INCR and DECR
clamp), the reference as the target's alpha holds it, the compare mask, and the write mask (~0xE9). A clear-mode draw
that clears the alpha writes the stencil with ALWAYS/REPLACE of the clear colour's alpha. A draw whose stencil test
fails is discarded, as on the PSP; stencil off writes nothing to either.

The copy rule. The stencil is always exact; the alpha is what textures, the display, write-back and destination-alpha
blends read. A draw leaves the alpha behind the stencil (`alpha_follows_stencil`) when the colour path cannot express
its stencil effect: an sfail op other than KEEP under a test that can fail, a zfail op other than KEEP under a depth
test that can fail, INVERT/INCR/DECR on pass, a write mask that keeps some bits, or REPLACE under a source-alpha blend
without dual-source blending. The renderer then marks the alpha stale and copies the stencil into it before the next
draw in the pass whose colour blend reads DA or 1-DA, and when the pass ends (anything that samples, shows or writes
back the target ends the pass first). The copy (`resolve_stencil_alpha`) stays inside the pass and never samples the
stencil: a quad over the target writes alpha 0, then one quad per bit b passes a stencil test EQUAL with compare mask
and reference 1<<b and adds (1<<b)/255 to the alpha (blend ONE+ONE, alpha written alone, stencil write mask 0); sums
of k/255 are exact in an 8-bit target. Its six vertices live in a fixed slot at the end of each frame's vertex region,
because a draw's vertices are already in the buffer, past `vertex_offset`, when its pass is ended or the copy is
needed. Measured with `PURE_TRACE_STENCIL_COPY=1` over the race route: one copy per race frame (338 copies for the 338
frames 5707-6044, alternating between the back buffers 0x04000000 and 0x04088000), always at the end of the pass and
never before a destination-alpha read, and none in the frontend.

Dual-source blending. When the colour blend reads SA or 1-SA and the draw stores a non-zero stencil value, the shader
stores the value as alpha and hands its own alpha to the blend as a second output (SRC1_ALPHA, `kAlphaDual`), so the
track strips 93-102 (REPLACE 0x80 under add(SA, 1-SA)) and the engine glows 820/828 store their reference exactly.
Pipelines that do not use it take a copy of the SPIR-V whose second output is moved to location 1, where no
attachment takes it. ZERO keeps the exact (ZERO, ZERO) alpha factors of task 009.

## The alpha test's numbering

The GE numbers the alpha-test functions as it numbers the depth test's: 0 NEVER, 1 ALWAYS, 2 EQUAL, 3 NOTEQUAL, 4
LESS, 5 LEQUAL, 6 GREATER, 7 GEQUAL. The race frame enables the alpha test with ALWAYS (reference 0) on 268 of its
871 draws, the last opaque writer of 87% of its pixels (the track, barriers, stadium arches, pillars, the sky cube),
so a backend that reads 1 as NEVER loses them. The renderer tests by the GE numbering, pushes ALWAYS for draws
without the test and for clears, and compiles the discard out for ALWAYS (patch 0003-vulkan-renderer-fixes, task
010); the Metal backend does the same. How it was found:
[The environment draws and the alpha test](history/ge-effects.md#the-environment-draws-and-the-alpha-test-task-010-2026-10-05).

## The depth write-back for the lens flare

### What the handler reads

A throwaway trace (not committed: a line for every guest load whose address, in any VRAM mirror, falls in the depth
buffer's bytes, with the value loaded, plus a line per GE signal from the HLE signal sink) on the race route to frame
6030, and on a run driven along the first straight to frame 7500 (task 019, in the history), gives:

- The signal: SIGNAL `0x0E020200` + END (for example at list address 0x08B7EAD8 in frame 6010), behaviour 2, signal
  id 0x0200, on the list's callback (the one sceGeSetCallback registered at 0x088ED1D4, signal function 0x088ECCAC).
  One per race frame from the race's first frame (313 in frames 5707-6019), none in the frontend; the only other
  interrupts are the FINISH callbacks (id 0). Every load of those bytes in the run (874 to frame 6020) comes after a
  0x0200 signal line and before the next signal, so they are the handler's.
- From frame 5966, when the fly-by ends, every frame: 16 halfword loads through the 0x04600000 mirror at
  0x04722902 + 0x800 i + 4 j (i, j = 0..3) on the grid, depth bytes 0x04122902 onward, so with 1024-byte rows
  (stride 512) rows 74, 76, 78, 80 and columns 129, 131, 133, 135: the 4x4 every-other-pixel block around the sun.
  The block moves with the sun: (3, 45) at frame 5966, (129, 74) on the grid, (142, 81) at 6566, (199, 88) at 7016
  and (323, 86) at 7466 in the driven run.
- From the HUD's fade-in (frame 6010 or 6011) nearly every frame (1490 of the driven run's 1534 frames that read),
  one more halfword first, at 0x047321E0: depth byte offset 0x221E0, row 136 column 240, the screen centre.

Task 008's `[vram]` lines for 0x04120000-0x0413FFFF were these loads: the trace names a block by the address masked to
2 MB, so the 0x046 mirror did not show. The framework maps every VRAM mirror onto the same bytes, so a depth buffer
stored linearly at 0x04110000 (row y at 0x04110000 + 1024 y) is what those loads see. That is also how PPSSPP's dump
holds it, and the values agree (below).

| Read | PPSSPP frame 7155 (VRAM at draw 833) | Ours, write-back off | Ours, write-back on (frames 6010, 6011) |
|---|---|---|---|
| sun block, 16 samples | 23 each (the sky cube) | 0 | 24 each |
| centre (240, 136) | 1168 | 0 | 1168 |
| whole buffer | 23-13344, no zero | 0 | 23-13444 |

### What the renderer does

At a SIGNAL with behaviour 1-3 whose callback has a signal function, the HLE signal sink (`hle_media.cpp`) calls
the GE backend's `write_back_depth` (the Vulkan backend forwards it to `VulkanRenderer::write_back_depth`; the Metal
backend's is docs/metal-backend.md, "Guest memory") with the GE's current colour target and depth registers (0x9E/0x9F) before it
queues the interrupt; the handler runs when the HLE call that executed the list returns, so it reads the depth of
everything drawn before the SIGNAL (the opaque world and the sky cube). FINISH and list-flow signals (0x10-0x12) do
nothing. `write_back_depth` ends the render pass, copies the depth aspect of the target's depth image
(D32_SFLOAT_S8_UINT, 960x544 at the default 2x) into a mapped host-cached buffer, submits what the frame has recorded
so far and waits for it (the same sequence `read_back_framebuffer` uses for block transfers), then stores
z = round(d x 65535) from the texel at the centre of each PSP pixel as 480x272 little-endian halfwords in rows of the
depth stride from the depth address; columns 480 to stride-1 are left alone. The vertex shader and the Vulkan
viewport map the GE's z onto depth z / 65535 (`minDepth`/`maxDepth` from the viewport z scale and offset), so this
is the GE's own z; our sky samples read 22-24 where the dump has 23. D24 and D16 depth formats are converted too
(not exercised here: MoltenVK on the M4 Pro gives D32_SFLOAT_S8_UINT). Only screen-wide depth buffers (stride 480 or
more) are written, the rule the frame write-back uses: a
render-to-texture depth buffer has no height the GE states. Depth images now have TRANSFER_SRC usage.

The whole buffer is written, not a region around the sun: the sun's position is the game's, and predicting it from
the previous frame's loads would need the load trace, which lives in `vendor/portablekit/src/guest_memory.cpp`. The region would not
make it cheaper either: almost all of the cost is the wait (about 1 ms a race frame on the M4 Pro, 0.9 ms of it
the GPU wait, task 019), which is the same for one pixel.

The bloom reuses those bytes (0x04110000 and 0x04132000, 8888 stride 256). Each target's guest-word snapshot is
taken at its first draw of the frame (833 and 834), after the SIGNAL, so the bloom binds 835, 837 and 838 still find
their target images, and frame 6016 is unchanged (task 019). A target that the depth write overwrites between its
first draw and a bind would be decoded from guest memory instead, which is what the PSP would show there.

`PURE_NO_DEPTH_READBACK=1` turns it off; `PURE_TRACE_DEPTH_READBACK=1` prints one line per write-back with the z
range and the time. The framework has no per-game hook for this (`GameProfile` would need a field, and the profile
lives in `src/`), so it is on for every game: a game pays one GPU wait per SIGNAL interrupt that has a handler. Wipeout
Pure raises one per race frame and none in its frontend.

## History

[docs/history/ge-effects.md](history/ge-effects.md): the port's chain confirmed against the dump (task 008), the
lens flare's read before the write-back, the diagnosis of the magenta bloom, the stencil-as-alpha and attachment
results on frame 6016 (tasks 009 and 011), the environment draws and the alpha test (task 010), the flare with and
without the write-back and its cost (task 019), and the commands that reproduce each.

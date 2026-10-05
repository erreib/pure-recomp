# GE effects on a race frame: bloom chain and lens flare (task 008, 2026-10-05)

What Wipeout Pure's GE does in one race frame, with every change of render target and every texture bind that reads
VRAM the game rendered, taken from the PPSSPP GE dump (ground truth) and checked against our port's own traces. The
last section says how the framework's Vulkan renderer resolves each of those binds and why the race is magenta.

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
   bufw 128, linear, bilinear, transform mode, v scale -1 (flipped). That texture is the colour target the round
   just drew (dump VRAM flags 5: a target, drawn to). Opaque, depth test GREATER with writes. [Ours: rounds of 37,
   12, 7 and 6 draws after the clear at that moment; same addresses and formats.]
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

### Confirmed in our port

`PURE_TRACE_FB_TEXTURES` at the first race frame (5707) and the `PURE_TRACE_GE_LIST` replay of frame 6485 show the
same chain with the same registers: target 0x04110000 8888 stride 256 is created at 5707 together with 0x04132000;
texture 0x04088000 (0x04000000 on alternate frames) 8888 512x512 bufw 512 drawn to 0x04110000 with prim 6, 16 vertices,
pos (0.25,0.25)-(256,135.75), uv (0.5,0.5)-(512,271.5); texture 0x04110000 256x256 bufw 256 drawn to 0x04132000 with
1320 vertices, pos (-5,0)-(245,136); texture 0x04132000 256x256 bufw 256 drawn to 0x04110000, pos (0,-5)-(240,141);
texture 0x04110000 drawn to 0x04088000, pos (1,1)-(512,271), uv (0.5,0.5)-(256,135.5); blends add(SA, FIXB 0),
ONE+ONE, ONE+ONE, add(FIXA 0xAFAFAF, FIXB 0xFFFFFF) with MASKALPHA 0xFF. The lens flare is the draw just before
(60-vertex strip, CLUT8 64x64, depth test off), the SIGNAL sits after the sky cube.

## Lens flare: the CPU depth read

Where: in the GE signal handler for signal 0x0200, which the game places right after the opaque world and the sky
cube (step 4), so the depth buffer is complete and the bloom has not yet overwritten it. The signal function
registered with sceGeSetCallback (called at 0x088ED1D4; signal 0x088ECCAC, finish 0x088ECD28, both with argument
0x08AD70C4) is a dispatcher that records the signal id and calls a handler pointer kept at 0x08AD70C4; that handler
is set at run time and was not identified. The flare drawn later in the same list (step 6) carries the result in
its alphas, 0x3F-0x79 at frame 7155.

Does our port do it: yes. `PSPRECOMP_TRACE_VRAM_READS` (64 KiB blocks, at most one line a second) reports, all
through the race, 960 loads a second from 0x04120000-0x0412FFFF and 60 a second from 0x04130000-0x0413FFFF: 16 + 1
loads per frame at 60 frames a second, which fits the 4x4 sample (depth rows 64-127 hold the sun on this grid). All
25 `[vram]` lines for 0x04110000-0x0415FFFF in each run (the earlier ones, during the camera fly-by, hit
0x04150000-0x0415FFFF) come right after the sceGeListUpdateStallAddr call that executes the SIGNAL + END pair (for
example run B lines 586493-586496: `0x08B7EB58 0x0E020200`, `0x08B7EB5C 0x0C000000`, the stall update, then the
`[vram]` line). So the framework raises the signal (ge_state.cpp:1418-1456, interrupt queued at
hle_media.cpp:177-186) and the handler runs at the right point of the list.

What it reads: guest memory at 0x0412xxxx, which holds no depth in our port. The renderer keeps depth in a Vulkan
image per colour target (vulkan_renderer.cpp:993-1023, made in create_target :3397-3400) and never stores it; it
ignores the GE depth address altogether (`RenderTarget::depth_address`, ge_state.hpp:84, is not read anywhere in
vulkan_renderer.cpp). Nothing else writes 0x04110000-0x04153FFF: the frame write-back stores only displayed targets
of stride 480 or more (vulkan_renderer.cpp:4136), and no block transfer or sceDmacMemcpy in run A lands below
0x04179680. A `PURE_NO_FB_TEXTURES=1` race frame, whose bloom decodes 0x04110000 and 0x04132000 from guest memory,
adds nothing visible, so the area is (near) zero. Zero is "sky" (docs/research.md, GE usage). In the dump the depth
range is reversed and far is small: the sky cube writes 23-24, the frame's depths run 23-13430 and none is 0, so a
zero read is farther than anything the game draws and the flare should never be occluded in our port.
Our race screenshots (FB textures on or off, `out/008/shotsA/r6000.png`, `out/race-nofb/r6400.png` in the main
checkout) show bright flare rings and a white haze over the left half of the grid view, where PPSSPP's frame 7155
of the same grid shows no rings; the read values themselves are untested (the trace counts loads per block, not
addresses or values), and our flare's vertex alphas were not traced.

## Diagnosis: what the Vulkan renderer samples for each bloom bind

How a VRAM texture is resolved (vendor/portablekit/host/gpu/vulkan_renderer.cpp):

- Every draw's texture goes through `find_framebuffer_texture` (called at :5894-5897, defined at :4199-4235) unless
  `PURE_NO_FB_TEXTURES` is set. It looks at every render target (`targets`, a map keyed by colour address only,
  :1024) and keeps those that contain the texture's start address, assuming each target spans `stride x 272 rows`
  (:4212-4213), with the same bits per pixel (:4210) and `bufw == stride` (:4214). Among those it takes the one with
  the highest `draw_serial` (:4215), checks that guest memory under the texture still matches the words snapshotted
  when the target was first drawn this frame (:4226-4230, snapshot at :6143-6144), and returns the target with the
  texel position of the texture's first byte inside it (:4231-4234).
- A hit samples a copy of the target's colour image (`framebuffer_descriptor`, :4239), with the texture coordinates
  remapped into the target's 480x272 space and offset by that position (:6088-6107). A miss decodes guest memory
  (:6109). `draw_serial` is bumped for the draw's own target after the lookup (:6146).
- `[fbtex] ... large or copied texture` (:3995) is only a trace classification (textures of 256x128 or more, or
  filled by a VRAM DMA copy); it does not choose the path. In the race it names the sky faces (RAM, irrelevant) and
  the three bloom sources below.

| Bind | Targets that match at :4207-4219 | Chosen | What it samples | Right? |
|---|---|---|---|---|
| 833 downsample, 0x04088000 8888 512x512 bufw 512 | 0x04088000 (offset 0). 0x04000000 ends exactly at 0x04088000 and is excluded | 0x04088000 at (0,0) | the back buffer's colour image, rows 0-271 | yes |
| 835 h-blur, 0x04110000 8888 256x256 bufw 256 | 0x04110000 (offset 0) | 0x04110000 at (0,0) | rows 0-135 of the 0x04110000 image: the 833 result | yes |
| 837 v-blur, 0x04132000 8888 256x256 bufw 256 | 0x04110000 (offset 0x22000, row 136, stride 256 matches) and 0x04132000 (offset 0) | **0x04110000 at (0,136)**: draw 836 (the black sprite) bumped its serial after 835 bumped 0x04132000's | rows 136-271 of the 0x04110000 image, which no draw ever writes. The h-blur result in the 0x04132000 image is never read | **no** |
| 838 composite, 0x04110000 8888 256x256 bufw 256 | 0x04110000 (offset 0) | 0x04110000 at (0,0) | rows 0-135 of the 0x04110000 image: the 837 result, i.e. the blur of the wrong source | right image, wrong content |

None of the four reaches a depth image (the renderer never samples depth) or a guest-memory decode (the guest-word
check passes each time: nothing writes guest VRAM there between a target's first draw of the frame and the bind);
all four sample a copy of a colour image.

Why magenta. The game only ever draws 256x136 (833) and 240x136 (836, 837) into 0x04110000, so rows 136-271 of its
Vulkan image are never written, apart from the 837 sprites' overshoot to row 141, which adds into rows 136-140 every
frame and is never cleared. Targets are created on first use (`target_for`/`create_target`, :3377-3410) and
"loaded, not cleared, so a new target starts undefined" (:3412, :3475): those rows keep whatever the image held when
it was created at frame 5707. On this machine (MoltenVK on the M4 Pro) that content comes back with red and blue
high and green zero. Race frame 6400 with FB textures on (`out/008/shotsA/r6400.png`, run A) minus the same frame
and route with `PURE_NO_FB_TEXTURES=1` (`~/dev/pure-recomp/out/race-nofb/r6400.png`): the positive differences
average +72.8 red, +0.4 green, +77.0 blue; the signed green difference is 0.0 in six of eight horizontal bands and
-0.4 in the other two. The same magenta is added everywhere, and the 1.85 blur gain with the 0.686 composite
saturates red and blue (means 249 and 250 in the FB-on frame, 176 and 173 without). The three other binds,
the blend factors (resolve_fixed_factor :291-297 turns FIX 0xFFFFFF/0x000000 into ONE/ZERO, so 838 is CONSTANT x src
+ ONE x dst) and the coordinate mapping are right.

Fix proposal (description, not a patch): in `find_framebuffer_texture`, let a target whose base address equals the
texture's address win over targets that merely contain it (vulkan_renderer.cpp:4215), or more generally keep each
target's drawn row range and skip a containing target whose rows at the texture's offset were never drawn. Either
makes 837 read the 0x04132000 image at (0,0), as on the PSP, and leaves the other three binds as they are.

### What will still differ once the bind is fixed

- The bloom mask. The downsample weights the scene by the back buffer's alpha, which the game writes as stencil
  (step 3). The GE state ignores STENCILTESTENABLE 0x24, STENCILTEST 0xDC and STENCILOP 0xDD (run A's "GE commands
  ignored": 0x24 x392590, 0xDC x415717, 0xDD x363574) and the pipeline writes the fragment's alpha (src ONE, dst
  ZERO, vulkan_renderer.cpp:4607-4609). The mask would be texture alpha (mostly opaque) instead of 4 everywhere and
  255 on the lights, so the whole scene would bloom instead of 0.4% of it. Stencil REPLACE into alpha is needed for a
  faithful bloom.
- Write masks. MASKRGB 0xE8 and MASKALPHA 0xE9 are ignored too (x458568 each) and the pipeline always writes RGBA
  (`PipelineKey::color_mask` default, :270; only clear-mode draws set it, :6022). The composite and the HUD therefore
  overwrite the back buffer's alpha; harmless for the display, wrong for anything that reads it later.
- The lens-flare read (previous section): the renderer would have to store the depth of the 0x04088000/0x04000000
  target into guest 0x04110000 (16-bit, stride 512) when the SIGNAL is raised, or answer the read some other way
  (PPSSPP's hardware backends use the compat flag `SoftwareRasterDepth` for this game).

## Stencil as alpha: what the renderer does since patch 0004 (task 009, 2026-10-05)

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

What the renderer does now (`stencil_alpha` and `blend_reads_source_alpha` in vulkan_renderer.cpp, ge.frag
`stored`): the PSP stores a draw's stencil result, never its fragment alpha, in a 5551/4444/8888 target's alpha, so
outside clear mode a draw writes alpha only when the stencil test is on, no alpha bit is masked (0xE9 == 0) and the
zpass op is REPLACE (the reference; its top bit on 5551, top nibble on 4444) or ZERO. KEEP, a stencil test that is
off, any masked alpha bit and 5650 targets leave the destination alpha (no A in the colour write mask). INVERT, INCR
and DECR need the destination and are logged once and kept. Fragments that fail the depth or alpha test are
discarded, which is KEEP: right for every zfail op in this frame except the shadow volumes' INCR/DECR (logged once).
A stencil function other than ALWAYS is logged once and drawn as ALWAYS; for 357 that gives the right alpha (all three
ops REPLACE) and the colour it had before (the darkening covers the screen instead of the stencil < 4 pixels). The
value reaches the target in one of two ways: the fragment shader writes it as alpha (push constant `viewport.w` bit
2, value in bits 3..10) when the colour blend does not read the source alpha; when it does (SA or 1-SA on either side
with RGB written), the alpha blend factors do it: (ZERO, ZERO) for ZERO, which is exact, and (CONSTANT_ALPHA,
ONE_MINUS_SRC_ALPHA) with the blend constant's alpha set to the reference for REPLACE, which is exact for opaque
fragments and for the z-equal decal passes (destination already the reference) and a blend towards the reference
elsewhere (93-102, 820, 828). Colour write mask 0xE8: a channel whose 8 bits are all set is not written (the shadow
volumes and 103-112 no longer draw colour); partial masks are logged once. `PURE_NO_STENCIL_ALPHA=1` restores the
old behaviour.

Result at our port's first full-HUD frame (6016: the HUD fades in over 6010-6016 in both runs, READY follows at
about 6080), route `~/dev/pure-recomp/out/race/route.txt`:

| Frame | Sky (100,20,280,60) mean | vs fb-off at tol 24 | vs ref/vineta_k_start.png at tol 32 |
|---|---|---|---|
| FB textures on (`out/009/fb-on.png`) | 210.3 | 6.3% differ | 62.8% differ |
| `PURE_NO_FB_TEXTURES=1` (`out/009/fb-off.png`) | 195.1 | | 66.3% differ |
| FB textures on, `PURE_NO_STENCIL_ALPHA=1` | 254.5 | 94.0% differ | |
| PPSSPP reference | 170.1 | | |

The bloom now lights the ceiling strips, the screens and the engines instead of the whole frame. Both frames still
differ from the reference mostly through the haze over the scene and the pale track, which the bloom does not
cause (the fb-off frame has them too).
## The environment draws and the alpha test (task 010, 2026-10-05)

Before patch 0005 the port drew crowds, billboards, the far skyline, ships and HUD on Vineta K and left the track,
barriers, stadium arches, pillar bodies and the sky white (the clear colour, 0x04FFFFFF). The cause was one shader
line: the GE alpha-test function numbers.

### Which draws make those pixels (PPSSPP dump)

`ppdmp.py cover` rasterises the dump's transform-mode draws for coverage only (the GE's clip and drop rules, depth
clamp, MINZ/MAXZ, each draw's depth test and write; no texturing, blending, alpha test or culling) and reports which
draw is the last opaque writer of each pixel. Its picture of draw 0-832 reproduces the reference frame's geometry
(`out/010/cover_all.png`). The large environment meshes, all in the opaque world (step 3 above):

| Draws | What | Pixels | PRIM, vertices | Vertex type | Texture | State |
|---|---|---|---|---|---|---|
| 175, 178 (and 174, 177 farther on) | track surface, alternating tiles | 20563 + 13090 | tristrip 274, 272 | 0x00013d: uv s8, colour 8888, normal s8, position s16 | 0x0417e380 / 0x0417fb80 CLUT4 64x64 swizzled, 4 mips | cull on, FFACE 0; z GT with write; MINZ-MAXZ 1001-64946; opaque |
| 176 | the track's sloped edges and near barriers, both sides | 17890 | tristrip 270 | 0x00013d | 0x0417ef80 CLUT4 64x64 | as above |
| 165, 490 | barrier tops and the light band along the right barrier | 1627, 953 | tristrip 209, 43 | 0x00013f: uv f32, colour 8888, normal s8, position s16 | 0x041f6680, 0x041a8900 CLUT4 64x64 | as above |
| 486, 496, 497, 499 (right), 510, 511, 513 (left) | stadium arches | 7102, 2665, 11003, 625, 4313, 991, 1334 | tristrips of 97-337 | 0x00013d / 0x00013f | CLUT4 64x64, 128x64, 64x128 in VRAM | as above |
| 598-602 | sky cube, five faces (602 is the one in view) | 23868 (602) | tristrip 81, 81, 81, 163, 81 | 0x00011d: uv s8, colour 8888, position s16 | RAM CLUT8 256x256 | cull off; z GT; viewport z -473/+473, MINZ-MAXZ 0-946 |

None of them has weights, morph targets, an index buffer or through mode, and every one has the alpha test enabled
(0x22 = 1) with ALPHATEST 0xDB = 0x000001: function 1, ALWAYS, reference 0. 268 of the frame's 871 draws (31651 of
72733 vertices) are set up that way, and they are the last opaque writer of 113566 of the 130560 pixels (87%):
`out/010/cover_always.png` shows them, the rest grey. What stays grey is what the port drew before the fix: the
crowd stands (alpha test GREATER 0x7F), ships, shadow volumes, the billboard screens.

### The same draws in our port

`PURE_TRACE_GE_LIST=470000:4000` (with `PURE_FRAME_LOG=1`) covered frames 6361-6372 of a race run; frame 6364 replayed
with `ppdmp.py gelist --vt` has 866 draws, 301 of them with the alpha test on and ALWAYS. The track run is draws
270-274 (tristrip 177, 274, 270, 158, 272, vertex type 0x00013d, cull 1/0, depth clamp 1, MINZ-MAXZ 1001-64946,
ALWAYS ref 0), the dump's 174-178 in the same order and pairing of textures, and the sky cube is 590-594 (81, 81, 81,
163, 81 vertices, 0x00011d, MINZ-MAXZ 0-946, ALWAYS). So the game issues them and the GE state reaches the renderer
unchanged; the texture VRAM addresses sit 0x1DC0 lower in our port (0x0417d5c0 for the dump's 0x0417e380), which
does not matter for this.

### What the renderer did with them

Checked in the brief's order:

1. Vertex type: 0x00011d, 0x00013d and 0x00013f are plain formats `decode_vertices` (ge_state.cpp:389) handles; no
   weights, morph, index or through bits.
2. Depth range and viewport: the world's viewport z is scale -31973, centre 32973, so the Vulkan viewport gets
   minDepth 0.991 and maxDepth 0.015 (vulkan_renderer.cpp:6180-6186), a reversed range Vulkan accepts; the crowds that
   did draw use the same one. The track's clip-space z/w stays inside [-1, 1] (draw 176: -0.97 to 0.99), so the
   [0, w] remap in ge.vert (:291-297) clips nothing extra. MINZ/MAXZ are 0xD6/0xD7 (0xD8/0xD9 are the colour test);
   the GE state stores them (`range_near`/`range_far`) and the renderer never applies them, which can only draw more.
   `PURE_NO_DEPTH=1` did not bring the meshes back (`out/010/nodepth/r6400.png`).
3. Culling: `PURE_NO_CULL=1` did not bring them back (`out/010/nocull/r6400.png`).
4. Patches: the frame has no BEZIER or SPLINE; PSUB/PPRIM/PFACE are set and unused.
5. The alpha test. ge.frag:72 tested `alpha_function == 1` as NEVER and let 0 pass, and vulkan_renderer.cpp:6057
   compiled the discard into the pipeline whenever the function was not 0. The GE numbers alpha-test functions like
   depth-test functions (the renderer's own depth mapping at :335-342 has them right): 0 NEVER, 1 ALWAYS, 2 EQUAL,
   3 NOTEQUAL, 4 LESS, 5 LEQUAL, 6 GREATER, 7 GEQUAL. Every fragment of every ALWAYS draw was discarded.

Patch 0005 makes the shader test by the GE numbering (0 discards), pushes ALWAYS (1) for draws without the test and
for clear-mode draws (vulkan_renderer.cpp:6082, :6090), and leaves the discard out of the pipeline for ALWAYS
instead of NEVER (:6057). The race frame then shows the track, barriers, arches, pillars and sky
(`out/010/race-hud.png`); the title screen capture is unchanged (0.0302 against ref/title.png, as in task 006).

What still differs on the grid view, all outside this fix: the ship shadows are solid dark-blue blocks (draws
339-356 are stencil shadow volumes, STENCILOP 0x000400/0x000500 = zfail INCR/DECR with MASKRGB 0xFFFFFF, both
faces in turn, and the GE state ignores both
stencil and the write masks: task 009), the lens flare's haze over the upper left (the CPU depth read, section
above), and no bloom with `PURE_NO_FB_TEXTURES=1`.

## Reproducing

```
P=/opt/homebrew/bin/python3
$P tools/ppsspp/ppdmp.py passes ref/vineta_k_start.ppdmp          # targets and VRAM binds
$P tools/ppsspp/ppdmp.py draws ref/vineta_k_start.ppdmp --all     # every draw
$P tools/ppsspp/ppdmp.py verts ref/vineta_k_start.ppdmp 835       # the blur taps
$P tools/ppsspp/ppdmp.py tex ref/vineta_k_start.ppdmp 833 out/008/tex833.png
grep -v shot ~/dev/pure-recomp/out/race/route.txt > out/008/route.txt   # then add N:shot lines
$P tools/run_boot.py --script out/008/route.txt --frames 6500 --shots out/008/shotsA --max-lines 3000000 \
  --env PURE_FRAME_LOG=1 --env PURE_TRACE_FB_TEXTURES=1 --env PSPRECOMP_TRACE_VRAM_READS=1 \
  --env "PURE_TRACE_CALLS=sceGe_user:0xAB49E76A,sceGe_user:0xE0D68148,sceGe_user:0x03444EB4,sceGe_user:0xB287BD61" \
  out/008/runA.log
# add --env PURE_TRACE_GE_LIST=FIRST:COUNT for list words, then: $P tools/ppsspp/ppdmp.py gelist <log excerpt> --all

# task 010: vertex types and the coverage of each draw
$P tools/ppsspp/ppdmp.py draws ref/vineta_k_start.ppdmp --all --vt
$P tools/ppsspp/ppdmp.py cover ref/vineta_k_start.ppdmp out/010/cover_all.png
$P tools/ppsspp/ppdmp.py cover ref/vineta_k_start.ppdmp out/010/cover_hl.png --highlight 165,174-178,490,598-602
$P tools/run_boot.py --script out/010/route.txt --frames 6420 --shots out/010/gelist --max-lines 1500000 \
  --env PURE_NO_FB_TEXTURES=1 --env PURE_FRAME_LOG=1 --env PURE_TRACE_GE_LIST=470000:4000 out/010/gelist.log
# frames 6361-6372 traced in that run; slice between two "[pure] frame" lines, then gelist --all --vt
```

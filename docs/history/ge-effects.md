# GE effects on a race frame: the record (tasks 008 to 019, 2026-10-05 and 2026-10-06)

The parts of docs/ge-effects.md that recorded how its rules were found and what each fix measured, moved here by
task 053 (2026-10-07). The frame, the dump and the rules the port draws by stay in
[docs/ge-effects.md](../ge-effects.md). Task 053 changed only the patch numbers, which task 052 regrouped
(patches/README.md maps them): old 0003 to 0008 are all part of patch 0003-vulkan-renderer-fixes now, each named
here with its task. Paths, line numbers and the renderer's behaviour are as they were on the dates given.

## Confirmed in our port (task 008)

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
addresses or values), and our flare's vertex alphas were not traced. Task 019 traced both and added the depth
write-back (old patch 0008, now part of 0003-vulkan-renderer-fixes; docs/ge-effects.md, "The depth write-back for
the lens flare"): the loads go through the 0x04600000 mirror, and with it the samples read the
sky cube's depth (24) on the grid, as in the dump, and the flare dims and goes as geometry covers the sun.

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

## Stencil as alpha (task 009, 2026-10-05)

The stencil state of the dump's frame is in docs/ge-effects.md ("The stencil and the alpha"). What the renderer
did with it after task 009, before task 011 added the attachment:

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

Before task 010's fix (old patch 0005) the port drew crowds, billboards, the far skyline, ships and HUD on Vineta K and left the track,
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

Task 010's fix (old patch 0005) makes the shader test by the GE numbering (0 discards), pushes ALWAYS (1) for draws without the test and
for clear-mode draws (vulkan_renderer.cpp:6082, :6090), and leaves the discard out of the pipeline for ALWAYS
instead of NEVER (:6057). The race frame then shows the track, barriers, arches, pillars and sky
(`out/010/race-hud.png`); the title screen capture is unchanged (0.0302 against ref/title.png, as in task 006).

What still differs on the grid view, all outside this fix: the ship shadows are solid dark-blue blocks (draws
339-356 are stencil shadow volumes, STENCILOP 0x000400/0x000500 = zfail INCR/DECR with MASKRGB 0xFFFFFF, both
faces in turn, and the GE state ignores both
stencil and the write masks: task 009), the lens flare's haze over the upper left (the CPU depth read, section
above), and no bloom with `PURE_NO_FB_TEXTURES=1`.

## The stencil attachment: before and after (task 011, 2026-10-05)

Task 009 (old patch 0004) kept the PSP's stencil only as the target's alpha, which a draw can write but never test, so the shadow
volumes (339-356) and the GREATER test of the darkening quad 357 were drawn as ALWAYS: 357 darkened the whole opaque
world to 0x9f/0xff (62%) instead of the shadowed pixels. Task 011 (old patch 0006) gives every render target a real stencil aspect
and keeps the alpha as a copy of it; task 009's behaviour is what `PURE_NO_STENCIL_BUFFER=1` gives now.
Result on frame 6016 of the race route (2x capture downscaled to 480x272; mean luma 0.299 R + 0.587 G + 0.114 B;
`PURE_NO_STENCIL_BUFFER=1 PURE_NO_DUAL_SOURCE=1` is task 009's path). The shadow regions were chosen from the
reference: a throwaway rasteriser over `ppdmp.py`'s `walk()` (the `cover` rules plus back-face culling and the
volumes' zfail INCR/DECR counts) marks 1046 pixels of the dump's frame that the volumes leave below 4, under the
player's ship, the left-row ship, the middle ship and a far one; each region below lies inside that mask.

| Region (x,y w x h) | PPSSPP | task 011 (`out/011/hud.png`) | other task 011 runs | task 011 off (`out/011/off/hud.png`) |
|---|---|---|---|---|
| player ship's shadow (222,250 16x22) | 30.0 | 32.0 | 34.1, 33.5, 32.0 | 32.0 |
| left-row ship's shadow (53,197 26x3) | 38.1 | 40.7 | 43.4, 40.3, 40.2 | 39.6 |
| middle ship's shadow (231,171 15x2) | 85.5 | 94.1 | 107.6, 98.2, 94.2 | 89.5 |
| plain track (160,205 40x8) | 173.3 | 181.2 | 182.5, 182.1, 181.1 | 120.0 |
| plain track (300,200 30x8) | 184.3 | 192.1 | 201.5, 197.5, 192.0 | 128.0 |
| whole frame vs reference at tol 32 | | 6.9% differ | 7.5%, 8.6%, 6.3% | 30.4% |

With the stencil off, 357 darkens every pixel it covers, so the shadow regions match the reference and the open track
is 62% as bright as it should be; with it, only the shadows are dark. A throwaway build that drew 357 unblended
(black where its stencil test passes) left 308 pixels below luma 10 in rows 140-271, all of them inside the
reference's mask (the player's shadow), and a ship-shaped dark patch under the left-row ship, whose model in that run
was not the dump's. The rest of the mask lies under ships the port draws differently: the AI field is not the same
from run to run (our frame 5977 has nine volume pairs of 312, 108, 252, 168, 240, 156, 144, 540 and 432 vertices
where the dump has 420, 456, 180, 252, 312, 156, 108, 240 and 168, and the four captures show different ships in
the left and middle slots), so the middle region varies most between runs. The frontend draws nothing that needs the
copy (the first one is at the race's first frame), and the title capture is 3.0% against ref/title.png at tol 24, as
before.

## The depth write-back: the flare with and without it (task 019, 2026-10-06)

`out/019/drive.txt` is the race route plus `6100:pad a 3000` (Cross held, no steering: the Feisar runs along the
first straight's left wall into the pillars). Two runs of it to frame 7500 with the throwaway trace, write-back on and
`PURE_NO_DEPTH_READBACK=1`; the player's path is the same in both (ship probe at frame 6690: dist 1464.906 and
1464.895). Frames 6250-7499 (1250), by how many of the 16 sun samples hold geometry (z above 30), with the alpha of
the flare's first element (the sun glow; the draw is the 60-vertex strip on the CLUT8 64x64 atlas, which the game
moves between 0x0968A4B0 in RAM and 0x0417B640 or 0x0417DA80 in VRAM):

| Sun samples covered | Frames (on) | Flare drawn (on) | First alpha (on), mean (range) | Off |
|---|---|---|---|---|
| 0 (all read 22-24) | 510 | 510 | 128.6 (109-157) | every frame reads 0 |
| 1-3 | 14 | 14 | 117.7 (98-134) | |
| 4-7 | 34 | 33 | 96.3 (68-118) | |
| 8-11 | 22 | 22 | 69.0 (38-79) | |
| 12-15 | 28 | 24 | 30.0 (9-40) | |
| 16 | 642 | 6 (alpha 0) | 0 | |
| all | 1250 | 609 | | 1250 drawn, first alpha 147.9 (109-182) |

So the game scales the flare by the share of samples that see the sky and drops the draw when none do. Without the
write-back every sample reads 0, which the game takes as sky, and the flare is drawn in every frame.

Frame 6690 (`out/019/drive_on/frame_6690.png`, `out/019/drive_off/...`): the sun is behind the left pillar, all 16
samples read 3187-3224. With the write-back there is no flare; without it the pillar is washed out by the glow and
the rings. Mean luma (0.299 R + 0.587 G + 0.114 B) in PSP (100,40 90x100) around the sun: 105.2 on, 176.5 off.
Frame 6016 (open sky on the grid): the samples read 24 with it on and 0 with it off, the flare is drawn in both
(first alpha 121, the others 60-108, jittered by the game from frame to frame either way), the same region is 225.7
on and 225.8 off (PPSSPP 221.1), and `out/019/hud.png` is 0.0676 against ref/vineta_k_start.png at tol 32 (0.0676
with it off; 0.0740 in another run with it on, where the AI field differed).

Cost, the same drive script to frame 7500 without the throwaway trace, `PURE_PERF=log`, averaged over the 25
one-second `[perf]` lines between the `[pure] frame 6000` and `[pure] frame 7500` marks, and the 1500
`PURE_TRACE_DEPTH_READBACK` lines in the same frames:

| | Off | On |
|---|---|---|
| fps (game fps) | 59.93 (59.92) | 59.94 (59.93) |
| frame avg / max ms | 16.70 / 18.74 | 16.70 / 18.72 |
| guest / render / pacing wait ms | 2.51 / 1.31 / 12.86 | 2.50 / 1.52 / 12.67 |
| GPU ms a frame | 0.80 | 0.90 |
| write-back, total (GPU wait) ms | | mean 1.07 (0.90), median 0.95 (0.77), max 15.1 (14.9) |

The race is held to 60 fps by the game's pacing either way; the write-back takes about 1 ms of the 16.7 ms frame
(6.4%), 0.9 ms of it waiting for the GPU to finish the frame's opaque world, which with the write-back off would
overlap the CPU's work instead. The copy and the conversion are the other 0.15 ms.

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

# task 011: the race frame with and without the stencil attachment, the copies, and our frame's volume draws
(grep -v shot ~/dev/pure-recomp/out/race/route.txt; echo "6016:shot hud") > out/011/route.txt
$P tools/run_boot.py --script out/011/route.txt --frames 6045 --shots out/011/shots out/011/hud.log
$P tools/run_boot.py --script out/011/route.txt --frames 6045 --shots out/011/off \
  --env PURE_NO_STENCIL_BUFFER=1 --env PURE_NO_DUAL_SOURCE=1 out/011/off.log
$P tools/run_boot.py --script out/011/route.txt --frames 6045 --shots out/011/copy --max-lines 200000 \
  --env PURE_TRACE_STENCIL_COPY=1 --env PURE_FRAME_LOG=1 out/011/copy.log
$P tools/run_boot.py --script out/011/route.txt --frames 6030 --shots out/011/gel --max-lines 1500000 \
  --env PURE_FRAME_LOG=1 --env PURE_TRACE_GE_LIST=325000:30000 out/011/gelist.log
# run 325000 is frame 5938 and the log cap ends in frame 5978; frame 5977 replayed with gelist --all

# task 019: the depth write-back. The read addresses and the flare alphas came from a throwaway edit (a line per
# guest load from the depth buffer's bytes in GuestMemory::aot_load*_slow, and the vertex alphas of 60-vertex draws
# on a 64x64 texture in VulkanRenderer::submit); the runs below without it give the frames and the timings.
(grep -v shot ~/dev/pure-recomp/out/race/route.txt; echo "6016:shot hud") > out/019/route.txt
(cat out/019/route.txt; echo "6100:pad a 3000") > out/019/drive.txt
$P tools/run_boot.py --script out/019/route.txt --frames 6045 --shots out/019/shots out/019/hud.log
$P tools/run_boot.py --script out/019/drive.txt --frames 7500 --shots out/019/drive_on --every 30 \
  --max-lines 400000 --env PURE_FRAME_LOG=1 --env PURE_TRACE_DEPTH_READBACK=1 --env PURE_WATCH_SHIP=1 out/019/drive_on.log
#   and the same with --env PURE_NO_DEPTH_READBACK=1 into out/019/drive_off
$P tools/run_boot.py --script out/019/drive.txt --frames 7500 --shots out/019/perf_on --max-lines 400000 \
  --env PURE_FRAME_LOG=100 --env PURE_PERF=log --env PURE_TRACE_DEPTH_READBACK=1 out/019/perf_on.log
#   and the same with --env PURE_NO_DEPTH_READBACK=1 into out/019/perf_off.log
```

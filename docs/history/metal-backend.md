# The Metal GE backend: the record (tasks 023 to 042, 2026-10-06 and 2026-10-07)

What docs/metal-backend.md recorded of each task's measurements, moved here by task 053 (2026-10-07); the backend as
it is stays in [docs/metal-backend.md](../metal-backend.md). Task 053 changed only the patch numbers, which task 052
regrouped (patches/README.md maps them), naming each by the patch that holds the change now and the task that made
it. File names are as they were on each date: before task 049 the backend was the one file `metal_backend.mm` and its
shaders a string in `metal_shaders.h`.

## The backend's story (tasks 023 to 040)

The doc's opening paragraph as it stood before task 053:

`PURE_GE_BACKEND=metal` draws the game with Metal, natively, behind the GE backend seam of D-003
(`docs/ge-backend.md`). It is `src/gpu/metal_backend.mm` and the files beside it ("Files"), registered as `metal`. Task
023 built its skeleton (device, targets, textures, the draws of the 2D frontend, clears, blending, the alpha test,
captures) and proved it on the frame regression suite's three frontend scenes, which it draws within a few pixels
of PPSSPP: the language page, the title screen and the profile screen. Task 024 added the 3D draws: the GE's
per-vertex lighting and fog, transformed sprites expanded on the screen, and culling confirmed on the race. Task 025
added the effects of the renderer fixes of tasks 009 to 019 (patch 0003-vulkan-renderer-fixes): the stencil test and operations with the target's alpha kept as the
PSP's stencil (the shadow volumes, the bloom's mask), the bloom chain's passes over aliased VRAM, block transfers
and read-backs from targets into guest memory, the frame write-back and the depth write-back the lens flare reads
at a GE SIGNAL. The race frame 6016 is now drawn as the Vulkan backend draws it, 2 pixels of 130560 over tol 24 at
the same scale ("The race check" below), and the frame regression suite passes 5/5 with `--backend metal`, race_hud
at 0.0379 against PPSSPP (Vulkan's 0.067). The Metal shell (task 027, "The Metal shell" below) shows its
pictures in a window of its own, with no Vulkan involved. Task 036 added the GE's texture mapping modes, the
texture matrix and the environment map (patch 0002-ge-state-commands carries them in the draw state): the ships' hulls and canopies,
glass and shiny roofs show their reflections ("Texture mapping modes" below), which the Vulkan backend does not draw.
Task 037 added the mip levels (patch 0002-ge-state-commands carries them): a texture the GE names levels for is a mipmapped texture,
sampled at the level the GE's rule picks, so distant textures no longer shimmer ("Mipmaps" below). Task 040 added
the colour test, the writes into 16-bit targets (the format's bits kept, dithered as the GE says) and CLIPENABLE's
depth clamp (patch 0002-ge-state-commands carries the three; "The colour test, 16-bit writes and the depth clamp" below).

## One command queue: why (task 031, 2026-10-06)

Until task 031 the shell had a queue of its own. Metal orders the command buffers of two queues only through an event
(`MTLSharedEvent`) or a wait, and the backend commits its frame without waiting, so the shell's present could sample
the target before the end of the frame had run on the GPU. In a race the window then showed the 3D picture without
the HUD drawn after it, and players saw the HUD flicker or vanish. `tools/hud_check.sh` (docs/verification.md, "The
race HUD check": 61 shots from flip 6200 to 7700 of the race route) counted 11 of 61 shots with the HUD on two queues
(task 028's probe: 12), and 61 of 61 on one queue, as on the Vulkan shell and in the backend's own headless captures.
The SIGNAL's mid-frame commit and wait was not the cause: task 028's probe with `PURE_NO_DEPTH_READBACK=1`, which
leaves the race one command buffer a frame, had the HUD in 3 of 61 shots.

A shared event was not needed. The backend could signal an `MTLSharedEvent` at its commit and the shell encode a wait
for it before sampling, which orders two queues the same way; but on one queue such a pair orders nothing the queue
does not order already, and it would need the event and its value handed from the backend to the shell, for which
the framework's `PresentedImage` has no field. One queue needs no new interface and no new wait.

The race under the Metal shell still runs at 60 fps: with `PURE_PERF=log`, the 24 one-second lines of the race in the
check's route read 59.7 to 60.1 fps, render 3.1 ms a frame on average, and the backend waited for the GPU 2009 times in
7710 flips (2003 of them at the SIGNAL), as many as on two queues.

## The Metal shell: numbers (task 027, 2026-10-06)

`tools/frame_regress.sh --shell metal --backend metal --only lang,title,profile` (2026-10-06, M4 Pro): lang 0.0002,
title 0.0002, profile 0.0000, task 023's values, in 72 s. The three 960x544 captures are pixel-identical
(`imgdiff.py --tol 0`) to the Vulkan shell's with the hand-over (`--backend metal`) of the same day. Over the frontend
route the backend waited for the GPU twice (0.9 ms) against 2128 times (1009 ms) with the hand-over; the route takes
the same 71 s either way, paced to real time. One of the runs caught the blinking cursor after LOAD at frame 2100
(profile 0.0002, 22 pixels, 19893 draws instead of 19853): its phase follows the real-time pacing, as on lang and
title. For comparison, `--shell headless --backend metal` gives the same three fractions from the backend's own 480x272
captures in 2 s (no window, unpaced: patch 0005-kernel-host-waits-and-pacing), and `tools/frame_regress.sh` with the Vulkan shell and backend still
passes 5/5 at 0.0544, 0.0302, 0.0543, 0.0331 and 0.0672.

A window resized through the menu (Window size x3) gets a 1440x816 drawable, and its capture reduced to 480x272 is
identical to the 2x one: nearest at 3x as at 2x.

The menu opens over the game with Esc (the interface's key) and closes with Esc again: `out/027/menu_shots/menu_open.png`
of task 027's check shows it over the paused language page.

## Frame times (task 033, 2026-10-06)

Erik's first race on the app dipped "here and there", while the scripted race's one-second `[perf]` lines held 59.7 to
60.1 fps: a second's average hides single long frames. Task 033 gave the backend a trace with a row per flip, measured
the Vineta K race cell with it, and removed what the backend and the shell could remove without changing a pixel: the
render pipelines compiled on first use (pre-warmed now) and the Metal shell's uneven presents on a 120 Hz display
(timed to the PSP's vblank now). Most of what remains is the game's own: stretches of frames that wait two vblanks.

### Method

The Vineta K Single Race cell (the menus, a three-lap race in which the follower presses Square, use pickup, every 120
flips, the results screen), under the Metal shell in a window, since the dips are what a player sees:

```sh
PURE_METAL_TRACE=out/033/race.csv python3 tools/campaign_sweep.py single_race vineta_k --no-damage --shell metal
python3 tools/frame_times.py out/033/race.csv --long 20 --fps 60 --from 6250 --to RESULTS-300
```

The sweep takes no `--env` (task 034's argument list): the environment reaches the game. The race is read from flip
6250, where the race clock starts, to 300 flips before the results screen. M4 Pro with its built-in display at 120 Hz;
the machine was in use during the runs (a browser at full load on one core, a VM, video), which shows as scattered
frames whose `draws` or `outside` grow with no more work in them. The window was not always visible: in three runs (A, C and D
below) the pictures stopped reaching the screen part of the way through or never did (the `shown_ms` and `occluded`
columns), and while it is occluded macOS holds `nextDrawable` back for up to a second. A cold shader cache, as on a machine's first start of the
app (Erik's first race), was made with a throwaway build, not committed: the shader source got an unused varying holding
a number from the environment, new for each run, so Metal's cache missed every library and pipeline.

### The runs

| Run | Shell | Window | Shader cache | Pre-warm | Pictures | Race window (flips) | Frames | Over 20 ms | Over 25 ms | 99th pct |
|---|---|---|---|---|---|---|---|---|---|---|
| A | Metal | shown until flip 7184, then occluded | warm | off | at once | 6250-17070 | 10821 | 236 | 227 | 33.4 ms |
| B | headless | none | warm | off | | 6250-17110 | 10861 | 244 | 188 | 33.3 ms |
| C | Metal | never shown | cold | off | at once | 6250-17610 | 11361 | 124 | 119 | 31.0 ms |
| D | Metal | occluded from flip 7769 | cold | on | at once | 6250-17990 | 11741 | 113 | 106 | 19.6 ms |
| E | Metal | shown | warm | on | at once | 6250-16890 | 10641 | 61 | 52 | 18.6 ms |
| F | Metal | shown | warm | on | at the PSP's vblank | 6250-17310 | 11061 | 73 | 72 | 18.9 ms |

The race's frames over 20 ms by cause (the tool's rule; a two-vblank stretch is three or more frames in a row over 25
ms whose cause is `outside`):

| Cause | A | B | C | D | E | F | What it is |
|---|---|---|---|---|---|---|---|
| two-vblank stretches (outside) | 211 in 11 | 116 in 8 | 108 in 6 | 94 in 3 | 48 in 2 | 71 in 3 | mostly runs of 13 to 39 frames of 31 to 35 ms, `other_ms` 28 to 32 ms and nothing else above its median: the game's own 30 fps (below) |
| outside, single frames | 11 | 80 | 6 | 8 | 8 | 1 | host contention: `other_ms` alone grows to 40 to 75 ms |
| draws, texture, backend | 3 | 45 | 4 | 5 | 1 | 1 | host contention: `submit_ms` 10 to 110 ms over the usual draws, `texture_ms` up to 34 ms with nothing decoded (the thread descheduled while hashing) |
| wait depth | 7 | 3 | 6 | 4 | 4 | 0 | the SIGNAL's depth write-back waiting 13 to 40 ms for the GPU (median 0.6 ms) |
| drawable, shell | 4 | 0 | 0 | 2 | 0 | 0 | the window occluded: `nextDrawable` held for 104 to 973 ms |
| pipeline | 0 | 0 | 0 | 0 | 0 | 0 | no render pipeline was made in any race; on a cold cache they all came before it (below) |

Before the race the cold cache mattered: in C the race's load (flip 5708) took 134.7 ms making 18 pipelines (122.9 ms
of it), flip 5745 27.6 ms making 3 (21.5 ms), and flips 3 and 5 at boot 26.9 and 26.4 ms; with the pre-warm (D) flips
5708 and 5745 took 15.0 and 7.2 ms, flip 5 10.1 ms, flip 3 waited 11 ms for the pre-warm's first pipeline (27.9 ms),
and no draw made a pipeline after it. On a warm cache a pipeline takes 0.2 to 2 ms on first use, and A and B made all 26
before the race, none in a frame over 25 ms. `--check-no-pipeline-stalls-after 600` fails on C (flips 5708 and 5745)
and passes on every other run.

On screen, run E (the window shown throughout, pictures shown at once) had what the flip times do not show: of 10641
pictures, 476 stayed 25 ms and 470 only 8.3 ms, in pairs, in most five-second stretches of the race (up to 28 pairs in
five seconds). The flips come every 16.68 ms with a standard deviation of 1.4 ms (the kernel's sleeps), and at 120 Hz a
picture is shown at the first refresh after its flip: while the flips' phase lies near a refresh boundary they
alternately catch and miss it. That stutter is the other "dip here and there" a player sees besides the game's own 30
fps stretches; F removes it (After).

### The two-vblank stretches (outside the backend and the shell)

In every run most of the race's long frames come in runs of frames at two vblanks each (about 33 ms; most runs 13 to 39
frames long), with no time above its median in any backend or shell column, 2 to 11 runs a race (E: 7082-7105 and
12280-12303; A: eleven). The emulated clock does not advance while guest code runs (it
jumps to the next event when every thread waits, `Kernel::schedule`), so a frame of two vblanks is the guest waiting
across two vblanks, which `[perf]` confirms ("game" 35 to 49 fps at speed 100% in those seconds). docs/timing.md
describes the game's end-of-frame routine: in a locked mode, or while a countdown at the frame object's `+0x117c` runs,
it waits two vblanks a frame (30 fps). What starts these stretches in the race, and whether the PSP has them in the same
places, is a question for the HLE and the game, outside this task (the brief's escalation): see the pacing trace below
and the Result of docs/tasks/033-frame-time-dips.md.

A headless run of the cell with the framework's pacing trace beside the frame trace (`PURE_TRACE_PACING=900000
PURE_METAL_TRACE=FILE python3 tools/campaign_sweep.py single_race vineta_k --no-damage --max-lines 1500000`; the n-th
`sceDisplaySetFrameBuf` line is flip n) shows the switch. In the race's ordinary frames the main thread calls no vblank wait: it reads the pad
(`sceCtrlReadBufferPositive`, which blocks until the next vblank's sample) and flips 250 us after each vblank, a frame
a vblank. In its stretch at flips 9261-9276 it calls `sceDisplayWaitVblankStart` twice a frame and flips on every
second vblank, the end-of-frame routine's locked path of docs/timing.md (step 5: `n = 2 - (vcount - lastVcount)` waits
when `+0x116c` is 0 or the countdown at `+0x117c` runs), then returns to the free-running path at flip 9277. The
stretches come back at about the same flips in different runs (7082-7105 in D and E; 16252-16290 in D, 16259-16283 in
F), so something in the race sets the lock. Finding what (a watch on `+0x116c` and `+0x117c` of the frame object, and
PPSSPP's frame rate at the same place on the track) is the follow-up the task reports.

### What changed

| Change | Where | What it does |
|---|---|---|
| Pipeline pre-warm | `metal_backend.mm` `start_prewarm`, `config/metal_pipelines.txt` | at `initialize`, the depth-stencil states of the list are made at once and its render pipelines are asked of Metal asynchronously (`newRenderPipelineStateWithDescriptor:completionHandler:`); a draw takes its pipeline from them on first use, waiting only for one not made yet; a key not in the list is still made on first use |
| Pictures at the PSP's vblank | `metal_shell.mm` `present_time` | while emulated time is held to real time (the HLE passes the frame's moment, the real time of the vblank it began from), each game picture is presented at that moment plus one PSP frame (`presentDrawable:atTime:`), when the PSP shows a flip; otherwise, or when that time has passed, at once. `PURE_METAL_PACE=0` turns it off |
| The trace, the tool, the occlusion column | `metal_backend.mm`, `metal_device.hpp`, `metal_shell.mm`, `tools/frame_times.py` | above |

Neither changes a pixel: the pipelines are the ones the draws made before, and the pictures are the same, shown at other
moments. `tools/frame_regress.sh` (both window paths and headless) and `tools/hud_check.sh` pass as before (the Result
of the task file has the runs).

### After

The long frames left in the race with both changes (F, the window shown): 71 in three two-vblank stretches (14720-14752,
15226-15238, 16259-16283) and two of host contention, none with a pipeline made in it, before or after the race's
first 10 seconds. The stretches are the game's; the two others, frames whose `outside` and `draws` grew with no more
work in them, the machine's.

On screen (the drawables' presented times, the window shown):

| Run | Pictures | Shown 16.7 ms | 25 ms | 8.3 ms | 33 ms (the game's two-vblank frames) | Latency, present to screen |
|---|---|---|---|---|---|---|
| E, pictures shown at once | 10641 | 90.6% | 476 | 470 | 51 | 21.5 ms mean, 37.3 longest |
| a minimum duration of two refreshes (`presentDrawable:afterMinimumDuration:`, tried, not kept) | 11091 | 99.4% | 19 | 0 | 49 | 34.0 ms mean, 67.6 longest; `nextDrawable` held the game 4 to 22 ms in 1217 frames |
| F, pictures at the PSP's vblank | 11059 | 98.6% | 47 | 28 | 72 | 27.0 ms mean, 46.9 longest; `nextDrawable` never waited |

The minimum duration evens the pictures out further, but each late flip moves the whole schedule a refresh later and
only the game's slightly slower rate (59.94 against 60) brings it back, so the queue of drawables filled and held the
game back: two to three frames of latency. Times from the game's own vblank grid carry no host jitter and keep the
queue empty, for 5.5 ms more latency than showing each picture at once.

## The pre-warm list's coverage (task 042, 2026-10-07)

What the list covers since task 042 (2026-10-07), each cell headless with the list of task 033 (26 render pipelines,
28 depth-stencil states) in force:

| Cell | Outcome | Render keys used | Depth-stencil keys | Made by a draw (not in task 033's list) |
|---|---|---|---|---|
| Single Race Vineta K | PASS, 3 laps, 197 s | 29 | 26 | 6 render pipelines |
| Single Race Modesto Heights | PASS, 3 laps, 292 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Chenghou Project | PASS, 3 laps, 269 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Blue Ridge | PASS, 3 laps, 280 s | 29 | 24 | 6 |
| Single Race Sinucit | STALL in lap 2 (left the track at Sinucit's fork, 880 to 1010 m), 164 s | 25 | 24 | 5 |
| Single Race Citta Nuova | PASS, 3 laps, 359 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Sebenco Climb | PASS, 3 laps, 331 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Sol 2 | PASS, 3 laps, 264 s | 26 | 25 | 6, and 1 depth-stencil state |
| Single Race Karbonis | STALL in lap 3 (the follower left the track at 2600 to 2760 m), 180 s | 24 | 23 | 3 |
| Single Race Sagarmatha | PASS, 3 laps, 224 s | 24 | 23 | 3 |
| Single Race Manor Top | STALL in lap 1 (left the track at 2250 to 2490 m), 95 s | 24 | 23 | 3 |
| Single Race Mandrashee | PASS, 3 laps, 247 s | 24 | 24 | 3 |
| Time Trial Vineta K | PASS, 3 laps, 235 s | 32 | 25 | 9 |
| Free Play Vineta K | PASS, 3 laps, 216 s | 32 | 25 | 9 |
| Zone 1 | PASS, 6 zones, 75 s | 23 | 23 | 2 |
| Tournament, Alpha league | PASS, 4 races, 1121 s | 32 | 30 | 9, and 2 depth-stencil states |

37 render keys and 30 depth-stencil keys in all. Of task 033's list, 24 render keys and all 28 depth-stencil keys are
still used; two render keys are gone, because the draws that made them make their colour-test or 16-bit variants
since task 040. The 13 new render keys:

- the six of task 040 (four `sixteen=1`, two `color_test=1`) that the Vineta K race makes, and the other Alpha and Beta
  circuits too;
- three that only Time Trial and Free Play drew: with the six, the nine every 30-fps run made by a draw (task 041);
- three untextured blends with source factor zero, drawn only by the Tournament's screens between races;
- one colour-test key without the alpha test (`source=4 destination=1 ... alpha_test=0 color_test=1`). The Classic
  circuits and Zone draw it, and they make no 16-bit draw.

The two new depth-stencil states (depth compare 4 with a stencil test, functions 1 and 6) come from Modesto Heights,
Chenghou Project, Citta Nuova, Sebenco Climb, Sol 2 and the Tournament. The stalled cells still cover their race
loads and laps; the results screens are the same on every circuit.

A second run of each acceptance cell with the new list, the exit lines:

| Cell (second run) | Outcome | `[metal] pipelines:` exit line |
|---|---|---|
| Single Race Vineta K (`--unlock-all --no-damage`) | PASS, 201 s | 29 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 29 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Single Race Vineta K (`--no-damage`, task 033's cell) | PASS, 197 s | 29 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 29 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Time Trial Vineta K (`--no-damage`) | PASS, 246 s | 32 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 32 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Free Play Vineta K (`--no-damage`) | PASS, 222 s | 32 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 32 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Zone 1 | PASS, 75 s | 23 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 23 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |

No draw of these runs made a pipeline or a depth-stencil state, and none waited for the pre-warm: on this machine's
warm shader cache the 37 pipelines were made on Metal's threads in 2.2 to 5.1 ms (`[metal] pre-warm done: ... (frame
1)`), and the pre-warm took 2.2 to 5.0 ms on the calling thread at start. On a cold cache the pipelines take longer to
make: task 033 measured 46 to 73 ms for its 26, all made by flip 4, thousands of flips before the first race load.

### Not changed by task 033, done in task 042

- (Done in task 042.) The app (`tools/bundle.sh`) did not carry `config/metal_pipelines.txt`, so it made its
  pipelines on first use, which cost its first race after an install (the shader cache is warm afterwards). Since task
  042 the bundle ships the list in `Contents/Resources`, where the backend looks first ("The pre-warm list").

### The Vulkan path, for comparison

`PURE_PERF=log PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=20 python3 tools/campaign_sweep.py single_race vineta_k
--no-damage --shell vulkan` (the Vulkan shell and backend, which have no trace: the framework's `[slow-frame]` line for
each frame over 20 ms, its guest, render and wait split and its stalls): 61 of the race's frames (6250-17540) were over
20 ms. 41 of them are two two-vblank stretches (12510-12527 and 14494-14516; the `[perf]` seconds over them read "game"
43 to 51 fps at speed 100%), the game's own as on Metal; the other 20 are 20 to 31 ms, a pacing sleep that woke late
beside the frame's read-backs (1 to 37 ms through MoltenVK) or a submit that waited (3 to 13 ms). The game's stretches
are the same on both paths; Metal's frames have no read-back of the picture to wait for.

## Texture mapping modes (task 036, 2026-10-07)

The recording is 8.8 MB, 1632 records; `gerec_dump.py` lists its 100 draws `envmap 0,1` and 40 `texmatrix 0`, and
the table checks (906 draws, as the backend's counter says).

The pictures cut after draw #359 (the 360th: the ship's three environment-mapped meshes drawn, the livery not yet)
show the difference plainly (the commands above make them; pictures of the game are not committed). Without
the modes the hull is the environment texture's darkest texels stretched by the meshes' UVs: nearly black, with
bright streaks along the side pods. With them it is a smooth grey shading, light where the hull faces the shade
lights and with a highlight on the canopy, the base the livery is then added to. In numbers, the two cut pictures:

| Compared | Pixels over tol 0 | Over tol 32 | Mean difference |
|---|---|---|---|
| the canopy region (225,177) 30x56, without the modes against with them | 1312 of 1680 | 1073 | 51.7 levels |
| the whole frame, the same (every mapped draw up to #359: the scenery's and the ship's) | 5644 (0.0432) | 2724 (0.0209) | |
| what #357 to #359 change in the ship's area (180,172) 120x100, with the modes (cut 357 against cut 360) | 4643 over tol 8 | | 17.9 levels |

The whole frame replayed from the recording is pixel-identical to the suite's `race_hud` capture (0 pixels over
tol 0), and against PPSSPP's reference its canopy region differs on 452 of 1680 pixels over tol 32 without the modes
and 21 with them, as the suite's captures below.

### Against PPSSPP

`tools/frame_regress.sh` (headless Metal, 2026-10-07, M4 Pro), each scene at tol 32 against its PPSSPP reference,
before (the same build with `PURE_NO_TEXMAP=1`, whose 18 captures are pixel-identical to the build before the task)
and after; the canopy region with `tools/imgdiff.py --region`:

| Scene | Whole frame before | After | Canopy region | Region before | After |
|---|---|---|---|---|---|
| `race_hud` (ref/vineta_k_start.png) | 0.0374 | 0.0262 | (225,177) 30x56 | 0.2690 (452 of 1680) | 0.0125 (21): 98.8% within tol 32 |
| `tt_hud` | 0.0617 | 0.0229 | (225,177) 30x56 | 0.2988 (502) | 0.0333 (56): 96.7% |
| `fp_hud` | 0.0620 | 0.0232 | (225,177) 30x56 | 0.2994 (503) | 0.0333 (56): 96.7% |
| `zone_hud` | 0.0348 | 0.0122 | (212,183) 66x45 | 0.3566 (1059 of 2970) | 0.0141 (42): 98.6% |
| `zone_change` | 0.0649 | 0.0353 | | | |

Each region is a rectangle around the ship's canopy: in race_hud, tt_hud and fp_hud (the same chase camera and ship,
FEISAR) the footprint of draw #359 above, PSP (225,177) 30x56; in zone_hud the Zone ship's dome, (212,183) 66x45.
The 13 frontend scenes have no mapped draws and are unchanged pixel for pixel. What stays over the tolerance in the
race scenes: the AI ships (the grid differs from PPSSPP's), the crowds' alpha-tested texels and one-pixel edges; in
the ship, a few edge pixels. In zone_hud the Zone ship's purple intake at the bottom of the screen differs as it did
before the task (not a mapped draw).

### Metal against Vulkan

Recordings made before task 036 (old patch 0013) hold no texture map state: their draws read as mode 0, and `metal_check.sh`'s race
comparison passes as before (the main checkout's `race_1x.gerec` of 2026-10-06, frame 6016, `--a vulkan --b metal`:
2 pixels over tol 24, PASS). A recording made since carries the modes, which Metal draws and Vulkan does not:

| `PureNative --replay out/race6016.gerec --a vulkan --b metal --frames 6016 --tol 24` | Pixels over tol 24 |
|---|---|
| as built | 2387 (0.0183): the mapped draws |
| with `PURE_NO_TEXMAP=1` | 0 |

(The recording above, made headless through Metal at 480x272, so both replay at 1x; one frame from a cold start, which
two backends start equally.) 0.0183 is under the 0.02 that `metal_check.sh`'s step 3 allows, but by little, and
what it measures there is now this task's difference, not a backend error.

So on a recording made since task 036 the Metal-against-Vulkan comparison is like with like only with
`PURE_NO_TEXMAP=1` (ge_replay hands the environment to both backends; the Vulkan backend has no such switch and draws
mode 0 regardless).

## Mipmaps (task 037, 2026-10-07)

### The check

Headless Metal, 2026-10-07, M4 Pro. "Before" is `PURE_NO_MIPMAPS=1`, whose 18 suite captures and Blue Ridge frame are
pixel-identical to the build before the task (the suite's captures by that build, run from a tree holding its
binary, against this build's with the switch: 0 pixels differ in each).

**Blue Ridge's first race frame** against PPSSPP's (`ref/blue_ridge_hud.png` of the audit's run J, made again for
this task with the command in `ref/README.md`: the PNG and the GE dump came out byte-identical to the hashes there).
Blue Ridge has no route in `config/pad_scripts/`, so the port's frame is the audit's: main_menu.txt + single_race.txt
without their shot steps, plus DOWN at 5380, 5410 and 5440 on TRACK SELECTION, flip 6016, on an empty memory stick.

| Compared with PPSSPP | Before | After |
|---|---|---|
| the whole frame, tol 32 | 0.0392 | 0.0247 |
| the whole frame, tol 16 | 0.0912 | 0.0487 |
| the right grandstand, (300,60) 180x90, tol 32 | 0.1418 | 0.0920 |

(The audit's 0.0534 was before task 036's environment maps.) The crowds, the stands' roofs and the far track are
soft as in PPSSPP's frame; what still differs is the AI grid (other ships than PPSSPP's) and the BLUERIDGE banner,
brighter and wider in PPSSPP's frame.

**The slope rule against the reference.** The same frame with D moved by a constant in slope mode (a throwaway
switch, not kept), against PPSSPP:

| D offset (1/16 levels) | -48 | -32 | -16 | -8 | 0 | +8 | +16 | +32 | +48 |
|---|---|---|---|---|---|---|---|---|---|
| tol 32 | 0.0388 | 0.0374 | 0.0323 | 0.0298 | 0.0247 | 0.0237 | 0.0256 | 0.0352 | 0.0526 |
| tol 16 | 0.0900 | 0.0859 | 0.0675 | 0.0560 | **0.0487** | 0.0549 | 0.0664 | 0.0943 | 0.1268 |

The documented rule (offset 0) is the best at tol 16 and within half a level of the best at tol 32, so it is kept
as the notes give it. Moving the auto mode's D by -32 to +32 changes the frame by at most 0.0007 (its draws cover
little of it).

**The shimmer.** 60 consecutive flips of Blue Ridge's start straight between the grandstands (6340 to 6399, the
ship accelerating from about 110 to 200 km/h with Cross held), each against the next at tol 32:

| Region | Before: mean (min to max) | After |
|---|---|---|
| the whole frame | 0.0845 (0.0650 to 0.1149) | 0.0603 (0.0426 to 0.0926) |
| the right grandstand, (300,60) 180x90 | 0.1902 (0.1625 to 0.2466) | 0.1124 (0.0793 to 0.1887) |
| the left grandstand, (0,60) 180x90 | 0.1248 (0.0975 to 0.1546) | 0.0586 (0.0321 to 0.0862) |
| the track, (0,130) 480x80 | 0.0745 (0.0559 to 0.1007) | 0.0596 (0.0424 to 0.0874) |

The mean absolute change between consecutive frames falls from 7.30 to 5.88 levels over the whole frame (15.24 to
11.11 on the right grandstand).

**The suite** (`tools/frame_regress.sh`, tol 32): race_hud 0.0262 to 0.0149, tt_hud 0.0229 to 0.0112, fp_hud
0.0232 to 0.0116, zone_hud 0.0122 to 0.0121, zone_change 0.0353 to 0.0353 (120 pixels change); the 13 frontend
scenes are unchanged pixel for pixel (none of their textures has levels).

**Decodes.** The race route of the suite (to flip 6046) decodes 646 textures before and after, and after it 596
levels besides (192857 draws sampled levels); Blue Ridge to flip 6020, 612 textures before and after, plus 525
levels. The Time Trial route: 566 textures both, plus 361 levels; Zone: 433 both, plus 52 levels.

### Recordings

Until task 040 (old patch 0017), `record_backend.cpp` recorded the bytes level 0's texels lie in, not the other levels'. A
recording made between tasks 037 and 040 replays with the levels after the first decoded from whatever ge_replay's
guest memory holds there (zero unless an earlier record wrote it), so a replay of a mipmapped draw is not the game's
picture; replay such recordings with `PURE_NO_MIPMAPS=1`. Since task 040 the record backend writes every level a
draw samples, and a recording replays exactly ("The colour test, 16-bit writes and the depth clamp", "Recordings"). Blue Ridge's
frame 6016 recorded through Metal replays 0.0913 off its recorded picture at tol 32 (336 of the frame's mipmapped
draws in PPSSPP's dump have their texture in main memory); recorded and replayed with `PURE_NO_MIPMAPS=1` it is
exact, and `gerec_dump.py --draws` parses the recording (831 draws with levels, listed `levels N auto|slope bias B
slope S`). Older recordings read as one level and replay as before (the main checkout's `race_1x.gerec` parses as
it did).

## The colour test, 16-bit writes and the depth clamp (task 040, 2026-10-07)

### The dither check

**The check.** Race frame 6016 recorded through Metal (the command in "Texture mapping modes", with the build of this
task) and replayed with `--cut` at the end of each billboard round, the target shown with
`PURE_METAL_SHOW_TARGET=0x04154000`, before (`PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1 PURE_NO_DEPTH_CLAMP=1`) and after,
against the target as PPSSPP's dump holds it after each of its rounds (draws 26, 45, 69 and 82, `ppdmp.py tex`):

| Picture | Pixels that are 565 values | Flat 4x4 blocks ordered as the round's matrix | The rule applied to the before picture |
|---|---|---|---|
| PPSSPP, rounds 1 to 4 | 1.0000 in each | 0.9943 (874 blocks), 1.0 (921), 0.1171 (222: a vertical gradient), 1.0 (1024) | |
| port before, rounds 1 to 4 (cut 42, 72, 84, 98) | 0.5560, 0.0721, 0.0000, 0.9963 | no block with any dither | |
| port after, rounds 1 to 4 | 1.0000 in each | 1.0 (710 blocks), 1.0 (831), 1.0 (936), 1.0 (1009) | 1.0000, 1.0000, 1.0000, 0.9998 of the pixels |

"Flat 4x4 blocks" are the matrix-aligned blocks whose 5-, 6- and 5-bit values span at most two steps (four in green)
and are not all equal, where a flat colour shows its dither; "ordered as the matrix" means that in every channel no
pixel with a larger offset has a smaller value, which an ordered dither by that matrix always gives (PPSSPP's third
round is a gradient across the blocks, which the measure does not allow for). The last column applies the PSP's rule
(the offset, the clamp, the top bits) to the before picture's 8-bit pixels and compares with the after picture: exact
wherever the last write to a pixel did not blend with an earlier one. The two runs show different adverts at that
moment (the billboards cycle through them: PPSSPP's first round is the red PIRANHA advert, the port's an orange one),
so their pixels are not compared one to one.

### What changed on the screen

Headless Metal, 2026-10-07, M4 Pro, against PPSSPP at tol 32 (`tools/frame_regress.sh`, "before" the same build with
the three switches, whose 18 captures are pixel-identical to the build before the task):

| Scene | Before | After | Pixels changed (tol 0) | By |
|---|---|---|---|---|
| race_hud | 0.014874 (1942) | 0.014828 (1936) | 723 | the colour test 640 (a lamp's glow, (307,107) 26x34), the billboard 83 |
| tt_hud | 0.011221 (1465) | 0.011213 (1464) | 377 | the billboards |
| fp_hud | 0.011566 (1510) | 0.011336 (1480) | 413 | the billboards |
| the other 15 scenes | | unchanged | 0 | |

| Region against PPSSPP | tol 32 before | after | tol 16 before | after |
|---|---|---|---|---|
| race_hud, the lamp's glow (307,107) 26x34 | 0.0328 (29 of 884) | 0.0260 (23) | 0.2285 (202) | 0.1765 (156) |
| race_hud, the billboard screen (201,126) 16x8 (draw #42's footprint, 127 pixels) | 0.8828 (113 of 128) | 0.8828 (113) | 0.9063 | 0.9063 |
| tt_hud, the billboard screen (195,114) 29x29 | 0.4245 (357 of 841) | 0.4221 (355) | 0.4828 | 0.4828 |
| fp_hud, the billboard screen (195,114) 29x29 | 0.4269 (359 of 841) | 0.3912 (329) | 0.4816 | 0.4828 |

The billboard screens show other adverts than PPSSPP's frames do (a different moment of the adverts' cycle), which is
nearly all of their difference; what the task changes there is the dither and the 16-bit steps of the content. The
colour test's effect is the bloom: the glows' black texels no longer write the bloom mask's stencil 255, so the bloom
no longer spreads the scene under them.

### Recordings

Task 040 (old patch 0017, the record format's part now in 0004-ge-backend-and-shell-seams) also makes `RecordBackend::submit` record the texels of every mip level a draw samples (levels 1 to
`level_count` - 1 when the minification filter's bit 2 is on), each from its own address at its own size. Race frame
6016 recorded through Metal now replays into Metal exactly without `PURE_NO_MIPMAPS` (0 pixels over tol 0; the
recording is 8.9 MB, 611 Memory records against 283), where a recording of the same frame made with task 037's
record backend replays 0.0119 off at tol 0. Blue Ridge's first race frame (the audit's route, flip 6016), the
frame task 037 found 0.0913 off at tol 32, recorded the same way replays exactly too (0 pixels over tol 0, 974 draws);
against PPSSPP it scores 0.024732 at tol 32 both before and after this task (27 pixels change, none by more than 8:
its billboards).

A Draw record ends with the colour test, dithering and CLIPENABLE (`kPixelBytes`, 31 bytes); a Draw that ends before
them reads as no colour test, no dithering and CLIPENABLE off, so the older recordings replay as before. `gerec_dump.py`
lists `ctest FUNCTION REFERENCE/MASK`, `dither ROWS` and `noclip`.

On a recording made since task 040, Metal against Vulkan (`PureNative --replay ... --a vulkan --b metal --frames
6016 --tol 24`, race frame 6016): 5149 pixels over tol 24 as built (the texture map modes and mip levels, which the
Vulkan backend does not draw either), 3 with `PURE_NO_TEXMAP=1 PURE_NO_MIPMAPS=1` (with `PURE_NO_COLOR_TEST=1
PURE_NO_DITHER=1` as well, still 3), 2 with `PURE_NO_DEPTH_CLAMP=1` too, task 025's figure. The one pixel the depth
clamp moves in that configuration, (146,124), is a depth tie between two draws that the clamp's depth arithmetic
(z times the z scale plus w times the offset, over 65535) rounds the other way from the viewport's; as built, no pixel
of the frame or of the suite's 18 scenes moves with the clamp.

The pre-warm list (`config/metal_pipelines.txt`) had none of the new keys: a race run made 6 render pipelines on
first use (four `sixteen=1`, two `color_test=1`), 1.2 ms at its first race frame and 0.24 ms later on this machine
(`PURE_METAL_TRACE`). Task 042 refreshed the list with them ("The pre-warm list").

## What was not done yet, as the doc had it

| Task | What |
|---|---|
| 027 (landed) | what the Metal shell leaves out ("The Metal shell"): frame interpolation, the Fill aspect, the touch controls, the performance overlay, and the menu's resolution, texture filter and texture-pack rows |
| enhancements | drawing above 480x272 (an internal scale above 1, which D-002 leaves for after the native picture) and texture packs, both the Vulkan renderer's today |

## The 3D check (task 024)

### Choosing the frame

The brief asked for a TEAM SELECTION frame with the ship model lit and no bloom or stencil draw in the list. There is
none: no frontend frame has a lit draw at all. The route run on Metal with `PURE_METAL_LOG=1` to frame 5760 (151590
draws, a line each, `lit`, `fog` and `cull` among the tags) gives:

| Frames | Screen | Draws a frame | Lit | Fogged | Stencil | Bloom targets | Depth-tested |
|---|---|---|---|---|---|---|---|
| 1-5707 | boot, language, title, profile, menus, CLASS, LEAGUE, TRACK, TEAM, loading | up to 81 | 0 | 0 | 0 | 0 | 2 a frame at 5-123 (boot), 13 at 5702-5706 (loading) |
| 5503-5701 | TEAM SELECTION (within the line above) | 59-81 while it comes in, 65-69 from 5531 | 0 | 0 | 0 | 0 | 0 |
| 5708 on | the race | 682-684 | 220-261 | 434-436 | 519 | 5 | 672-674 |

The TEAM screen's rotating ship is ten textured quads (pre-drawn outline pictures, 256x128 CLUT8 textures in VRAM),
not a lit model. Every TEAM draw but the clear is transformed, under an orthographic projection, with linear
filtering; none is lit, fogged, depth-tested or stencilled. So the TEAM frame checks the transformed path (matrices,
the viewport, the transformed sprites, 26 sprite draws, texture coordinates), and lighting and fog are checked on the
race up to its first stencil draw instead. 5650 is the middle of the TEAM screen (5503-5701 in the survey run), so a
run that drifts by some tens of frames still lands on it; its recording holds 66 draws a frame, 131 of the two
frames' 133 transformed.

### Numbers (2026-10-06, M4 Pro)

| Comparison | Result |
|---|---|
| `team.gerec` (1x) frames 5650 and 5651, vulkan against metal | 0.000000 at tol 24 (0 pixels; 0 at tol 0 too): PASS |
| the same frames recorded at 2x | 0.051877 at tol 24 (6773 pixels, glyph edges) |
| `race_1x.gerec` frame 6016, `--first-diff --tol 24` | first difference at draw 394 of 906, the stencil-gated darkening quad (025's), in 10 steps. After draw 393: 0 pixels over tol 1, 36 one level off |
| what draws 1-393 hold | 58 lit draws (45 into the display target), 360 fogged (275 into it), 353 culled (266 counter-clockwise into the display target) |
| race frame 6016 whole, against Vulkan at 1x | 0.3246 at tol 24 (42380 pixels): the shadow darkening over the whole screen, the bloom, and what follows from them |
| `race_warm.gerec` (2x) frame 6016, `--first-diff --tol 24` | first difference at draw 40 (11 pixels): a fogged, alpha-tested (GREATER 0x7F), bilinear-textured strip that writes the stencil, its alpha-test edge moved by the 2x-to-1x reduction. Bisected to the first draw past 5% of the pixels instead: draw 394 |
| race frame 6016 whole, against Vulkan at 2x | 0.3768 at tol 24 |
| race frame 6016 against PPSSPP (`tools/frame_regress.sh --backend metal --only race_hud`) | 0.2978 at tol 32, limit 0.10 (task 023: 0.2977; Vulkan 0.0672): FAIL, not yet a pass condition. The red is the track, the ships and the stands under the stencil-gated darkening quad, which without the stencil dims the whole screen, and the missing bloom: both 025's, and large enough to hide what lighting changed |

That the race comparison would catch a wrong rule: the 1x recording cut after draw 393 of frame 6016, replayed into
Vulkan, and into Metal alone with a switch (pixels over tol 24 against Vulkan's picture):

| Metal | Over tol 24 | Over tol 8 |
|---|---|---|
| as built | 0 | 0 |
| `PURE_NO_LIGHTING` (vertex colour, no fog) | 1936 (0.0148) | 3352 |
| `PURE_NO_FOG` | 555 (0.0043) | 1049 |
| `PURE_NO_CULL` (most back faces are hidden by the depth test anyway) | 68 (0.0005) | 81 |
| the winding reversed (a throwaway build) | 63574 (0.4869); `--first-diff` stops at draw 41 | 64474 |

What the race lights with (frames 6008-6016): lit draws whose vertex colour stands in for all three material colours
with no light on (emissive plus the global ambient times the vertex colour; 1944 draws over the nine frames), and
lit draws with the material colours and two directional diffuse lights (523); fog with four settings (end 1400 and
scale 1/1230 towards the colour register 0xCCA38E (0xBBGGRR) or black, end 1270 and scale 1/770 towards 0xEDFCFF,
end 5001 and scale 1 towards grey). No point or spot light, no specular, no powered diffuse, no reversed normals, no separate specular: those
are ported from `ge.vert` as they are and checked by nothing but the port.

In the replays Metal takes 4 to 6 ms a race frame and Vulkan 5 to 10 (each including its capture).

## The race check (task 025)

### Numbers (2026-10-06, M4 Pro)

| Comparison | Result |
|---|---|
| `race_1x.gerec` frames 6008-6016, vulkan against metal | each within 2 pixels over tol 24 (0 to 0.000015): PASS |
| frame 6016, pixels over tol 0, 1, 4, 8, 16, 24 | 553, 77, 24, 18, 3, 2 (of 130560) |
| frame 6016 after draw 393 (`--cut 393`), task 024's first stencil draw | 0 pixels over tol 24 |
| frame 6016 with task 024's backend | 0.3246 at tol 24 (42380 pixels): no shadows, the darkening over the whole screen, no bloom |
| `--first-diff --tol 24` (no fraction) | draw 508 of 864, one pixel: an alpha-tested crowd strip (below) |
| `race_warm.gerec` (2x) frames 6014, 6015, 6016 | 0.0777, 0.0788, 0.0804 at tol 24 (task 024: 0.3768 for 6016): edges and the crowds' texture detail moved by the 2x-to-1x reduction, accumulating from the first alpha-tested draws (`--first-diff --max-frac 0.02` passes 2% at draw 261 of 906, an opaque strip) |
| race frame 6016 against PPSSPP (`tools/frame_regress.sh --backend metal --only race_hud`) | 0.0379 at tol 32 (4954 pixels), limit 0.10: PASS, twice (the verify run and an earlier one). Task 024: 0.2978; the Vulkan backend 0.0672 (runs 0.063 to 0.086, the AI grid varies) |

Metal draws the race with the effects in: shadows under the ships, the bloom on the light strips and the screens, the
lens flare. Against PPSSPP, what stays over tol 32 in race_hud is the AI ships (the grid differs from run to run),
the crowds' alpha-tested texels, parts of the player's ship and one-pixel edges (`imgdiff.py --out`). The pictures of
frame 6016 after the whole frame differ in three places, all small, which item 5 of the brief asked to classify:

| Pixels | Levels | First draw (ge_replay numbering) | What it is | Whose |
|---|---|---|---|---|
| column 0, rows 244-263 (20) | 5-11 | 837 (gerec_dump #836): the HUD's LAP panel, a transformed sprite from x -2 to 12, blended add(SA, 1-SA) | the HUD is drawn with a GE viewport whose offsets are 2048 - 1807 and 2048 - 1911, one pixel right and down of the world's (1808, 1912), so on the screen it covers x -1 to 13. The Vulkan backend makes the GE viewport its `VkViewport`, which then starts at x 1, and clips everything left of it: column 0 keeps the scene, 9 to 11 levels brighter. The GE clips x and y only at the scissor (0,0)-(479,271) (it clips on z = -w and drops triangles outside its 4096-pixel space: the coverage rules of `tools/ppsspp/ppdmp.py cover`, docs/ge-effects.md task 010) and draws column 0, as Metal does. PPSSPP's dump of frame 7155 draws the same sprite (its #843 and #844, x -2 to 12) | a Vulkan difference against the GE's rule; not matched. Both pictures after the draw: `--frames 6016 --cut 837 --out DIR` (in the task's run, rows 244-263 of column 0 are 149-162 in Vulkan's, the scene unchanged, and 142-158 in Metal's, the panel over it) |
| (342,131), (464,115), (439,125) | 20-36 | 508, and later crowd strips | crowd strips alpha-tested GREATER 0x7F on bilinear-filtered CLUT4 texels: a texel alpha at the threshold falls on either side in the two backends (their texture coordinates and filtering are computed by different instruction sequences), so one pixel passes in one and not the other | neither: rounding at a test's threshold |
| 24 pixels over tol 4 in all, the two rows above included | 5 or less elsewhere | from draw 299 on | interpolation and blending rounding | neither |

Nothing else differs by more than 4 levels, so nothing in the race is drawn by another rule in Metal than in Vulkan
except the viewport clipping above. The 2x recording adds no other finding: its differences are the reduction's.

### The lens flare

The depth write-back is asked for at every race frame's SIGNAL 0x200 (339 in the route, frames 5707-6045) and
writes the back buffer's z into 0x04110000. The race route holds Cross from frame 6100, so the player's ship runs
along the first straight's left wall, and at frame 6690 the sun is behind the left pillar (docs/ge-effects.md, the
depth write-back). Two windowed runs of the route to frame 6700 with `PURE_TRACE_DEPTH_READBACK=1`, one per backend,
put the ship in the same place and give:

| Frame | Metal: z written, mean luma around the sun | Vulkan: the same | Task 019 (Vulkan) |
|---|---|---|---|
| 6016, open sky: the flare drawn | 23-13433, 225.8 | 23-13443, 225.9 | 225.7 |
| 6690, sun behind the pillar: no flare | 22-13415, 111.2 | 22-13431, 111.6 | 105.2 with the write-back, 176.5 without |

(Mean luma 0.299 R + 0.587 G + 0.114 B over PSP (100,40) 90x100, the region task 019 measured.) So the game's
4x4 depth test sees the pillar in Metal's depth as in Vulkan's, and drops the flare.

### Cost

Over the race route to frame 6046 (339 race frames), counted by the backend's exit line:

| Run | GPU waits (ms) | Frame write-backs: stored/asked, waited | Depth write-backs: stored/asked, waited | Stencil copies |
|---|---|---|---|---|
| Vulkan shell (`frame_regress.sh --backend metal --only race_hud`) | 6383 (3134) | 6043/6046, 0 ms (the hand-over's read-back reused) | 339/339, 236 ms (0.70 ms each) | 339 |
| Vulkan shell, `MTL_DEBUG_LAYER=1` (the acceptance run) | 6383 (3325) | 6043/6046, 0 ms | 339/339, 283 ms (0.83 ms) | 339 |
| Metal shell (`PURE_SHELL=metal`, `PURE_PERF=log`) | 353 (254) | 6043/6046, 46 ms in 14 waits, the rest already drawn | 339/339, 209 ms (0.62 ms) | 339 |

So a race frame waits for the GPU once, at its SIGNAL, for about 0.6 to 0.8 ms (the flare's depth; in the drive runs
above, Metal's write-back took 0.8 to 0.9 ms at frames 6016, 6400 and 6600 and the Vulkan backend's 1.0 to 1.4 ms),
plus, under the Vulkan shell, the hand-over's read-back at the flip (0.48 ms on average). Under the Metal shell the
race runs at 59.9 to 60.0 fps, frame 16.7 ms (guest 2.1 to 2.6, render 3.2 to 3.4, pacing wait 10.7 to 11.3 ms). None
of the runs printed a `[metal] ... not implemented` line, and the one with Metal's API validation (`Metal API
Validation Enabled`) reached frame 6046 with no validation error. The race's 570 to 606 block transfers (the number
varies from run to run) come from main memory, so none is written back.

## Verify numbers

`tools/build.sh profile && tools/frame_regress.sh --backend metal --only lang,title,profile` (2026-10-06, M4 Pro),
against the PPSSPP references at the suite's thresholds, beside the Vulkan backend's documented values:

| Scene | Tol | Limit | Metal | Pixels over tol | Vulkan (2x) |
|---|---|---|---|---|---|
| `lang` | 24 | 0.07 | 0.0002 | 22: the blinking cursor after ENGLISH, shown in our frame and not in PPSSPP's | 0.0544 |
| `title` | 24 | 0.05 | 0.0002 | 31: the blinking cursor after PRESS START BUTTON, shown in PPSSPP's frame and not in ours | 0.0302 |
| `profile` | 24 | 0.07 | 0.0000 | 0 | 0.0543 |

Every other pixel is within 24 of PPSSPP's; most of the rest of the difference is 1 or 2 levels (`lang`: 117458
pixels at 1-2, 9474 at 3-8, 3187 at 9-24: the paused movie picture behind the page, a texture from main memory,
is 254 where PPSSPP's is 253; `title`: 124915 pixels equal; `profile`: 123411 equal, its white background 255 in
both). The backend's own `capture_frame` of `lang` (`PURE_SCREENSHOT_EVERY`) is identical to the suite's window
shot reduced to 480x272.

Outside the Verify line, for the record (not acceptance items): `main_menu` (2D as well) scores 0.0106 against its
limit of 0.05 (Vulkan 0.0331), and `race_hud` 0.2977 against 0.10 (Vulkan 0.0672): the capture shows the track,
the stands, the ships and the HUD in place, without lighting, the stencil-volume shadows and the bloom, which are
tasks 024 and 025. The race route runs to its end on Metal (frame 6046).

The frontend route (2130 flips, windowed) takes 72 s with either backend: the frames are paced, not drawn slowly.
The Metal backend drew 19853 draws in 2126 passes, decoded 347 textures, read no target as a texture and made no
copy, and waited for the GPU 2128 times (the hand-over to the window, once a frame) for 892 ms in all, 0.42 ms a
frame. The first shader compile on a machine takes about 0.7 s, later ones 0.5 to 30 ms.

With the Metal sources built in, `tools/frame_regress.sh` (Vulkan) passes 5/5 with the fractions it had before
(0.0544, 0.0302, 0.0543, 0.0331, 0.0672), and its five captures are pixel-identical to the main checkout's run of
2026-10-06 03:35.

### Task 024

`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal --only
lang,title,profile` (2026-10-06, M4 Pro): metal_check PASS (6 s with its recordings made; team frames 0.000000 at
tol 24, the race bisected to draw 394 at 1x and to draw 40 at 2x), and the three frontend scenes at their task 023
fractions: `lang` 0.0002, `title` 0.0002, `profile` 0.0000. `tools/frame_regress.sh` (Vulkan): 5/5 at the fractions it
had (0.0544, 0.0302, 0.0543, 0.0331, 0.0672), its five captures pixel-identical to the main checkout's run of
2026-10-06 07:30-07:36.

### Task 025

`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal` (2026-10-06, M4
Pro): metal_check PASS in 5 s with its recordings present (team frames 0.000000 at tol 24; race_1x frame 6016
0.000015 at tol 24, 2 pixels, PASS; bisected for the record to draw 508 at 1x and draw 40 at 2x), and the suite 5/5:
`lang` 0.0002, `title` 0.0002, `profile` 0.0000, `main_menu` 0.0106 (tasks 023 and 024's fractions) and `race_hud`
0.0379 (limit 0.10), in 7m 12s. In those runs the backend stored the frame in guest memory at 2127 of 2130 flips
(frontend), 4727 of 4730 (main menu) and 6043 of 6046 (race) with no wait of its own, and waited for the GPU 2128,
4728 and 6383 times (1024, 2195 and 3149 ms), as many times as before task 025 plus the race's 339 depth write-backs
(250 ms). `tools/frame_regress.sh` (Vulkan): 5/5 at 0.0544, 0.0302, 0.0543, 0.0331 and
0.0673 (race_hud's AI grid varies; 0.0672 before), in 7m 8s, its four frontend captures pixel-identical to the main
checkout's run of 2026-10-06 07:54. The race route on Metal ran to frame 6046 with `MTL_DEBUG_LAYER=1` (Metal API
validation on) without a validation error or a `[metal] ... not implemented` line ("Cost" above). Beyond the Verify
line, `tools/frame_regress.sh --shell metal --backend metal` (no Vulkan at all, M6's exit check) passes 5/5 with the
same five fractions (0.0002, 0.0002, 0.0000, 0.0106, 0.0379) in 7m 10s.

### Task 036

`tools/verify_task.sh 036` (`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh && python3
tools/imgdiff.py out/regress/shots/race_hud.png ref/vineta_k_start.png --max-frac 0.032 --tol 32`, 2026-10-07, M4
Pro): 13 patches reproduce the vendor tree; the suite passes 18/18 headless in 24 s, the 13 frontend scenes at their
fractions and the race scenes at race_hud 0.0262, tt_hud 0.0229, fp_hud 0.0232, zone_hud 0.0122 and zone_change
0.0353 (the table's metal column, from before the task: 0.0379, 0.0617, 0.0620, 0.0348 and 0.0649; the suite flags
tt_hud and fp_hud as moved by more than 0.03); race_hud 0.026180 at tol 32 against the Verify's 0.032: PASS. Beyond
the Verify line: `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18, every scene within 0.0005 of its
vulkan column (19m 49s); `tools/hud_check.sh` (the Metal shell) 61 of 61 shots with the HUD; `PURE_NO_TEXMAP=1`
gives the 18 captures of the build before the task pixel for pixel; the framework's list of ignored GE commands is
63 long in every run (0xC0 and 0xC1 left it); the main checkout's `race_1x.gerec` of 2026-10-06 replays Vulkan
against Metal as before (frame 6016, 2 pixels over tol 24). "Texture mapping modes" has the draw-level check and the
canopy regions.

### Task 037

`tools/verify_task.sh 037` (`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh &&
tools/hud_check.sh --shell headless`, 2026-10-07, M4 Pro): 14 patches reproduce the vendor tree; the suite passes
18/18 headless in 25 s, the 13 frontend scenes at their fractions and pixel for pixel as before, the race scenes at
race_hud 0.0149, tt_hud 0.0112, fp_hud 0.0116, zone_hud 0.0121 and zone_change 0.0353 (the metal column: 0.0262,
0.0229, 0.0232, 0.0122, 0.0353); hud_check 61 of 61 shots with the HUD. Beyond the Verify line:
`tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18, every scene within 0.0005 of its vulkan column
(19m 48s); `tools/hud_check.sh` (the Metal shell, windowed) 61 of 61; `PURE_NO_MIPMAPS=1` gives the 18 captures of the build before the task pixel for pixel; the framework's
list of ignored GE commands is 40 long in every run (63 before: TEXADDR1 to 7, TEXBUFWIDTH1 to 7, TEXSIZE1 to 7,
TEXLEVEL and TEXLODSLOPE left it); no run refused a level or printed a new `not emulated` line. "Mipmaps" has the
Blue Ridge frame, the shimmer sequence and the decode counts.

### Task 040

`tools/verify_task.sh 040` (`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh`, 2026-10-07,
M4 Pro): 16 patches reproduce the vendor tree (old 0001 to 0015 and 0017; 0016 was reserved); the suite passes 18/18
headless in 24 s, the 15 other scenes pixel for pixel as before (Zone's colour-tested draws change none of their pixels),
race_hud 0.0148 (0.0149 before), tt_hud 0.0112 (0.0112), fp_hud 0.0113 (0.0116). Beyond the Verify line:
`tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18, every scene within 0.0005 of its vulkan column
(19m 47s); `tools/hud_check.sh --shell headless` 61 of 61 shots with the HUD; `PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1
PURE_NO_DEPTH_CLAMP=1` gives the 18 captures of the build before the task pixel for pixel, and each feature alone
moves only the pixels "What changed on the screen" names (the depth clamp none); the framework's list of ignored GE
commands is 30 long in every run (40 before: 0x1C, 0x20, 0x27, 0xD8 to 0xDA and 0xE2 to 0xE5 left it); no run printed
a `not emulated` line. "The colour test, 16-bit writes and the depth clamp" has the dither check and the regions.

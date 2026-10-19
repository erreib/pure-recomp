# Fidelity

D-009 asks for the port as close to 1:1 with the original as possible before any enhancement. This doc says where
the port stands against the original today, difference by difference, and how that is measured. The fidelity audit
(task 035, 2026-10-06) found the differences and the M8 tasks after it (036 to 048) fixed or explained them; their
report, every table and finding with its date, is [docs/history/fidelity.md](history/fidelity.md).

## How it is measured

| Tool | What it answers | Where |
|---|---|---|
| `tools/scorecard.py` | the standing answer: six categories (pictures, trajectories, timing, audio, saves, coverage) graded `faithful`, `close` or `differs` against PPSSPP or the game's own facts | docs/scorecard.md (the latest `--full` run); "The accuracy scorecard" below |
| `tools/frame_regress.sh` | 18 scenes against PPSSPP's captures: every menu of the five modes and the first race frames | docs/verification.md "Frame regression suite" |
| `tools/fidelity_audit.py` | the campaign matrix: 46 cells (every circuit in Single Race at Vector and Phantom and in Time Trial, Free Play and the tournaments by league, Zone 1 to 4), headless, collecting every halt, stub, unemulated GE state, warning, two-vblank stretch and audio figure; about 4 hours | README.md, the tools table; [the matrix of 2026-10-06](history/fidelity.md#the-campaign-matrix-item-2) |
| `tools/ai_seed_check.sh` | the scorecard's trajectories with PPSSPP's race clock pinned (difference 13) | docs/developing.md |
| `tools/sas_reverb_check.sh` | the reverb's tail at a pause against PPSSPP's (difference 12) | "The SAS reverb check" below |
| `tools/save_interchange.sh` | saves both ways between the port and PPSSPP (difference 5) | "The save interchange check" below |
| `tools/vfpu_probe.py`, `tools/vfpu_model.py` | the VFPU's rounding at the game's own instructions (difference 13) | "The VFPU dot-product check" below |

## What matches

The audit's list of what it found the same as the original (2026-10-06), still true:

- **No halt anywhere.** No cell of the matrix printed `[hle-stub]`, `unsupported` or a `Runtime stopped` of its own,
  and no `[metal] ... not emulated` or `not implemented` line. The 26 imports without an implementation (the
  multiplayer, the download menu's network side, game sharing) were never called.
- **The frontend, pixel for pixel.** Every menu compared differs from PPSSPP in 0 pixels at tol 24 on the Metal
  backend; the HUD (labels, digits, bars) matches on every circuit's first race frame; the pause menu, the results
  panel and Zone's end panel have PPSSPP's layout and fonts.
- **The game's logic and timing.** The same follower drove Vineta K in PPSSPP and in the port to laps within 1.5 s and
  the same 45 contacts; Zone 1 with Cross held ends on both at TOTAL ZONES CLEAR 6 with scores one apart; the race
  start runs the same 57 frames at two vblanks; the two-vblank stretches are the game's own (below).
- **Saves round-trip**, and since task 045 in the PSP's own format (difference 5).
- **Audio keeps going**: every race's mix and effects active in every second, the music in 97 to 100% of them (the
  gaps are loads and the game's own track changes, which PPSSPP has too).
- **Every circuit reachable** in every mode and class (`PURE_TEST_UNLOCK_ALL`, or the game's own unlock code below);
  where the test driver fails (Sinucit's fork, Manor Top, Karbonis at Phantom) the game itself behaves.

## The differences

The audit's numbering, kept by the tasks, the scorecard and the code comments that cite "difference N". "Fixed"
means the port now does what the original does, by the measure in the history; the Vulkan backend, the portable path
(D-008), does not draw the GE features of 1, 2, 10 and 11.

| # | What a player saw | State | Where the fix lives | Record |
|---|---|---|---|---|
| 1 | Reflective surfaces wrong: the ship's hull and canopy, glass buildings, shiny roofs showed the reflection texture stretched over the model | fixed (task 036, 2026-10-07): TEXMAPMODE and TEXSHADELS carried and drawn by the GE's rules; the Vulkan renderer too since task 057 (patch 0011-vulkan-texture-mapping). Not checked by a capture: TEXMAPMODE 1 (Vineta K's 40 projected draws are clipped in the suite's frames) | patch 0002-ge-state-commands (task 036); docs/metal-backend.md "Texture mapping modes" | [the table](history/fidelity.md#the-differences) |
| 2 | Distant textures sharp and shimmering | fixed (task 037): every mip level uploaded and sampled at the level the GE's rule picks; the Vulkan renderer too since task 058 (patch 0012-vulkan-mipmaps) | patch 0002-ge-state-commands (task 037); docs/metal-backend.md "Mipmaps" | [the table](history/fidelity.md#the-differences) |
| 3 | Sebenco Climb's wall and Sinucit's overhang about 1.5 times brighter | not a difference (task 038): the game's weather mist in another phase, from its own state; the wall is drawn exactly as on the PSP | none | [Difference 3](history/fidelity.md#difference-3-the-weather-mist-task-038-2026-10-07) |
| 4 | A second profile overwrote the first; LOAD offered no choice; no save dialog | fixed (task 039): the save list, drawn over the game as the PSP's dialog; the input script answers it with `save ANSWER`. Left: the interface's font and button symbols, no fade, mode 7 lists only this game's folders | patch 0007-savedata-list-and-no-key-mode (task 039); docs/savedata.md "What the dialog shows" | [Saves and records](history/fidelity.md#saves-and-records-item-5) |
| 5 | A PSP's or PPSSPP's save did not load, and a port save would not load on a PSP | fixed (task 045): saves without a game key written and checked in the save-data utility's mode 1, as a PSP does | patch 0007-savedata-list-and-no-key-mode (task 045); docs/savedata.md "The PSP's format" | [Saves and records](history/fidelity.md#saves-and-records-item-5) |
| 6 | Loading screens before a race shorter than on the PSP (about 0.3 s of game time against 1.5 s in PPSSPP) | accepted (Erik, D-011): the loads stay the port's own | none; the scorecard grades it `accepted (D-011)` | [the table](history/fidelity.md#the-differences) |
| 7 | Freezes of 0.1 to 0.3 s with a gap in the sound | not a player's (task 041): the headless test runs' (host contention, once a cold-cache pipeline compile); 16 minutes of windowed race had no frame of 100 ms | none | [Differences 7 to 9](history/fidelity.md#differences-7-to-9-checked-in-a-window-and-against-ppsspps-audio-task-041-2026-10-07) |
| 8 | The race music stops for about 2 s at a track change; Free Play's 3.9 s at the finish | the game's own (task 041): the track's own fade and silence, and Free Play's pause menu; PPSSPP plays the same samples | none | [Differences 7 to 9](history/fidelity.md#differences-7-to-9-checked-in-a-window-and-against-ppsspps-audio-task-041-2026-10-07) |
| 9 | The attract demo's sound clips | the game's own (task 041): PPSSPP's demos clip as much | none | [Differences 7 to 9](history/fidelity.md#differences-7-to-9-checked-in-a-window-and-against-ppsspps-audio-task-041-2026-10-07) |
| 10 | Pure black pixels of a few draws drawn where the PSP drops them | fixed (task 040): the colour test; the Vulkan renderer too since task 059 (patch 0013-vulkan-colortest-depthclamp) | patch 0002-ge-state-commands (task 040); docs/metal-backend.md "The colour test, 16-bit writes and the depth clamp" | [the table](history/fidelity.md#the-differences) |
| 11 | No dithering on 16-bit targets; no depth clamp | fixed (task 040): 16-bit targets keep the format's bits with the GE's dither; CLIPENABLE's clamp and MINZ/MAXZ applied (no pixel of the game moves with the clamp); the Vulkan renderer applies the clamp too since task 059 (patch 0013-vulkan-colortest-depthclamp) and the 16-bit writes with the dither since task 060 (patch 0014-vulkan-16bit-dither) | patch 0002-ge-state-commands (task 040); the same section | [the table](history/fidelity.md#the-differences) |
| 12 | The race's effects had no reverb: they stopped dead at a pause where the PSP's ring on | fixed (task 043): the SPU reverberator on the voices' effect sends, its two constants fitted to PPSSPP's output (D-010) | patch 0008-sas-reverb (task 043); `PURE_NO_REVERB=1` turns it off | [Difference 12](history/fidelity.md#difference-12-the-sas-reverb-task-043-2026-10-07) |
| 13 | The AI ships run another race than in PPSSPP | explained (task 046): the race's random numbers start from clock readings at TEAM SELECTION and the race runs on measured frame times, which differ between any two runs, also on a PSP. With PPSSPP's clock pinned (`PURE_TEST_RACE_CLOCK`) all 12 player paths are faithful; the AI rows still part, from 1-ulp float differences the AI amplifies (below) | the VFPU rounding of tasks 047 and 048: patch 0009-vfpu-rounding (D-013) | [Difference 13](history/fidelity.md#difference-13-the-ais-start-task-046-2026-10-07) |
| 14 | On Karbonis the player's ship scrapes a wall and comes out 1 to 3 km/h faster than in PPSSPP | explained (task 046): the time step, not the contact response; with PPSSPP's frame times the path stays within 0.01 m | none | [Difference 14](history/fidelity.md#difference-14-the-karbonis-contact-task-046-2026-10-07) |
| 15 | (Erik's playtest, 2026-10-09, the 2026-10-07 app) The track-side screens on Vineta K's pillars show flat colour with vertical bars, not an advert's picture | fixed (task 063, 2026-10-10): each advert is drawn into a 128x128 16-bit target (docs/ge-effects.md) and the screen samples it with v scale -1 and the REPEAT wrap; both backends now wrap a target texture's own coordinates by the GE's wrap mode before placing them in the target (REPEAT takes -v modulo 1), where they had clamped -v at the target's edge and stretched the advert's first row into bars. PPSSPP shows the picture (the first check, 2026-10-10, compared the pillar strips, an ordinary texture PPSSPP draws as bars too); `tools/billboard_check.sh` measures the screen: the mean luminance step down it 2.0 before, 18.7 after on Metal headless, 18.9 in the Vulkan window, 25.6 on PPSSPP's | `src/gpu/shaders/ge.metal` (`place_in_target`) and `src/gpu/metal_draw.mm` (task 063); patch 0015-vulkan-fb-texture-wrap; docs/metal-backend.md "Textures" | this row; docs/tasks/063-fb-texture-wrap.md |

### Difference 13, where it stopped

The port's default rounding is the PSP's documented and measured rule for every VFPU kind the game runs (dot
products, the cross product's lanes, the horizontal sums; D-013), and a test mode (`PURE_VFPU_DOT=ppsspp`, implied by
`PURE_TEST_RACE_CLOCK`) rounds as PPSSPP's JIT does, so the scorecard's AI rows measure the port rather than
PPSSPP's compiler. Under the test mode the port matches PPSSPP on every sampled result of every sampled kind (3.9
million results, 18 sample sets), the player's paths are faithful on 11 of 12 circuits (Karbonis parts by
millimetres after a 7 s wall scrape) and the AI rows stay `differs` on nine circuits: a faithful AI row would need the
port equal to PPSSPP's JIT on every float operation of the race, the bit-exact chase against an emulator the plan
rules out. The rounding work stopped there (2026-10-07). The next suspect, if anyone resumes it, is subnormal
flushing (PPSSPP's JIT flushes subnormals; the port's native code does not).

### Not differences, though they looked like ones

- **The two-vblank stretches** (task 033; below): the game's own, and PPSSPP's.
- **Zone's pace**: a PPSSPP run with a capture every vblank seemed to count zones three times as fast; a run with no
  capture during the race ends exactly as the port does. PPSSPP's captures moved its timing.
- **The movie channel's two 1.9 s underruns at boot**: a reserved channel the game sends nothing for a while, silent
  on a PSP too.
- **The follower's stalls** (Sinucit's fork, Manor Top, Karbonis at Phantom, a wedge on Chenghou Project): the game
  puts the ship back or holds it as it should; the test driver cannot get past (docs/tracks.md, "Stalls").

## The two-vblank stretches: the game's own rule

Every race runs 0.4 to 1.3 s at a time at two vblanks a frame (30 fps). The end-of-frame routine (docs/timing.md,
step 5) waits two vblanks while the frame object's countdown at `+0x117c` runs, and FxScreen (the full-screen colour
flash, `FUN_0882da04`) sets that countdown to 2 on every frame a flash is on screen: a weapon going off near the
camera, the ship being put back on the track, the race-start fade (57 flips on both sides). What starts a stretch is
a game event, not a time the game measures, and PPSSPP shows the same stretches for the same reason, so a smoother
race would be an enhancement (the countdown store skipped), not a fix. Which writer sets which field, and the
stretches measured on both sides: [What writes the two fields](history/fidelity.md#what-writes-the-two-fields).
That enhancement exists since task 070 (E6, D-016): the menu's Flashes row, Smooth by default, clears the countdown
in Single Race and Tournament (docs/timing.md, "E6"); every check runs with it off (Original, `PURE_SMOOTH_FLASHES=0`),
so what this page measures is the PSP's pacing, and `tools/flash_check.sh` is the check that runs it on.
Time Trial, Free Play and Zone run at two vblanks a frame throughout on the PSP (their race managers set the frame
object's `+0x116c` back to 0), so they have no stretch to show. Since task 072 (E4, D-017) the menu's 30 fps modes row,
60 fps by default, lifts that lock while the race backend lives (docs/timing.md, "E4"); every check runs with it off
too (Original, `PURE_SIXTY_FPS=0`), and `tools/framerate_check.sh` is the check that runs it on.

## PPSSPP references beyond the suite (item 3)

The audit's item 3 took PPSSPP captures of every scene the brief named (`ref/README.md` lists them with their hashes
and commands). Thirteen are in the suite; three more race frames are in the scorecard's pictures (`tools/scorecard.py`
`EXTRA_SCENES`): Blue Ridge, Sinucit and Sebenco Climb's first full-HUD frames, whose ports are reached by the sweep's
picks after `main_menu.txt` + `single_race.txt`. Sinucit's and Sebenco Climb's compare two states of the weather mist
(difference 3), so their fractions stay high whatever the renderer does. The scenes with no route in
`config/pad_scripts/` (OPTIONS, CONTROLS, the other circuits' first race frames, the pause menu) have their fractions
in [the audit's table](history/fidelity.md#ppsspp-references-beyond-the-five-item-3), measured before tasks 036 to
040 changed the race pictures.

The Beta and Classic circuits are reached in PPSSPP by the game's own unlock code, LEFT, RIGHT, LEFT, L, R, L, RIGHT,
LEFT, RIGHT, R, L, R on MAIN MENU (`tools/ppsspp/routes/unlock_all.txt`), which sets the profile byte
`PURE_TEST_UNLOCK_ALL` stands in for. How it was found:
[the game's own unlock code](history/fidelity.md#the-beta-and-classic-circuits-in-ppsspp-the-games-own-unlock-code).

## The GE state the framework still ignores

The framework's GE state lists at exit the commands it does not apply (`GE commands ignored: N distinct`). The audit
counted 65; tasks 036, 037 and 040 brought them to 30 (the suite's race run on 2026-10-07: REGION1 and 2,
ANTIALIASENABLE, PATCHCULLENABLE, PATCHDIVISION, PATCHPRIMITIVE, PATCHFACING, LOGICOPENABLE and LOGICOP, MORPHWEIGHT0
to 7, SHADEMODE, TEXENVCOLOR, TEXSYNC and the GE init's undocumented 0xF0 to 0xF9). The audit found no draw of the
game using any of them in PPSSPP's dumps of the race frames: the drawing region is written with the lists (157808
times in that run, always 0 first), TEXSYNC (a texture-cache flush) 2035 times, the rest a few times at start-up or
with their reset values. The scorecard's coverage row grades this `close`. The counts and the dumps' draw-by-draw
survey: [the audit's feature table](history/fidelity.md#the-ge-state-the-framework-ignores-and-how-much-of-it-the-game-uses).

## Open

- Medal counting is untested: no cell won a medal (the follower finishes 7th or 8th, and is far off Time Trial's
  bronze times).
- The 31-flip put-back flash and the 38-to-39-flip flash were measured in the port only; PPSSPP's race had three
  flashes of 22 to 25 flips.
- The game's own unlock code would be the more faithful switch for the sweep than `PURE_TEST_UNLOCK_ALL` (it saves
  the byte with the profile, as a player's would be).
- The SAS reverb's two constants (D-010) are PPSSPP's, not proven against a PSP; a capture from real hardware would
  settle them.

## The fidelity layer's checks

How each instrument of the fidelity layer runs and what it compares: reference, not gates (docs/verification.md
lists the gates). Moved from docs/verification.md by task 092 under the same headings.

### Audio

#### PURE_AUDIO_WAV

`PURE_AUDIO_WAV=<file>` (src/hle/audio_capture.cpp) wraps the bound `sceAudioOutputPannedBlocking`,
`sceAudioOutputBlocking` and `sceAudioOutputPanned` and writes what the game submits: each buffer as stereo 16-bit
44.1 kHz with the call's volumes applied the way the sink applies them (`sample * min(volume, 0x8000) >> 15`), to
`<file>.ch<N>.wav` per channel and the clipped sum to `<file>`. It also follows `sceAudioChReserve`,
`sceAudioSetChannelDataLen` and `sceAudioChangeChannelConfig`, because the frame count of an output call is the
channel's data length and format bit 0x10 makes it mono. Every file is on the kernel's virtual clock, sample 0 at
time 0: a buffer starts where the channel's previous one ended, or at the call's virtual time when it came late, and
the gap is zeros. A gap under 2 s on a playing channel is logged as an underrun
(`[pure] audio capture: channel N underrun of F frames (M ms) at t=US`), and the exit line counts them per channel.
The headers are rewritten after every write, so a killed run still leaves readable files.

What the channels are in this game (all stereo):

| Channel | Frames per call | Carries |
|---|---|---|
| 1 | 768 | the sceSas mix: interface sounds, engine, weapons, speech |
| 2 | 2944 | music (sceAtrac): the frontend loop from the main menu, the race tracks |
| 3 | 2048 | movie audio (sceMpeg): the clip after the language confirm, the intro movie |

The capture is the sink's input bit for bit: on the loop run below, 16-frame windows of the capture at 146.5 s and
175.5 s occur exactly in the framework's `PURE_AUDIO_DUMP` of the same run, 0.816 s earlier (the sink drops the
silence a fast load produces), and the total energy of the two files agrees within 0.3%.

Times: the frontend flips at 30 a second (two vblanks), so flip N of a route is at about N/30 s of virtual time
there (the language confirm at flip 700 is at ~23 s); a race flips at 60.

#### tools/wavstats.py

```
tools/wavstats.py <wav> [--from S] [--to S] [--floor RMS] [--gap-ms G] [--min-active-frac F] [--max-clip-frac C] [--quiet]
```

One row per second (RMS and peak over both sides, clipped samples, `silent` below the floor), then the window, the
silent seconds, the longest silent run, the active fraction (whole seconds with RMS above `--floor`, default 100,
about -50 dBFS) and the clipping fraction (samples at -32768 or 32767). A dropout too short to silence a whole
second shows in the zero runs: every stretch of at least `--gap-ms` (default 50) where all samples are exactly 0, not
touching either end of the window. They are information only (between interface sounds they are normal, inside
music they are dropouts). With `--min-active-frac` and/or
`--max-clip-frac` the last line is PASS (exit 0) or FAIL (exit 1); without either it is INFO. Pure Python
(`array` and `math.sumprod`), about a second per minute of audio.

The checks of task 013 (the frontend music, its loop, a race's mix; 2026-10-05):
[The M4 checks](history/verification.md#the-m4-checks-2026-10-05).

#### tools/audio_compare.py: the port against PPSSPP

```
tools/audio_compare.py A.wav B.wav [--from S] [--from-b S] [--seconds N] [--floor RMS] [--block-ms MS] [--top N]
                       [--quiet] [--detail S:E]
tools/audio_compare.py A.wav B.wav --locate T:LEN:FROM:TO
tools/audio_compare.py --selftest
```

Two WAVs side by side, typically PPSSPP's audio dump (`tools/ppsspp/ppsspp_ctl.py run --dump-audio`, docs/ppsspp.md)
and the port's `PURE_AUDIO_WAV` capture of the same route. Each file has its own window start (`--from` for A,
`--from-b` for B), since the two reach a scene at different times. Per whole second: each file's RMS, peak and
clipped samples, `-` after a silent one (RMS at or under `--floor`, 100 as in `wavstats.py`), `<>` where only one is
active; then each file's active seconds, peak (and dBFS), clipped samples and fraction, and its `--top` longest
silences, runs of 10 ms blocks at or under the floor (`all zero` when every sample is 0). `--detail S:E` adds 100 ms
rows for a stretch of the window, the sample-level view of a gap.

PPSSPP's dump is the mix only, and in a race the effects are louder than the music, so a music gap does not show in
the mix's level. `--locate T:LEN:FROM:TO` finds B's stretch from T to T+LEN inside A between FROM and TO by normalised
cross-correlation (8 times decimated, then refined at the full rate) and prints the time in A, the offset and the
correlation: the port's music channel (`<file>.ch2.wav`) found in PPSSPP's mix at 0.3 to 0.7. The same offset at two
times means the two played the same samples in between; a different offset after a track change is the difference
in the switch, to the sample. A 2 s template takes about half a second per second searched.

`--selftest` (task 041's Verify) writes WAVs with known gaps, clipping and a hidden stretch and checks the figures, PASS
or FAIL. The comparisons of differences 7 to 9, and the routes on both sides, are in docs/history/fidelity.md
("Differences 7 to 9"). Two things to know when repeating them: the game picks the attract demo's tracks itself,
differently from run to run, so demos compare by their figures rather than sample for sample; and a dump of a race
includes PPSSPP's SAS reverb, which the port models since task 043 (patch 0008-sas-reverb; before it, PPSSPP's idle race
mix had about 1.4% more level).

#### The SAS reverb check

```
tools/sas_reverb_check.sh [--out DIR] [--env KEY=VAL ...] [--allow-parallel]
```

Plays the Free Play pause route headless and unpaced with `PURE_AUDIO_WAV` (about 20 s; the run is the port's side of
task 041's Free Play idle: `main_menu.txt` and `free_play.txt` without its Cross hold, so the ship idles on Vineta
K's grid, START at flip 16700, to flip 16800, on an empty memory stick in `<out>/game`) and compares the sound after
the pause with PPSSPP's dump of the same route, `ref/audio/free_play_pause.wav` (ref/README.md: the command, about 8
minutes, and its SHA-256; START at vblank 28800). At the pause the game stops the music, holds the effects at one
level for 70 to 150 ms, then keys them off; what sounds after that is the reverb's tail. In each mix the tail starts
at the first 10 ms block after START whose RMS is under 0.6 of the median of the five blocks before it, once those
five are all under 0.7 of the median level of the 0.5 s before START (the music has stopped, so the drop is the
held effects' end, not the music's). START's time: PPSSPP's from its vblank timing, the port's from the virtual time
of the first sceSas call the run logs after the script's START (it traces `__sceSasRevEVOL`, which the race calls
every frame). It prints both starts and the RMS of ten 100 ms steps from there, and checks the first five: PASS (exit
0) when each of the port's is non-zero and within a factor of 2 of PPSSPP's, else FAIL (exit 1); exit 2 when the
reference or the build is missing or another PureNative runs (one game at a time; `--allow-parallel` starts
anyway). `<out>` (default `out/sas_reverb`) keeps the route, the log, the WAVs and `summary.txt`. `--env` passes the
A/B switches: `--env PURE_NO_REVERB=1` (the port before task 043) and `--env PURE_SAS_REVERB_SPU_RATE=1` (the SPU's own
22050 Hz) both FAIL.

On 2026-10-07 the port's five steps were 1.05 to 1.27 of PPSSPP's (PASS); without the reverb the tail is exact zeros
after the first step, and at the SPU's own rate 1.59 to 6.83 times PPSSPP's (both FAIL):
[the table](history/verification.md#the-sas-reverb-check-task-043-2026-10-07).

### The save interchange check

```
tools/save_interchange.sh [--port-only]
tools/save_interchange.sh --check FOLDER FILE [PLAIN_OUT]
tools/save_interchange.sh --make-ppsspp-save
```

Checks that saves move both ways between the port and PPSSPP (a PSP's stand-in) now that the port writes them in the
PSP's own format, the save-data utility's no-key mode (patch 0007-savedata-list-and-no-key-mode, task 045;
docs/savedata.md "The PSP's format"). The port runs are headless, unpaced and silent on memory sticks of their own under
`out/045/<step>/game`; the PPSSPP run is the driver's, real time, on PPSSPP's own memory stick, which the script leaves
as it found it. About 3 minutes when PPSSPP is free; it waits (at most 20 minutes) while another PPSSPP runs, and never
touches another process.

| Step | What runs | Passes when |
|---|---|---|
| (a) PPSSPP to port | PPSSPP's NAME0000 (`ref/saves/ppsspp/UCUS98612P0000`, ref/README.md) alone on a fresh stick; `profile_load.txt` headless with `PURE_TRACE_SAVEDATA` to flip 3900 | LISTLOAD loads 41570 bytes and logs both hashes verified (mode 1); MAIN MENU within 0.05 of `ref/main_menu.png` at tol 24 (the suite's limit; 0.011); SET NAME's digits vary by 500 or more (1531: NAME0000); the game's PROFILE > SAVE writes P0000 back in mode 1, 41586 bytes, with "User name: NAME0000" in its PARAM.SFO (the game's own profile line), and that save verifies |
| plain | the plain save of the build before task 045 (`ref/saves/port-plain/`), the same route | it loads as a plain save (flag 0) and shows as in (a); the game's save rewrites it in mode 1, and that verifies |
| born | `main_menu.txt` headless on an empty stick, with SET NAME's shot at 2250 | NEW writes P0000 and the first-boot AUTOSAVE writes `PPCD00001DLS001` in mode 1; SET NAME on the empty stick is blank past NAME (variance 0, the control) |
| (b) port to PPSSPP | (a)'s save (the round trip's) copied into PPSSPP's stick; `tools/ppsspp/routes/profile_load.txt` (LOAD, the load dialog, Enter, "Load completed.", Back, MAIN MENU, PROFILE > NEW > YES, SET NAME) | MAIN MENU at 3720 within 0.05 of `ref/main_menu.png`; SET NAME at 4560 varies by 500 or more, equals the port's SET NAME of (a) (tol 24, 0.02) and differs from the empty stick's; the stick holds what it held before |
| (c) side by side | the port's NEW profile and the round trip's against PPSSPP's, the port's `PPCD00001DLS001` against PPSSPP's, each through the framework's `load_save` and hash checks (`out/045/savecheck`, built from `vendor/portablekit`'s save-data sources) | both sides verify (PARAM.SFO's hash, the data file's listed hash, decrypted); PARAM.SFO the same size, keys, formats, lengths and values apart from the bytes that cover the random header (the file's hash in `SAVEDATA_FILE_LIST`, the mode-1 hash at SAVEDATA_PARAMS 0x10); the flag byte equal; ICON0, ICON1, PIC1 and SND0 byte-equal. The decrypted contents are compared and every difference is listed (not a failure) |

What (c) finds (2026-10-07): the two `PROFILE.BIN`s, decrypted, differ in 71 of 41570 bytes, all inside 69 words that
hold addresses in the PSP's user RAM, the port's each 0x200 above PPSSPP's (0x08ECAF10 against 0x08ECAD10 and so on):
the profile keeps pointers into the game's heap verbatim, and the port's heap sits 512 bytes higher at that point. The
game sets them again when it loads a profile (the round trip's save, loaded from PPSSPP's and saved by the port, has
the port's addresses), so they do not matter to a load either way. Nothing else differs: no timestamp, no counter.
`DATA1.BIN` of `PPCD00001DLS001` is identical decrypted; `DATA2.BIN` beside it, which the game writes itself through
sceIo (not the save utility), differs in nearly every byte (it is the game's own, enciphered by it) and is only
reported.

`--port-only` runs everything but (b) and exits 3 (never PASS), for when PPSSPP is busy for long. `--check FOLDER
FILE [PLAIN_OUT]` puts one save folder through the same checks and writes the decrypted file (for any tool that has
to read a profile's contents: the plain bytes of a mode-1 save are not on the stick any more). `--make-ppsspp-save`
remakes PPSSPP's reference save with `frontend.txt` + `save_yes.txt` + `save_dialog.txt` and moves it out of PPSSPP's
stick into `ref/saves/ppsspp/`.

### The accuracy scorecard

```
tools/scorecard.py [--quick | --full] [--only CATEGORY[,CATEGORY...]] [--out DIR] [--tracks TRACK[,...]]
tools/scorecard.py --refresh-references [CATEGORY] [--tracks TRACK[,...]]
tools/scorecard.py --selftest
```

The standing answer to "how accurate is the port" (D-009): six categories, each row measured on the port headless and
compared with PPSSPP or with the game's own facts, graded `faithful`, `close` or `differs` by a stated threshold.
`docs/scorecard.md` holds the latest `--full` run of this branch, its header the thresholds of every category. The
tool writes `scorecard.json` (every row with its figures) and `scorecard.md` to `--out` (default `out/scorecard`),
with every run's route, log, captures and WAVs under `<out>/runs/`; a `--full` run of every category also rewrites
`docs/scorecard.md`. Exit 0 once the scorecard is written, whatever the grades.

| Mode | Categories | Port runs | Time on this Mac |
|---|---|---|---|
| `--quick` (the default) | pictures, timing (from the matrix's cells), saves, coverage | the suite, three extra race frames, a short race for the load, a profile | about a minute |
| `--full` | all six | also 12 straight-on races (three with `PURE_AUDIO_WAV`), the main menu with `PURE_AUDIO_WAV`, four sweep cells (Single Race, Time Trial and Free Play on Vineta K, Zone 1; races paced) | about 18 minutes |
| `--only CATEGORY,...` | the named ones, with `--full`'s sources (or `--quick`'s beside `--quick`) | | |

Every port run is `tools/run_boot.py --shell headless --backend metal` on an empty memory stick of its own
(`<out>/game`), silent, with the data directory `out/data/scorecard`, and no `PURE_*` switch inherited from the shell;
the suite and the sweep cells run with their own headless defaults. One game at a time: when another task's
PureNative (or PPSSPP, for the references) is running, the tool waits for it and never touches it; the report gives
the time spent waiting beside the wall time.

How each category measures:

- **Pictures.** `tools/frame_regress.sh --out <out>/regress` as it is, its `summary.txt` read for the 18 scenes; then
  the first full-HUD frames of Blue Ridge (flip 6016), Sinucit (6016) and Sebenco Climb (6018, with the unlock
  switch), the sweep's picks after `main_menu.txt` + `single_race.txt`, against `ref/blue_ridge_hud.png`,
  `sinucit_hud.png` and `sebenco_climb_hud.png` at tol 32. Their measured values and limits are in the tool's
  `EXTRA_SCENES`, set by docs/verification.md's re-baselining rule; Sinucit's and Sebenco Climb's compare two states of the weather
  mist (difference 3, task 038), so their fractions stay high whatever the renderer does.
- **Trajectories.** Each circuit's Single Race at Vector by the sweep's route (`main_menu.txt`, `single_race.txt`, the
  picks of `tools/campaign_sweep.py`), `PURE_TEST_UNLOCK_ALL=1` on all twelve, Cross held from flip 6100, no steering,
  `PURE_WATCH_GRID=1`, to flip 7800 (about 25 s of race clock; 10200 on the three audio circuits). PPSSPP's side is the
  same race through the routes of task 035 with Cross held from the first READY frame, its race records sampled as
  `tools/pp_lines.py` samples them (its block and parser), each block read twice and kept only when both reads agree.
  Both sides are cut at each ship's first lap-clock restart; the port's positions, every flip, are interpolated at
  PPSSPP's race clocks. Two PPSSPP runs of Vineta K agree at every common clock, so PPSSPP's AI is repeatable and the
  AI ships get a row per circuit (the worst of the seven). The port's headless runs repeat themselves as well, AI
  included (two runs each of Karbonis and Sinucit: 0 m apart at every common clock), so where the port's AI parts
  from PPSSPP's it is another race, not noise. A player row that differs names the nearest AI ship on each side at
  the clock it first parts (a contact with an AI ship that is somewhere else in the other run).
- **Timing.** Flips per race-clock second: pairs of `[pure] ship` lines on consecutive flips whose clock moved (a
  lap-clock restart counts the new clock; a pause, when the probe prints nothing, does not count), over the matrix's
  cells at Vector in `--quick`, over this run's sweep cells in `--full` (Tournament stays the matrix's: its cell takes
  17 minutes). The stretches: `tools/fidelity_audit.py`'s `scan_log` on the Vineta K race (the matrix's cell or this
  run's) against the summary of `--ppsspp-race vineta_k`. The race load: from the TEAM SELECTION confirm (port flip
  5700, PPSSPP vblank 6700) to the first of the 57 two-vblank flips of the race-start fade, which end where the race's
  one-vblank flips begin, in game time (the port's `PURE_TRACE_CALLS` on `sceDisplaySetFrameBuf`, PPSSPP's flip log);
  graded `accepted (D-011)`.
- **Audio.** The main menu: `main_menu.txt` with L every 600 flips (20 s) from 4800, to flip 6900, against PPSSPP's dump
  of `frontend.txt` + `main_menu_music.txt` (L every 1200 vblanks): the attract demo, which would start 30 s after the
  last new button and play a track the game picks itself, never comes, and L makes no sound there (the port's
  sceSas channel stays silent). `--locate` finds three two-second stretches of the port's mix (4, 24 and 44 s into
  the music) in PPSSPP's dump; the lowest correlation is graded, and the per-second RMS ratio over the aligned 60 s.
  The races: the port's music channel (`.ch2.wav`) located in PPSSPP's mix at five stretches from GO + 10 s, the
  median correlation graded; then the two mixes over 60 s from GO aligned by the best stretch's offset: the share of
  seconds where both or neither are active, and the clipped samples. The AI ships differ in the port, so the effects
  do too; the RMS ratio of the race mixes is reported, not graded.
- **Saves.** `tools/save_roundtrip.sh`'s first run, `main_menu.txt` on an empty stick (NEW, NAME0000, AAA, SAVE PROFILE
  YES), made headless in seconds (the script itself runs five windowed runs in 13 minutes and has no option for one),
  against PPSSPP's save of the same profile (`ref/scorecard/saves/UCUS98612P0000`). Since task 045 (patch
  0007-savedata-list-and-no-key-mode) both write PROFILE.BIN enciphered in the save utility's mode 1, so it is compared
  by size and by its contents, each side decrypted through the framework's own load path with both hashes checked
  (`tools/save_interchange.sh --check`): close when the only differing words hold user-RAM addresses on both sides (the
  profile keeps heap pointers verbatim, task 045's finding; the game sets them again on a load).
- **Coverage.** The cell results of `tools/fidelity_audit.py` from `out/035-wip/fidelity` (this checkout's, else the
  main checkout's, else `out/fidelity`); without them the rows say which command makes them (about 4 hours; the
  scorecard never runs the matrix). The 278 imports by state from `config/imports.csv`, the start-up list of
  unimplemented imports and the `[hle-stub]` and `UNVERIFIED` lines of the matrix's logs (the brief names an
  `hle_coverage.csv` under `config/`, which does not exist). The GE commands still ignored from this run's exit list.
  Functions entered: not measured (no cheap entry count exists).

`--refresh-references [CATEGORY]` (trajectories, audio, saves or timing; all four without one) takes the PPSSPP side
into `ref/scorecard/`, one PPSSPP at a time, waiting while PPSSPP runs for another task or while its memory stick
holds a profile save, and lists every file with its SHA-256 in `ref/scorecard/manifest.json` and `ref/README.md`
(the commands are there too). A row whose reference is missing says `no reference` and names the command; it does not
fail the run. `--selftest` checks every grader, the parsers and the report on synthetic inputs (PASS in about a
second).

### The VFPU dot-product check

```
tools/vfpu_probe.py cover [--track T] [--seconds S]          # once: which sites a race runs (ref/vfpu/coverage.csv)
tools/vfpu_probe.py sample --out ref/vfpu/jit --sites all --cap 5000 --seconds 12
tools/vfpu_probe.py sample --out ref/vfpu/interp --cpu-core 0 --cap 1500 --seconds 12 --sites ADDR,...
tools/vfpu_probe.py port ref/vfpu/jit                        # the port's results for the same operands
python3 tools/vfpu_model.py --selftest && python3 tools/vfpu_model.py --check ref/vfpu
```

The check behind difference 13's last step (docs/history/fidelity.md, "The dot-product rule, measured"): PPSSPP's VFPU
results at the game's own instructions, and a model that reproduces every one of them.

**The sites.** `scan` decodes EBOOT.ELF and keeps the instructions the corpus has code for (its `L_XXXXXXXX` labels,
so decoded data is left out): 711 sites of `vdot`, `vtfm`, `vmmul`, `vrcp`, `vrsq`, `vsqrt`, `vsin` and `vcos`
(`vhdp` decodes only in data, which the corpus has no code for; `vexp2`, `vlog2` and `vasin` do not occur at all).
`cover` found 205 of them executed from READY to 3.2 s of race clock on Vineta K, 1.4 million hits; `vsin` and `vcos`
(two sites each) were not among them.

**The PPSSPP side.** The route is the scorecard's reference route (`frontend.txt`, `vineta_k_start.txt`, Cross held
from READY), so the race is the one the scorecard's references and the race clocks of task 046 come from. Log-only
breakpoints (`cpu.breakpoint.add` with `log` and a `logFormat`; PPSSPP's expressions take the scalar names S000 to
S733) sit on each site, logging its source lanes, and on the next instruction, logging the destination lanes; a pair
counts only when the two lines are consecutive in PPSSPP's log. Three things the debugger taught:
- A breakpoint added while the CPU runs never fires in a block the JIT has already compiled (the first coverage run,
  armed at READY, saw 47 sites and none of the ship update's). The probe adds every breakpoint at boot with the
  condition `usec >= READY` (and an end for the hot sites), which keeps them silent through the menus.
- `cpu.getAllRegs` offers the GPRs, the FPU and the 128 VFPU scalars, not the prefix registers; the probe reads the
  `vpfx` words in front of each site from the code (`sites.json`). None of the sampled sites has a prefix.
- With the interpreter (`--cpu-core 0`) a log-only breakpoint stops the CPU like any other; the probe then reads the
  registers with `cpu.getAllRegs` at each stop and resumes (about 90 stops a second, so that run samples 27 sites).

The breakpoints change PPSSPP's AI race a little (the player's ship ends within 1 mm of the reference at 12 s in every
run; the AI ships up to 8 m with 330 breakpoints), by their place in the JIT's blocks, not by the instruction they
sit on; each logged row is still one execution's operands and result. The measurements:
[the breakpoints](history/verification.md#the-vfpu-dot-product-check-task-047-2026-10-07).

**The port side.** `port` builds, for every sampled site, the corpus's own block of that instruction
(`generated/generated_unit_*.cpp`, between its label and its `goto`) into one program with the corpus's flags
(`/usr/bin/clang++ -O2 -std=gnu++20 -arch arm64`), loads PPSSPP's operands into an `AllegrexContext`, runs it and
writes the destination lanes: the port's results on PPSSPP's operands, without a port run. The model's emulation of
the port (model b) reproduces every one of them.

**The model.** `--check` takes each sample set under `ref/vfpu`, the rule of the PPSSPP core that made it
(`vfpu_model.py` `RULES`) and the instruction, and counts the dot products the rule reproduces; it exits 0 when it is
all of them, else prints up to 20 failing rows a group (operands, PPSSPP's result, the model's and the port's). It
then reports the transcendental instructions. About 10 s. `--report` runs every candidate model over every set
(about 70 s for the JIT set). The samples are git-ignored; ref/README.md has the commands and their hashes.

#### The two rounding modes (D-013)

The port's generated code rounds dot products as a real PSP does by default and as PPSSPP's JIT does under the test
mode (`PURE_VFPU_DOT=ppsspp`, or `PURE_TEST_RACE_CLOCK`, which implies it). Both are checked against the recorded
samples by recomputing the port side with the probe's harness under each mode:

```sh
for mode in ppsspp psp; do
  rm -rf out/vfpu_$mode && mkdir -p out/vfpu_$mode && cp -R ref/vfpu/jit out/vfpu_$mode/jit && cp ref/vfpu/coverage.* out/vfpu_$mode/
  PURE_VFPU_DOT=$mode python3 tools/vfpu_probe.py port out/vfpu_$mode/jit
done
python3 tools/vfpu_model.py --report out/vfpu_ppsspp     # the "port" row must read 100% in every column
```

and, for the default mode, the port's results against the hardware model (`vfpu_model.model_fn("c", vfpu_model.HW[1])`)
over `vfpu_model.dot_rows(...)` of `out/vfpu_psp/jit`, which must agree on every row. The probe's harness compiles
the header, so the check runs without a game; the vtfm and vmmul sites need the regenerated corpus (`tools/regen.sh`),
since their code is emitted inline. The figures of the corpus rebuild of 2026-10-07:
[the two rounding modes](history/verification.md#the-two-rounding-modes-task-047-2026-10-07).

#### The other kinds

```sh
P=/opt/homebrew/bin/python3
K=vcrs,vcrsp,vqmul,vfad,vavg,vrot,vmscl
for t in vineta_k karbonis; do
  $P tools/vfpu_probe.py cover --track $t --kinds $K --seconds 13 --out ref/vfpu/jit/048_$t        # 2.5 min each
  $P tools/vfpu_probe.py sample --track $t --out ref/vfpu/jit/048_$t --sites all --cap 0 --seconds 13   # 4 min each
  $P tools/vfpu_probe.py port ref/vfpu/jit/048_$t --modes ppsspp,psp
done
python3 tools/vfpu_model.py --check ref/vfpu          # every set: the dot forms, the other kinds, both modes
python3 tools/vfpu_model.py --diff ref/vfpu/jit/048_karbonis --limit 20    # where the test mode differs, in time order
```

The same check as the dot products' for the kinds beside them: `vcrs.t`, `vcrsp.t`, `vqmul.q`
(`execute_vfpu_cross_quat` and the codegen's inline `vcrs`), `vfad`, `vavg` (`execute_vfpu_horizontal`), `vrot` and
`vmscl`. Each result lane is one problem (a cross product's three lanes, a horizontal sum's one, a vmscl's sixteen
elements), with its own candidate models in `vfpu_model.kind_models` and PPSSPP's measured rule in `RULES_048`. The
game's code has only `vcrsp.t`, `vfad`, `vrot` and `vmscl`; `vcrs.t`, `vqmul.q` and `vavg` decode only in data, so
their models are checked against pspautotests' `vector.expected` alone (`--selftest`), and no `vrot` ran from READY to
13 s on either circuit.

What is new in the tools:
- `sample --cap 0` logs every execution from READY (these kinds run rarely enough: 0.9 million rows a circuit), and
  `--window FROM,TO` logs every execution of every listed site between two race clocks and nothing else, placed on
  PPSSPP's emulated time by the player's samples of the scorecard's reference race (`--sites` may then name sites
  that never run; they give empty files). Karbonis' dot and transcendental window (`048_karbonis_dot`, 711 sites, 6.0 to
  7.0 s) was taken with `--sites` set to every dot and transcendental site of `scan`.
- `port --modes ppsspp,psp` runs the harness under each rounding mode of patch 0009-vfpu-rounding and writes
  `<ADDR>.port.<mode>.csv`; `--check` then prints, under every rule line, the test mode against PPSSPP and the default
  mode against the PSP's rule (`hw_of`: the hardware dot product, or `HW_048`'s model). The harness now compiles with
  `-ffp-contract=off`, as the corpus does since task 047.
- A header experiment never touches `vendor/`: copy `vendor/portablekit/include` to `out/048/candidate/include`, edit it
  there, then `port DIR --modes ppsspp,psp --tag candidate --include out/048/candidate/include` and `vfpu_model.py
  --check DIR --tag candidate`. The corpus before task 047's rounding is the same with that rounding's header hunk (old
  patch 0020, the first part of `patches/0009-vfpu-rounding.patch`) reversed in the copy and `--fp-contract on --tag
  pre0020`.
- `vfpu_model.py --diff DIR [--which ppsspp]` lists, per site and then in time order, every sampled result where the
  port differs from PPSSPP: the candidates a divergence can start from.

What the samples of the other kinds showed (2026-10-07): [The other
kinds](history/verification.md#the-other-kinds-task-048-2026-10-07).

## History

[docs/history/fidelity.md](history/fidelity.md): the fidelity audit's report as it stood, with every
task's findings from 035 to 048 (the matrix, the feature table, the references, audio, saves, the
stretches, and each difference's evidence).

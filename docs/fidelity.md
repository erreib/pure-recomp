# Fidelity

D-009 asks for the port as close to 1:1 with the original as possible before any enhancement. This doc says where
the port stands against the original today, difference by difference, and how that is measured. The fidelity audit
(task 035, 2026-10-06) found the differences and the M8 tasks after it (036 to 048) fixed or explained them; their
report, every table and finding with its date, is [docs/history/fidelity.md](history/fidelity.md).

## How it is measured

| Tool | What it answers | Where |
|---|---|---|
| `tools/scorecard.py` | the standing answer: six categories (pictures, trajectories, timing, audio, saves, coverage) graded `faithful`, `close` or `differs` against PPSSPP or the game's own facts | docs/scorecard.md (the latest `--full` run), docs/verification.md "The accuracy scorecard" |
| `tools/frame_regress.sh` | 18 scenes against PPSSPP's captures: every menu of the five modes and the first race frames | docs/verification.md "Frame regression suite" |
| `tools/fidelity_audit.py` | the campaign matrix: 46 cells (every circuit in Single Race at Vector and Phantom and in Time Trial, Free Play and the tournaments by league, Zone 1 to 4), headless, collecting every halt, stub, unemulated GE state, warning, two-vblank stretch and audio figure; about 4 hours | README.md, the tools table; [the matrix of 2026-10-06](history/fidelity.md#the-campaign-matrix-item-2) |
| `tools/ai_seed_check.sh` | the scorecard's trajectories with PPSSPP's race clock pinned (difference 13) | README.md |
| `tools/sas_reverb_check.sh` | the reverb's tail at a pause against PPSSPP's (difference 12) | docs/verification.md "The SAS reverb check" |
| `tools/save_interchange.sh` | saves both ways between the port and PPSSPP (difference 5) | docs/verification.md "The save interchange check" |
| `tools/vfpu_probe.py`, `tools/vfpu_model.py` | the VFPU's rounding at the game's own instructions (difference 13) | docs/verification.md "The VFPU dot-product check" |

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

## History

[docs/history/fidelity.md](history/fidelity.md): the fidelity audit's report as it stood, with every
task's findings from 035 to 048 (the matrix, the feature table, the references, audio, saves, the
stretches, and each difference's evidence).

# The fidelity audit (task 035, 2026-10-06)

D-009 asks for the port as close to 1:1 with the original as possible before any enhancement. This audit measures
where it is not, across the campaign, and ends with the list the M8 fix tasks come from ("The differences", last
section). It changed no game-facing code: it ran the game, PPSSPP and the static analysis tools and compared.

Four kinds of evidence:

- **The campaign matrix** (`tools/fidelity_audit.py`, below): 46 cells headless on the Metal backend, every halt,
  unimplemented import, unemulated GE state, warning, two-vblank stretch and audio figure collected per cell.
- **PPSSPP references beyond the five**: new routes in `tools/ppsspp/routes/`, new captures in `ref/` (listed in
  `ref/README.md`), twelve of them in the frame regression suite, and a PPSSPP race driven by the sweep's own
  follower (`tools/fidelity_audit.py --ppsspp-race`).
- **Audio** over every cell (`PURE_AUDIO_WAV` on each, `tools/wavstats.py` from the race start) and a five-minute
  idle on the main menu.
- **Saves and records** after a Single Race and a Tournament, a reboot that LOADs the autosaved profile, and two
  profiles in a row.

Plus the static analysis behind the two-vblank stretches (task 033's follow-up): Ghidra decompiles of the routines
that write the frame object's lock fields (`out/035/limiter_writers.txt`, `out/035/fxscreen.txt` in the worktree;
the commands are under "The two-vblank stretches").

<!-- MATCHES -->

<!-- MATRIX -->

## Halts, stubs and what the GE draws without (item 1's feature table)

`out/fidelity/features.md` lists every distinct line the collectors took from the cells' logs (frame numbers and
times taken out), then the framework's exit list of GE commands it ignores, then the imports with no
implementation. Over the whole matrix:

<!-- FEATURE_SUMMARY -->

### The GE state the framework ignores, and how much of it the game uses

The framework's GE state (`vendor/portablekit/host/gpu/ge_state.cpp`) counts every GE command it does not apply and
prints the list at exit (`GE commands ignored: 65 distinct`, the count and the first value of each); the Metal
backend draws from that state, so these never reach a picture. The counts tell how often the game writes a command,
not whether it changes anything: the first value is the reset value in every cell. Whether the game turns a feature
on was read from PPSSPP's GE dumps, which hold the complete state of every draw (`out/035/gestate.py`, a reader on
top of `tools/ppsspp/ppdmp.py`; draws of the frame, clears left out):

<!-- GESTATE -->

What that means for the picture, from the most draws to the fewest:

- **Mipmaps.** Most of the race's textures carry two to five mip levels (TEXADDR1 to 4, TEXSIZE1 to 4, TEXLEVEL
  mode 2 "slope" with a per-draw LOD slope, TEXLODSLOPE), and the PSP picks a smaller level as a surface recedes.
  The port always samples level 0, so distant textures (grandstand crowds, the track's far surface, building
  windows) are sharper and shimmer in motion where the PSP's are smooth: the clearest single difference in the race
  shots (the Blue Ridge pair below).
- **Environment and projection mapping** (TEXMAPMODE 2 and 1, TEXSHADELS): about a tenth of a race frame's draws
  take their texture coordinates from the normals (a reflection) or from the texture matrix. The port draws them
  with the vertices' own coordinates, so the ships' hulls and canopies and the shiny roofs lose or misplace their
  reflections (the ship crops below).
- **Dithering** (DITHERENABLE, DITH1 to 4): 60 draws of the race frame. The PSP dithers when it writes 16-bit
  colour; most race targets are 32-bit, where it does nothing. Small.
- **The colour test** (COLORTESTENABLE, COLORTEST, COLORREF, COLORTESTMASK): 6 draws of the race frame. A drawn
  pixel whose colour matches the reference is discarded on the PSP and kept by the port. Which 6 draws, and
  whether they show, is open.
- **Depth clamp** (CLIPENABLE): set for every 3D draw. The PSP clamps depth to the range instead of clipping
  against the far plane; the port clips. Shows only where geometry crosses the depth range's ends.
- **Regions, flat shading, logic ops, morph weights, patches, the GE init's undocumented F0 to F9**: written a few
  times at start-up or with their reset values (`first=0x0`, one write a run); no draw of the frames read used
  them.

### Imports with no implementation

26 of the 278 imports have no implementation (the start-up list in every log: `sceKernelLoadExec`, the alarm and
semaphore-status calls, ten `sceHttp*`, the adhoc matching and PDP stat calls, `sceParseHttpStatusLine`,
`sceUriParse`, `sceRtcGetTime_t`, `sceRtcSetTime_t` and the four `sceUtilityGameSharing*`). None was called in any
cell: a call would print `[hle-stub]`, and with `PURE_STRICT_HLE=1` stop the cell as HALT. They belong to the
multiplayer, the download menu's network side and game sharing, which no cell reaches.

## PPSSPP references beyond the five (item 3)

New routes in `tools/ppsspp/routes/` reach every scene of the brief in PPSSPP with frame-exact input; the captures
are listed in `ref/README.md` with their hashes and the commands that make them. A port capture of the same game
moment was made for each, headless on the Metal backend: by the suite's own routes where `config/pad_scripts/` has
one, by ad-hoc presses otherwise (the steps are in the table). Scenes with a port route are now rows of
`tools/frame_regress.sh` (twelve; "Re-baselining" in docs/verification.md for their measured values); the others
need a route file in `config/pad_scripts/`, which this task could not add (Must not touch), so their fractions are
here only.

How the moments were matched: the frontend runs at two vblanks a frame on both, so a menu `k` frames after its
press is PPSSPP vblank `V + 2k` for port flip `F + k`; each menu pair was then confirmed by searching a burst of port
captures for the PPSSPP frame (every menu matched at a fraction of 0.0000 at tol 24, the Metal backend drawing the
2D screens exactly). Race and Zone scenes are the first frame with the HUD fully faded in, found on both sides from
the CURRENT and LAP labels' brightness (`tools/hud_check.py`'s regions) or, in Zone, the SCORE label's.

A PPSSPP capture made while the CPU is held at a breakpoint lets PPSSPP's file reads run on in real time, so a
capture during a load makes the load end sooner in emulated time and moves everything after it (two runs of
`zone_start.txt`, one with a capture every 10 vblanks and one with none during the load, put the race 100 vblanks
apart). Every race reference was therefore taken in a run with no capture between the route's last menu press and
the scene.

<!-- REF_TABLE -->

### The Beta and Classic circuits in PPSSPP: the game's own unlock code

PPSSPP's CWCheat engine has pointer writes (code type 6: a pointer at an address, a value, an offset), which should
reach the profile's unlock byte at `[0x08B17794] + 0x381` (not tried); GPI cannot be cheated, being no memory.
Neither is needed: the game has the unlock as a button sequence on MAIN MENU. FUN_0894d4c8, the MAIN MENU
page's update, compares each newly pressed button with the table at 0x08AB480C (codes 2, 3, 2, 8, 9, 8, 3, 2, 3, 9,
8, 9, -1); FUN_08898870 numbers the PSP's buttons 0 UP, 1 DOWN, 2 LEFT, 3 RIGHT, 4 CIRCLE, 5 CROSS, 6 TRIANGLE, 7
SQUARE, 8 L, 9 R. So **LEFT, RIGHT, LEFT, L, R, L, RIGHT, LEFT, RIGHT, R, L, R** on MAIN MENU sets the profile's
`+0x381` and shows "CONGRATULATIONS! YOU HAVE UNLOCKED: EVERYTHING"; any other button starts the sequence again.
`tools/ppsspp/routes/unlock_all.txt` enters it in PPSSPP and the port took it the same way (headless, the presses
from flip 4480, 30 apart: the same panel, then five classes on CLASS SELECTION, without `PURE_TEST_UNLOCK_ALL`).
`unlock_race_beta.txt`, `unlock_race_classic.txt` and `unlock_track_downN.txt` then reach every Beta and Classic
circuit, and their first full-HUD frames are in `ref/` (PNG only) and in the table above. The port's side of those
eight used the sweep's picks with the test switch; the profile byte set by the code would be the more faithful
switch for the sweep (it is saved with the profile, as a player's would be).

## Audio (item 4)

Every cell ran with `PURE_AUDIO_WAV` (docs/verification.md, "Audio": the mix and one file per channel, on the
kernel's virtual clock, so a headless run records what the game hands sceAudio with no device open), and the tool ran
`tools/wavstats.py` over the mix, the sceSas channel (1) and the music channel (2) from the race start (the first
ship line with a running clock) to the cell's end, then removed the WAVs. `out/fidelity/audio.md`:

<!-- AUDIO_TABLE -->

<!-- AUDIO_NOTES -->

### Five minutes idle on the main menu

`main_menu.txt` headless to flip 13500 with `PURE_AUDIO_WAV` (320.6 s of virtual time; the main menu from about
145 s). The frontend music starts at 145.5 s, as in task 013. Left alone for 30 s the main menu launches the attract
demo (FUN_0894d4c8: no new button for 30 s of its timer, "Demo Launch"): a race on Modesto Heights, and after it a
second on Citta Nuova (the TrackStartup.xml each opens). The music channel stops for the demo's load (175.5 s, 9 s of
silence on channel 2 while the sceSas channel carries the demo's sound) and again for the second demo (295.7 s, 9
s). Over 146 to 320.7 s the mix is active in every second (174 of 174), with no zero run of 50 ms or more; the music
channel is active 156 of 174 seconds, the two loads its only silences.

The mix clips in the demos' races: 2611 samples at full scale over the window (0.017%), in nine seconds between 202
and 276 s, up to 1000 samples in one second, and the sceSas channel itself holds 3474 clipped samples: the clipping is
in what the sceSas mixer hands the game, before sceAudio. The scripted races clip far less (the single-race cells'
mix 0.00003 or less). Whether the PSP's own SAS mixer clips there too was not measured (PPSSPP can dump its audio,
`DumpAudio` in its ini, not used here).

## Saves and records (item 5)

Every cell starts from an empty memory stick and makes a profile (`main_menu.txt`: NEW, NAME0000, AAA, SAVE PROFILE
YES), so every log has the first-boot AUTOSAVE of `PPCD00001DLS001` and the NEW profile's LISTSAVE of
`UCUS98612P0000`; the matrix's `saves` column lists anything beyond those two. The Single Race cells quit at their
results panel, before the game saves; so two runs went on past it:

- **After a Single Race**: a cell of the audit's `single_race_save` mode (Single Race's route with the Tournament's
  end rule: Cross every 120 flips after the results panel; `--cells` with `single_race_save vineta_k`). After the
  panel (BAD LUCK... 7TH, the laps 1:06.77, 0:59.66, 0:59.96, TOTAL 3:06.39, LR and RR marks, ENTER TAG AAA) the
  game shows PROFILE AUTOSAVED and saves: `[savedata] AUTOSAVE (1) game="UCUS98612" save="P0000"
  file="PROFILE.BIN"`, 41570 bytes, the same size as at NEW. Then RETURN TO MAIN MENU / RACE AGAIN / NEXT RACE. Its
  TRACK SELECTION, back in the menus, shows RACE RECORD 3:08.59 and LAP RECORD 0:58.69 for Vineta K.
- **After the Alpha tournament** (the matrix's `tournament-alpha` cell): PROFILE AUTOSAVED and an AUTOSAVE of
  `P0000/PROFILE.BIN` after races 1, 2 and 3; the cell ends on the final TOURNAMENT STANDING, before the fourth.

Then a reboot that LOADs the saved profile (headless: `profile_load.txt`'s first steps, the title and LOAD, on a copy
of the cell's memory stick, then MAIN MENU > PROFILE > PROGRESS, RECORDS > RACE (paged with RIGHT), STATS, and
SINGLE PLAYER > TIME TRIAL > TRACK SELECTION):

| Screen | New profile | After the Single Race, LOADed | After the tournament, LOADed |
|---|---|---|---|
| RACE RECORDS, Vineta K, Vector | 1ST, 2ND, 3RD and BEST LAP 0:00.00 | 1ST AAA 3:08.59 FEISAR, BEST LAP AAA 0:58.69 FEISAR | 1ST AAA 3:03.60 FEISAR, BEST LAP AAA 0:59.12 FEISAR |
| RACE RECORDS, Modesto Heights / Chenghou Project / Blue Ridge | 0:00.00 | 0:00.00 | 4:40.40 and 1:29.06 / 4:19.22 and 1:19.00 / 0:00.00 (race 4 not autosaved) |
| PROGRESS (the medal grid per track and class) | ROOKIE (0), no medal | ROOKIE (0), no medal (7th) | ROOKIE (0), no medal (8th overall) |
| STATS | every time 00:00:00, medals 0 | TOTAL and SINGLE RACE PLAY TIME 00:03:08 | TOTAL and TOURNAMENT PLAY TIME 00:12:04 |
| Time Trial's TRACK SELECTION | RACE and LAP RECORD 0:00.00 | the same (no Time Trial run) | |

The records the reboot shows are the ones the race set (the tournament's Vineta K: 64.6 + 59.1 + 59.9 s = 3:03.6),
so the autosave, the files under `ms0/PSP/SAVEDATA/UCUS98612P0000/` and LOAD round-trip the progress. No medal was
won by any cell (the follower finishes 7th or 8th, and Time Trial's bronze at Vineta K is 2:10.00 against its
3:23 to 3:33), so medal counting is untested.

### Two profiles in a row, and the PSP's save list

`main_menu.txt` then MAIN MENU > PROFILE > NEW > YES on the same stick (SET NAME comes pre-filled with the current
name, and the same presses made it NAME1111), SAVE PROFILE YES, then PROFILE > LOAD, with `PURE_TRACE_SAVEDATA=1`:

- the second LISTSAVE asks for the list `P0000` to `P0004` with `overwrite=0` and the framework answers it by writing
  `P0000` again: the first profile (NAME0000) is gone, and the stick holds one profile, NAME1111;
- LISTLOAD then loads `P0000`, the only save, without a list on screen.

<!-- SAVE_DIALOG -->

## The two-vblank stretches (item 6): the game's own rule, and PPSSPP has them too

Task 033 found that every race runs 0.4 to 1.3 s at a time at two vblanks a frame, the end-of-frame routine's locked
path (docs/timing.md, step 5: FUN_0886511c waits two vblanks when the frame object's byte `+0x116c` is 0 or its
countdown at `+0x117c` is not 0, and decrements the countdown). This audit found what sets the lock in a race, and
measured PPSSPP at the same game moments. **Finding: the stretches are the game's own; nothing in the HLE's timing
starts them; PPSSPP shows the same stretches, the same length, for the same reason.**

### What writes the two fields

The frame object is the one `DAT_08a8e960` points to. Every store to its `+0x116c` and `+0x117c` in the corpus
(found in `generated/` by the stores at offsets 4460 and 4476, then decompiled in Ghidra from a copy of the main
checkout's project, `analyzeHeadless ... -process BOOT.BIN -noanalysis -readOnly -postScript Decompile.java OUT
ADDR...`, since Ghidra refuses a path with `.claude` in it):

| Writer | Field | Value | When |
|---|---|---|---|
| BackendRoot_cpp__0880c068 (the race backend's constructor) | `+0x116c` | 1 | a race starts: free-running frames from here (the 60-fps modes) |
| BackendRoot_cpp__0880c328 (its destructor) | `+0x116c` | 0 | the race is torn down: back to the frontend's 30 fps |
| LinkObj_etc__08818d80 (SPFreePlay_RaceManager.cpp's constructor), LinkObj_etc__08819a0c, LinkObj_etc__0881bc8c (two more race managers of the same shape) | `+0x116c` | 0 | Free Play and the other 30-fps modes lock again after the backend set 1 |
| RenderManager_cpp__088666c4 | both | 0, 0 | render manager set-up |
| FUN_08897f20, FUN_08896d7c, FUN_08896e30 (MemStickUtil.cpp's dialog driver) | `+0x116c` | `DAT_08b17c14` (the mode saved before a save dialog) | a save or load dialog ends |
| **FUN_0882da04 (FxScreen.cpp's update, after its constructor FxScreen_cpp__0882d8fc)** | `+0x117c` | **2, every frame its effect runs** | a full-screen flash is on screen |
| FUN_0886511c (the end-of-frame routine) | `+0x117c` | the countdown less 1 | each locked frame |

FxScreen (`c:/Work/Wipeout/Code/System/Particles/FxScreen.cpp`) is a full-screen colour flash with keyframed colour
and a duration. While its time runs from 0 to 1 it queues itself for drawing (FUN_08865358, sort key 0x4e000000) and
sets the countdown to 2, so every frame of the flash and the one after it wait two vblanks. Its strength falls off
with the camera's distance from the flash's position (FUN_0882e58c: `1 - (|camera - position| - near) / (far -
near)`, clamped), and a new flash replaces the running one only if it is stronger. The one FxScreen object is made in
the race set-up (Fog_etc__0880c748, pointer at `DAT_08a8ce44`); the code that reads that pointer, so the code that
starts flashes, is in MineManager.cpp, MissileManager.cpp, RocketManager.cpp, Bomb.cpp, DisruptorFx.cpp,
Quake_Importer.cpp (the weapons' explosions), FUN_08928824 (the ship destroyed), the ship's own code (LinkObj_h__08923db4,
LinkObj_h__089258b8), RaceManager (FUN_088125a4) and BackendRoot. So a stretch is a weapon going off near the camera,
the player's ship falling off the track and being put back, or the race-start fade.

### In the port's races

The matrix collects every stretch (`out/fidelity/stretches.md`; the table below). Two kinds:

- **31 or 32 flips (1.03 s)**, the same length each time: the ship leaving the track and the game putting it back
  (Sinucit, race 1 of the Beta tournament: five at 897 to 969 m, each one of the put-backs the sweep counted), and at
  Phantom on Vineta K ten at 108 to 167 m in laps 1, 3, 4 and 5, where the follower at Phantom speed loses the track.
- **13 to 25 flips (0.4 to 0.8 s)** at places that change from run to run: weapons going off near the player (the AI
  ships fire at it, and the follower fires whatever it picks up: its steering tables' `absorb=2` presses Square every
  two seconds, which the game's controls screen names Use pickup).

<!-- STRETCH_TABLE -->

A race with Cross held and no steering, where the player stops at the first barrier and no weapon comes near, has
none: `main_menu.txt` + `single_race.txt` headless to flip 9300 (51 s of race), and PPSSPP's `vineta_k_hold_cross.txt`
(50 s), both zero.

### In PPSSPP

`tools/fidelity_audit.py --ppsspp-race vineta_k` drives PPSSPP through the frame-exact routes to the Vineta K grid and
then steers the race with the sweep's own follower (the same steering table, the race record read from PPSSPP's memory
about 30 times a second, the stick and Square sent live), while log-only breakpoints log every flip with its emulated
time, every pass through the locked path (0x08865254) and every store of FxScreen's countdown (0x0882E198):

| Run | Laps (s) | Contacts | Two-vblank stretches (flips, s) | FxScreen stores in them | Locked passes in them |
|---|---|---|---|---|---|
| PPSSPP, `--ppsspp-race vineta_k` | 65.2, 59.3, 61.6 | 45 | 22 (0.73), 25 (0.83), 25 (0.83) | 21, 24, 24 (every flip but the first) | 22, 25, 25 |
| port, `single_race-vineta_k` of the matrix | 66.7, 59.6, 59.9 | 45 | 16 (0.53), 23 (0.77), 23 (0.77) | (no probe) | |

The follower drove both the same way (laps within 1.5 s and the same contact count), and both races had three
flashes of the same length. Where they fall differs because the weapons do (the AI ships' choices differ run to run
on both). The race start matches flip for flip: after the load both run 57 flips at two vblanks while the
race-start fade plays (PPSSPP logged 57 FxScreen stores there; the port's `PURE_TRACE_CALLS` trace of
`sceDisplaySetFrameBuf` shows 57 flips 33.4 ms apart, flips 5708 to 5764), then one vblank a flip.

What starts a stretch is a game event (an explosion, a put-back, the race start), not a time the game measures from
the system clock, and the lock lasts as long as the flash: the HLE's answers play no part, and PPSSPP shows the same
lengths. So this is faithful, and the list below has no row for it. A smoother race than the PSP's would be an
enhancement (the countdown store could be skipped, as the 60-fps cheat skips the second vblank wait), not a fix.
Open: the 31-flip put-back flash was measured only in the port (PPSSPP's race never left the track), and why the
follower at Phantom triggers one at about 150 m of Vineta K each lap was not looked into.

<!-- DIFFERENCES -->

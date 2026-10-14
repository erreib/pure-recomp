# Frame pacing and the 30/60 fps split (spike S8, 2026-10-05)

Source: Ghidra decompile of `FUN_0886511c` (0x0886511c-0x08865357), the end-of-frame routine, in `out/limiter.txt`.
Addresses are for US v2.00 (UCUS-98612). The CWCheat "60 fps" code `0x200652A8` targets `0x088652A8`.

## What the routine does, in order
1. `FUN_088eda8c(0,0)`: GE sync (this function is the only caller of `sceGeDrawSync`; it also calls `sceGeListSync`).
2. Display-list bookkeeping (`FUN_08866200`, `FUN_088662fc`, `FUN_088913d8`, `FUN_08866498`, `FUN_08897f20`).
3. If a debug byte at `0x08a8f1fc` is set: a debug overlay (`FUN_08865f7c`, which animates with `sceDisplayGetVcount`).
4. `sceKernelGetGPI()` bits 0x40/0x20 switch `sceDisplaySetMode` between mode 0 and debug modes 0x60/0x1a at 480x272.
   GPI is the dev-kit switch block; on retail it reads 0, so mode 0 is used. Our HLE returns 0.
5. Pacing, chosen by GPI bit 0x80 (always 0 on retail), then by two fields of the frame object `param_1`:
   - if `*(u8*)(param_1+0x116c) == 0` (mode is vblank-locked) **or** `*(int*)(param_1+0x117c) != 0` (a countdown
     of frames that forces locking, decremented here): `n = 2 - (sceDisplayGetVcount() - lastVcount)`, clamped to
     1..2, then `n` times `sceDisplayWaitVblankStartCB()`. That is a **30 fps lock**: two vblanks per frame.
   - else `sceKernelDelayThreadCB(150)`: the frame runs free, bounded only by the GE sync in step 1. This is the
     "60 fps target" of Single Race and Tournament; the actual rate is whatever the frame costs.
6. `lastVcount = sceDisplayGetVcount()`.
7. `FUN_088ef6b8()`: frame-buffer swap (one of the three `sceDisplaySetFrameBuf` callers), result stored at
   `param_1+0x5df1`.

The cheat replaces the `bne a0,zero,0x08865298` at `0x088652a8` (the loop branch of step 5) with a NOP, so the
locked modes wait one vblank instead of two. Game logic that advances per frame then runs at double speed, which is
the reported "double speed in 30 fps areas".

## Consequences for the runtime
- Implement on the virtual clock: `sceDisplayGetVcount` (vblank counter), `sceDisplayWaitVblankStartCB` (block
  until the next vblank, run callbacks), `sceKernelDelayThreadCB`, `sceDisplaySetMode`, `sceDisplaySetFrameBuf`,
  `sceKernelGetGPI` (returns 0). Yakumo does not register `sceDisplayWaitVblankStart*` (MHP3rd paces through
  `sceCtrlReadBuffer`); PortableKit does (`host/hle/hle_media.cpp`: the waits, `sceDisplayGetVcount`), so the port
  needed no HLE of its own here. Our profile answers `sceKernelGetGPI` (`src/profile/pure_profile.cpp`: 0 as on
  retail, 1 under the test switch `PURE_TEST_UNLOCK_ALL`).
- The free-running modes are bounded by `FUN_088eda8c`'s GE sync: with a fast GPU backend they will reach the
  60 fps vblank rate; the vblank itself must still tick at 59.94 Hz on the virtual clock so `GetVcount` is sane.
- E4 (60 fps in locked modes) is not a one-instruction patch for us: the right change is to find what reads
  `param_1+0x116c` (the per-mode lock flag) and what advances per frame while locked. Callers of `sceDisplayGetVcount`:
  `FUN_0886511c`, `FUN_08865f7c` (debug overlay), `LoadingScreen_cpp__088822dc` (loading screen animation).
  Done as task 072 (D-017, "E4" below): the byte's readers are step 5 and the save dialog, and the race integrates dt.
- Input is read by `FUN_08898568` / `FUN_0889859c` (`sceCtrlReadBufferPositive`), not tied to pacing.

## The two lock fields (answered by the fidelity audit, task 035)
- `+0x116c` is set to 1 by the race backend's constructor (free-running frames: Single Race and Tournament) and back
  to 0 by its destructor and by the race managers of Free Play and the other 30-fps modes.
- `+0x117c` is FxScreen's countdown: the full-screen flash sets it to 2 on every frame it runs (an explosion near
  the camera, the ship put back on the track, the race-start fade), so a flash and the frame after it wait two
  vblanks. These are the race's two-vblank stretches, the game's own and PPSSPP's too (docs/fidelity.md; every
  writer: [What writes the two fields](history/fidelity.md#what-writes-the-two-fields)).

## E6: the flash lock cleared (task 070)
D-016: the player's Esc menu has a Flashes row (Video tab, Game section; `game.smooth_flashes`, `PURE_SMOOTH_FLASHES`;
patch 0019-game-option-rows), Smooth by default. With Smooth, `src/profile/enhancements.cpp` wraps `sceGeDrawSync`
(NID 0xB287BD61), which the end-of-frame routine calls once a frame at step 1, before step 5 reads the fields: when
the frame object (`*0x08A8E960`) is in user RAM and `+0x116c` is 1 (Single Race, Tournament), it stores 0 to `+0x117c`
first, so a flash frame takes the free path (`sceKernelDelayThreadCB(150)`) like any other. With `+0x116c` 0 (Time
Trial, Free Play, Zone, the frontend) nothing is written: their 30 fps is E4's question ("E4", below). No generated
code changes.
- The only reader of `+0x117c` in the corpus is `FUN_0886511c` (the load at 0x08865248, emitted twice in
  `generated/` as a branch delay slot; its decrement's store at 0x0886525C); the other stores are FxScreen's
  (`FUN_0882da04`, 0x0882E198) and the render manager's set-up (`RenderManager_cpp__088666c4`, 0x08866BC0). The only
  other `4476` in an address is `FUN_0889e5ac`'s constant 0x08A5117C, a string of the network error names, not the
  frame object.
- On the Vineta K start route (`tools/flash_check.sh`): with Original the fade waits two vblanks for 57 flips
  (5708 to 5764, 1.90 s); with Smooth none of flips 5708 to 6100 does, and the race clock starts 10.02 s after the
  fade's first flip (flip 6309) where it starts 10.04 s after it with Original (flip 6253): the same time in more
  flips, since the intro runs on the measured dt. A traced run shows one `sceGeDrawSync` a flip from the race's first
  frame on. TEAM SELECTION and the race load (to flip 5706) keep their two vblanks with either choice: the load's
  flips wait so with `+0x116c` 1 and the countdown 0, so their pace is not step 5's.
- Every tool run has Original unless it names the variable (`tools/purelib/port.py`'s `original_pacing`), so the
  suites, the HUD check and the sweep measure the PSP's pacing; `tools/flash_check.sh --race` has a swept race's
  stretches and laps with both. Task 070's run of Vineta K: Original, 4 stretches of 16 to 22 flips and laps of 59.6,
  64.1 and 56.4 s; Smooth, no stretch and laps of 62.9, 55.4 and 58.2 s (the mean 2.0% lower, inside the 5% the check
  allows; the follower's laps vary by more than that from lap to lap).

## E4: the 30-fps modes free-running (task 072)
D-017: the Esc menu's 30 fps modes row (Video tab, Game section, before Flashes; `game.sixty_fps`, `PURE_SIXTY_FPS`;
patch 0019-game-option-rows), 60 fps by default. In E6's `sceGeDrawSync` wrap and before E6's clear,
`src/profile/enhancements.cpp` stores 1 to the frame object's `+0x116c` when it reads 0 there while the race backend
lives (`DAT_08a8c5f4`, 0x08A8C5F4, and the frame object pointer both in user RAM). Time Trial, Free Play and Zone then
take step 5's free path as Single Race does; with Smooth E6 clears their flash countdown too, and with Original a
flash frame still waits two vblanks there. The frontend has no backend, so its byte is never written. No generated
code changes.
- The gate. `DAT_08a8c5f4` is 0 in the executable's .data; its only writers (Ghidra's references to it, and the stores
  at offset -14860 from 0x08A90000 in `generated/`) are the backend's constructor `BackendRoot_cpp__0880c068`, which
  stores the backend at 0x0880C0CC right after its 1 to `+0x116c` (0x0880C0C8), and its destructor
  `BackendRoot_cpp__0880c328`, which zeroes it at 0x0880C5CC (the byte at 0x0880C378). The other 25 references are
  reads.
- The byte's readers (the loads at offset 4460 in `generated/`): `FUN_0886511c` (0x08865240, step 5) and eight
  functions of MemStickUtil.cpp's save dialog, `FUN_088965e0`, `MemStickUtil_cpp__08896730`, `FUN_088968f4`,
  `MemStickUtil_cpp__08896b68`, `FUN_08896ea4`, `FUN_08897050`, `FUN_08897180` and `FUN_088972b8`, each of which
  saves it to `DAT_08b17c14` and stores 0 (the dialog runs at two vblanks; it calls `sceUtilitySavedataUpdate(2)`);
  the dialog driver `FUN_08897f20` (called at step 2), `FUN_08896d7c` and `FUN_08896e30` store the saved value back.
  Nothing else reads it. The race managers that store its 0 are `LinkObj_etc__08818d80` (SPFreePlay_RaceManager.cpp),
  `LinkObj_etc__08819a0c` (SPTimeTrial_RaceManager.cpp) and `LinkObj_etc__0881bc8c` (SPZone_RaceManager.cpp); every
  writer: [What writes the two fields](history/fidelity.md#what-writes-the-two-fields).
- What follows from step 5's code (read, not measured): a locked frame decrements the countdown even when it is 0
  (0x08865254), so it runs negative through a 30-fps race, and the hook never stores 0. With the option on from the
  race's start the byte is 1 at every step 5 and the countdown stays 0 outside a flash. Set to 60 fps in the menu
  during a 30-fps race, the race runs free at once with Smooth (E6 clears the countdown) but with Original only once a
  flash has counted down from 2; set back to Original, the byte stays 1 until the backend's destructor and the race
  ends at 60. A save dialog while the backend lives (the ghost's auto-load, `GhostShip_etc__0891e4cc` calling
  `MemStickUtil_cpp__08896b68`) runs free with the option on, the byte stored back to 1 the next frame; the port's
  savedata dialog does not read the update's vblank count.
- On the Time Trial route (`tools/framerate_check.sh`, Flashes Original in both): the frontend's flips 4000 to 5000
  have a median of 33.37 ms with either choice; the race's flips 6300 to 6900 33.37 ms and 29.97 flips a race-clock
  second with Original, 16.68 ms and 59.94 with 60 fps. The `on` line comes after flip 5704, in the race load after
  the TEAM SELECTION confirm (flip 5700): the backend is made there, the race's first frame is flip 5707 and the
  race-start fade waits two vblanks from 5708 to 5764 in both runs. The race clock starts at flip 6010 with Original
  and 6175 with 60 fps, 10.11 and 8.74 s after flip 5707: the route's Cross hold at flip 5900 comes 2.29 s sooner at
  60 fps, and with the hold moved to flip 6037 (where 5900 falls at 30 fps) the clock starts 10.04 s after 5707, as
  Single Race's does (above).
- A swept Time Trial of Vineta K (`tools/framerate_check.sh --race`, task 072's run): 29.98 flips a race-clock second
  with Original and 59.95 with 60 fps; the game clock (`DAT_08a8c3dc`) 0.9994 and 1.0001 s a virtual second; the
  standing start 42.1, 80.5, 124.2 and 174.4 km/h in the half seconds about 0.5, 1.0, 1.5 and 2.0 s of race clock
  with Original and 39.3, 77.5, 121.1 and 168.2 with 60 fps (2.8 to 6.2 km/h lower, each within the check's 5% or
  10 km/h; the first speed pad is at about 2.2 s); laps of 77.1, 69.8 and 65.2 s with 68 contacts against 65.5, 58.7 and 59.7 s with 44 (the follower reads
  its steering every 10 flips, twice as often at 60: its doing, not the game's speed).

## E8: the display rate (task 089)
D-022, as task 089's review amended it (2026-10-14): the Esc menu's Display rate row (Video tab, Game section, after
Texture detail; `game.display_rate`, `PURE_DISPLAY_RATE`; patch 0019-game-option-rows), Display by default, runs the
race's vblank at the display's refresh. Patch 0030-vblank-period makes the kernel's vblank period a runtime value
(`Kernel::set_vblank_period_us`, default `kVBlankPeriodUs`, 16683 us; a change applies from the next vblank, which
stays where it was due, and the count of vblanks stands), read by the tick, `last_vblank_us()`, the media HLE's frame
grid, vblank duration, hcount and vblank flag, and frame interpolation's game frame and rate (passed on at each flip);
the Metal shell asks for each picture one period after its frame's vblank. In E6's `sceGeDrawSync` wrap, before E4 and
E6, `src/profile/enhancements.cpp` sets the period to `round(1e6 / rate)` (the rate clamped to 240 Hz) when the row is
Display, the display's refresh (the window shell's `display_refresh()`, or the test switch `PURE_DISPLAY_HZ=N`) is
above 60.5 Hz and the race backend lives, and to the PSP's otherwise. "The race backend lives" is E4's gate:
`DAT_08a8c5f4` (0x08A8C5F4, stored by the backend's constructor in the race load, zeroed by its destructor) and the
frame object (`*0x08A8E960`) both in user RAM; not the lock byte `+0x116c`, which is 0 in the 30-fps modes at Original
and while the save dialog runs. So Single Race and Tournament run at the display's rate, Time Trial, Free Play and Zone
at it with the 30 fps modes row at 60 fps and at half of it at Original (two vblanks of the display's period: 60 on a
120 Hz display), and the frontend and the save dialog keep the PSP's cadence. One line a change, not a flip: `[pure]
display rate: off` (Original, or no display above 60.5 Hz), `[pure] display rate: 120 Hz in a race, the PSP's 59.94 Hz
outside one` (Display, outside a race: at start) and `[pure] display rate: 120 Hz (8333 us a vblank)` (the race load:
after flip 5700 on the Time Trial route). The game's speed is unchanged because its frame timer integrates measured dt
("The game's clock in a race", below).
- Why the frontend keeps the PSP's rate: task 089 first ran the period at the display's everywhere and compared shots
  at the same flip and at the same virtual time in both lanes of the main-menu route (out/e8probe/ on the Mac). Time
  drives the boot cards (SCEA, Studio Liverpool), the language screen's build-in, the flashing after the profile
  save's confirm (roughly) and the menus' typed help line: they match at the same virtual time. Frames drive the
  screens' build-in and build-out transitions: identical at the same flip at both rates, so twice as fast at 120. For
  example MAIN MENU's after the profile save, flips 4315 to 4341, is 0.90 s at 59.94 Hz and 0.45 s at 120. The frame
  count the timer keeps at `DAT_08a8c3d8` has two references in the corpus (its load and store in `FUN_08804390`) and
  is not passed on, so no one field slows the transitions; the review chose the race-only period instead.
- The race-start fade needs no hook: its two-vblank stretch doubles in flips and keeps its time. 1.902 s in 57 flips
  at 59.94; at 120, 1.883 s in 113 flips with the race-only period (the switch lands in the load, flips before the
  fade), 1.900 s in 114 with the period everywhere. FxScreen re-arms the countdown on every frame of a fade that dt
  times, so the countdown never halves it.
- On the Time Trial route (`tools/display_rate_check.sh`): the frontend's flips 4000 to 5000 have a median of 33.37 ms
  and 29.84 flips a virtual second in both lanes; the race's (race clock 1 to 6 s) 16.68 ms and 59.96 flips a
  race-clock second at 59.94, 8.33 ms and 120.00 at 120.
- A swept Time Trial of Vineta K (`tools/display_rate_check.sh --race`, three runs a lane in task 089, two of them with
  the period everywhere): 59.95 to 59.96 against 119.67 to 120.02 flips a race-clock second. The game clock
  (`DAT_08a8c3dc`) advances 1.0001 s a virtual second at 60 and 0.9962 at 120 (a guess, not checked: the float sum near
  1000 s rounds each 8.3 ms step down). The standing start is the same to 1.5 s (39.3, 77.5 and 121.1 km/h at 0.5, 1.0
  and 1.5 s against 38.9 to 39.2, 76.9 to 77.0 and 120.1 to 120.8). The first speed pad is not: its boost starts at
  2.152 s and 1266.83 m of track at 60, 2.144 s and 1266.32 m at 90 (one cell with `PURE_DISPLAY_HZ=90`), and 2.057 to
  2.067 s and 1262.20 to 1262.62 m at 120, on the same lateral line (z -96.8): 0.1 s and 4.6 m early at 120, the same
  in every run, and not a fixed frame-count lag (that would put 90 at about 2.10 s); not traced further. The 2.0 s bin
  then reads 168.2 km/h at 60 against 183.9 to 189.0 at 120. Mean laps of 61.97, 61.70 and 59.73 s at 60 against 58.70,
  57.03 and 58.70 at 120 (-5.3%, -7.6% and -1.7%), with 13.3 to 16.0 contacts a lap in both: the follower reads its
  steering every 10 flips, twice as often at 120, and its laps differ by 9% from run to run at one rate (lap 1: 60.5 and
  65.9 s). So the check bounds the flips, the game clock, the start to 1.5 s and the contacts, and reports the 2.0 s
  bin, the pad and the laps.
- In the window, on this Mac's 120 Hz display (`PURE_DISPLAY_RATE=1 tools/stutter_check.sh`, its budget doubled):
  PASS, 10 of 195 seconds with a frame over 25 ms, nine of them the sweep's results-panel shots every 30 flips after
  the race (165 to 199 ms each) and one in the race (25.9 ms, render). The `[perf]` lines of the race: 120.0 flips a
  second, frame avg 8.3 ms, max 9.5 ms at the median second and 13.2 at the 90th percentile, guest 1.4 and render
  6.9 ms. The Metal shell's `frame_rate_now` counts the last second's presents: 120.
- The Vulkan renderer's Frame rate row follows `game_rate()`: in a race at 120 it offers the game's own "120" and
  "Match display 120 Hz", nothing between (help: "Frames between the game's 120 a second"); outside a race, at the PSP's
  rate, its usual rates.
- Open: `kIdleVBlankLimit` (the kernel's deadlock report after 18000 vblanks with no thread to run) still counts
  vblanks, so in a race at 120 it comes after 2.5 minutes instead of 5; `sceDisplayGetFramePerSec` still answers 59.94
  (this game does not import it). Both are left as they are (scheduler code; no caller here).

## Frame structure (from `out/frame.txt`)
- `FUN_088ed190` is the GE init: `sceGeEdramGetAddr`, `sceKernelCreateEventFlag`, `sceGeSetCallback` (one callback
  set with signal/finish handlers that set the event flag), then an initial `sceGeListEnQueue` + `sceGeListSync`.
  This is the sceGu library pattern; the game links a sceGu-like layer, not raw GE commands scattered in game code.
- `FUN_088ed284` is the per-frame `sceGeListEnQueue` (display list start, stall address, callback id, args).
- `FUN_088eda8c` is `sceGuSync`-like: `sceGeListSync` then `sceGeDrawSync` with the mode arguments it receives.
- `FUN_088ef5a8` sets mode and frame buffer at init (`sceDisplaySetMode` + `sceDisplaySetFrameBuf`); `FUN_088ef650`
  and `FUN_088ef6b8` are the two swap variants (`sceDisplaySetFrameBuf` with different sync modes). The end-of-frame
  routine calls `FUN_088ef6b8`.
For the runtime this means: GE callbacks must be delivered as guest interrupts that set an event flag (Yakumo does
this), `sceGeListSync`/`sceGeDrawSync` must block until the list is done on the virtual clock, and
`sceDisplaySetFrameBuf` with the "next vblank" mode must take effect at the next vblank, not immediately.

## The game's clock in a race (task 046, 2026-10-07)
- **The frame timer.** `FUN_08804390`, once a frame: `dt = (low word of sceKernelGetSystemTimeWide - the last one) *
  scale`, clamped to 0..0.067 s (two flags at `DAT_08a8e964`/`DAT_08a8e965` force 1/30 or 1/60 instead; neither is
  set in a race); `FUN_08893284` hands it to every object, which sums it into its own clock (the frontend root's
  +0x44 is the one the race seed is taken from, docs/fidelity.md difference 13). The game's physics, camera and
  timers integrate this dt.
- **The port's frame times move in 1 ms steps.** The kernel's virtual clock advances by `kStarvationQuantumUs`
  (1000 us) every 20000 dispatches of the outer loop, so a frame measures 15683, 16683 or 17683 us at 60 fps (32366
  to 34366 us at 30 fps) where PPSSPP measures the vblank plus the frame's emulated CPU time (15957 to 17201 us in a
  Vineta K race second). Averaged over a second both are the vblank rate; frame by frame the game integrates
  different steps, which is all that parts the player's path from PPSSPP's on Karbonis (difference 14) and part of
  why the AI ships differ (difference 13). The test switch `PURE_TEST_RACE_CLOCK` (`src/profile/test_hooks.cpp`)
  replays PPSSPP's frame times for the scorecard.
- **The busy-time charge (task 051's finding).** The framework's kernel adds a thread's wall time to the virtual
  clock when it runs over 100 ms without a wait (`Kernel::charge_busy_time`, up to 250 ms), so on a loaded machine a
  headless run can take a step of 100 ms or more that a run on an idle one does not, and from there race another
  race. `PURE_NO_BUSY_CLOCK=1` (the framework's switch) turns the charge off; the shared runner (`tools/purelib`,
  task 050) sets it for every headless run of the tools, and a player's game keeps the charge.
- **The race load's length does not reach the race.** The race's two seeds are drawn at the TEAM SELECTION confirm,
  before the load; the load draws the same 2566 random numbers on both sides whether it takes 5 flips (the port) or
  34 (PPSSPP), the frame timer is not called while it runs, and the first frame after it is capped at 0.067 s on
  both. With the race clock pinned the port's shorter load (D-011) leaves the random sequence PPSSPP's for 20 s.

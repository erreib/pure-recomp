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
- Input is read by `FUN_08898568` / `FUN_0889859c` (`sceCtrlReadBufferPositive`), not tied to pacing.

## The two lock fields (answered by the fidelity audit, task 035)
- `+0x116c` is set to 1 by the race backend's constructor (free-running frames: Single Race and Tournament) and back
  to 0 by its destructor and by the race managers of Free Play and the other 30-fps modes.
- `+0x117c` is FxScreen's countdown: the full-screen flash sets it to 2 on every frame it runs (an explosion near
  the camera, the ship put back on the track, the race-start fade), so a flash and the frame after it wait two
  vblanks. These are the race's two-vblank stretches, the game's own and PPSSPP's too (docs/fidelity.md; every
  writer: [What writes the two fields](history/fidelity.md#what-writes-the-two-fields)).

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

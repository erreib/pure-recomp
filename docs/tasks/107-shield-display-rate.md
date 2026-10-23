# 107: The shield effect at the display's rate (GitHub issue 2)

Milestone: E8 (D-022) | Branch: task/107-shield-display-rate from batch/m2 | Status: OPEN

## Goal
GitHub issue 2 (2026-10-22, RussDCA, an M4 Pro Mac mini at 120 fps), "Infinite shield (visuals only)": in a race,
after a Shield is picked up the shell effect (the one that sweeps from the ship's nose back over it) does not show;
after the first wall contact it shows and never stops, for the rest of the race, on the player's ship and on the
opponents'. Damage still lands, so the shield itself ends on time and only the picture is stuck. Erik reproduced it
on the Mac (2026-10-23, Metal, internal scale 6, the HD pack, Texture detail and Smooth flashes on) and found it
follows the Display rate row: at Display (the race at 119.40 Hz) it sticks, at Original it behaves. When this task
is done the shield effect looks the same at Display as at Original, at any display rate the row runs, and nothing
else in the race changes.

The suspect (a guess, not read in the code): the effect steps its animation in whole 60 Hz frames taken from dt
(`(int)(dt * 60)` or the like), which is 1 at 60 Hz and 0 at 120, so the build-up never starts, the contact sets a
visible state outright, and the fade never advances. A vblank-count step or a test of a value for equality after
a dt-sized step would also fit. Find out which; do not assume it.

## Read first
- docs/timing.md: "E8: the display rate (task 089)" (what runs at the display's rate and why; frames drive the
  frontend's transitions) and "The game's clock in a race (task 046)" (`FUN_08804390`'s dt, clamped, in 1 ms steps
  on the port's clock; `FUN_08893284` hands it to every object).
- src/profile/enhancements.cpp, the E8 hook (the period set in the `sceGeDrawSync` wrap) and its gate (the race
  backend at `DAT_08a8c5f4`).
- src/profile/aspect.cpp: the function-override pattern (the generated body found through `Registrations`, the
  override registered once, why not before it is needed, the `[aspect]` lines).
- docs/tracks.md, "The shield": the shield value at `be::Ship` +0xF8 and the functions that touch it (that is the
  energy bar, not the pickup; read it for the ship object's layout and for `PURE_WATCH_SHIP`).
- config/function_labels.csv: `FUN_08946054` (`LinkObj.h;Shield.cpp`, the only function labelled from Shield.cpp;
  it is reached from the ship's update at 0x08924344), `FUN_0884bf3c` (`WeaponManager.cpp`).

## Facts
- The texture `in_game/effects/ship/absorb_surface` (an HD pack name) is first drawn in the race when a shield
  shows: likely the shell's. It is a lead to the draw, not proof.
- Ghidra is on the Mac: `tools/ghidra_headless.sh script Decompile <outfile> <hexaddr>...` and `script Callers`.
- `PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=N` runs the race at N Hz headless (docs/developing.md); `tools/run_boot.py
  --shell headless --shots DIR` writes frames headless. The Vineta K drive route (config/pad_scripts/drive/) races
  against seven opponents, who use shields.
- Game data and frames never enter the repository: keep shots under `out/107/`.

## Diagnosis (the planning session, 2026-10-23; Ghidra, `out/107/shield_methods.c` and `census.c`)
The suspect holds. `FUN_08946054` is the Shield's constructor: it makes the two shells (`vr_shield_cockpit.vex` at
+0x160, `vr_shield.vex` at +0x164), sets the vtable at +0x3c to `DAT_08ac2acc`, a current colour at +0x118..+0x124
and a target at +0x108..+0x114 (both from `.bss` the game fills at start: read them live), an ease of 0.15 at +0x128,
a scale of 0.7 at +0x130 easing to 1.0 (+0x12c) at 0.2 (+0x134), the dying flag +0xc4 and a clock +0x15c at 0. The
vtable's own methods are `FUN_08946834` (the destructor) and **`FUN_08946918`, the update, `(float dt in $f12,
Shield *this in $a0)`**:
```
n = (int)(dt / 0.016666668);                       // whole 60 Hz frames in this frame's dt, truncated
for (i = 0; i < n; i++) colour += 0.15 * (target - colour);         // +0x118..+0x124 toward +0x108..+0x114
for (i = 0; i < n; i++) scale  += 0.2  * (1.0 - scale);             // +0x130, only when n >= 1
pulse = sin(clock * 15); alpha = colour.a * (pulse * 0.25 + 0.75);  // then the shells' colour and matrix
clock += dt;                                                        // +0x15c, by the real dt
if (dying && colour.a <= 0.1) { delete this; return 0; } return 1;
```
On the port's clock a frame's dt moves in 1 ms steps (docs/timing.md, "The game's clock in a race"): 15.683, 16.683
or 17.683 ms at 59.94 Hz, so n is 1 on most frames (0 on the short ones, as the PSP's own 16.68 ms gives 1); at
119.40 Hz 7.4 to 9.4 ms, so **n is 0 on every frame** and neither the colour nor the scale ever moves. The shell
never builds up after a pickup, and once something sets its colour outright (the contact, most likely: confirm with
the trace) the fade to the dying test's 0.1 never runs, so the object is never deleted and shows for the rest of the
race. The same holds at any Display rate above about 62 Hz (the rig's 100 Hz included), and Original keeps it.
The clock at +0x15c takes the real dt, so an override that feeds the body a rounded-up dt must put +0x15c back
afterwards, and must not touch the object after a 0 return (deleted). The other way the brief allows, running the
body only once a whole 60 Hz frame of dt has gathered with the gathered dt, keeps the clock exact and returns 1 on
the frames it skips; the shells' pulse then moves at 60 Hz. Pick by what the trace shows.

**Census, first pass** (every function of the generated corpus that builds 1/60 (`0x3C888889`) and cuts a division
by it to an integer within 60 lines; then each decompiled: all ten have the shield's shape, `for (i = 0; i < (int)(dt
/ 0.016666668); i++)` easing a value, so all stall at the Display rate). Placed by their neighbours in
config/function_labels.csv, not by their own names:
| function | loops | neighbours |
|---|---|---|
| `FUN_08858ad0` | 2 | before Disruptor.cpp |
| `FUN_0885a010`, `FUN_0885a5bc`, `FUN_0885aad4`, `FUN_0885ae9c` | 1 each | DisruptorFx.cpp |
| `FUN_0886b274`, `FUN_0886bc6c` | 1 each | EngineFlare_Importer.cpp (the ships' engine flares) |
| `FUN_089379f8` | 4 | after FxLensflare.cpp, before FxWeather.cpp |
| `FUN_08945850`, `FUN_08945a80` | 1 each | between PsysDef.cpp and Shield.cpp |
| `FUN_08946918` | 2 | Shield.cpp (this task) |
Not covered: a step by `dt * 60` (no hit for 60.0 cut to an integer), a step by the vblank count, a frame counter
compared for equality, and anything the 60-line window misses. Deliverable 1's census starts from this table: confirm
what each drives, and widen the search where it is cheap.

## Deliverable
1. **The diagnosis** (in Result): confirm the Diagnosis above with the trace (the colour, the scale and the dying
   flag frame by frame at both rates, and what the contact writes), or correct it. Then a census: other functions
   that convert dt to whole frames, or step by the vblank count, in the same way (grep the decompile of the
   functions dt reaches through `FUN_08893284`'s callees as far as is cheap; list them with what they drive, and
   say which you looked at and which you did not). Do not fix those here; they are the next brief's.
2. **A trace**, `PURE_TRACE_SHIELD=1` (test-only, src/profile/): once a frame while a shield effect is live, the
   frame, the ship's index and the effect's step state (`[pure] shield frame N ship K ...`), so both rates can be
   compared from a headless run.
3. **The fix**, in src/profile/ only, by the aspect pattern: an override of the stepping function that makes the
   step follow time at any rate (for example carry the fraction of a 60 Hz frame from one call to the next, per
   effect, so two 119.40 Hz frames make one step, or run the generated body only when a whole 60 Hz frame of dt has
   gathered, whichever the code makes exact). Installed only while the display rate is above the PSP's, as E8's
   hook decides, so Original runs exactly the generated code. One line when it goes in (`[pure] shield step:
   ...`). An off switch: `PURE_SHIELD_STEP=0` keeps the generated code at Display (docs/developing.md row).
4. **A check**, `tools/shield_check.sh`: the drive route headless at Original and at `PURE_DISPLAY_HZ=120` with
   `PURE_TRACE_SHIELD=1`; PASS when every shield effect seen in the 120 lane builds up and ends, and its life in
   seconds is within 10% of the Original lane's median (or of the decompile's constant, if the routes do not line
   up). docs/verification.md row.
5. docs/timing.md: a subsection "The shield effect (task 107)" under E8 with the diagnosis, the fix and the
   census; docs/status.md: the E8 row and the Next bullet for issue 2.

## Acceptance criteria
- [ ] Result names the stepping code and the cause, with the decompiled lines.
- [ ] At 120 headless the trace shows the effect building up after a pickup and ending, as at Original.
- [ ] At Original the override is not registered (no `[pure] shield step` line) and the run's dispatches are
      unchanged (`tools/frame_regress.sh` headless and `tools/display_rate_check.sh --race`, PASS).
- [ ] `PURE_SHIELD_STEP=0` at 120 brings the stuck effect back (the trace shows it), so the switch is real.
- [ ] The census is in Result, with what was and was not looked at.

## Verify
`tools/build.sh profile && tools/shield_check.sh && python3 tools/docs_check.py`

## May touch
- src/profile/ (a new shield_step.cpp/.hpp, enhancements.cpp's install call, CMake's source list for it)
- tools/shield_check.sh, docs/timing.md, docs/developing.md, docs/verification.md, docs/status.md,
  docs/tasks/107-shield-display-rate.md, out/107/ (never committed)

## Must not touch
`vendor/`, `vendor/portablekit/include/psprecomp/`, `generated/`, the code generator, the kernel scheduler,
`tools/regen.sh`, `main`, src/gpu/ (it is not the renderer: Original draws it right).

## Estimated turns
50. Commit at each stage (the diagnosis in Result first, then the trace, then the fix and the check), so a stop at
the turn limit resumes from the branch.

## Escalate when
- The stepping is not in one function the override can wrap (it is inlined into the ship's update or a shared
  effect manager that also steps other effects): stop after the diagnosis, BLOCKED, with what a fix there would
  change.
- The cause is not a frame-sized step (the effect follows the vblank count through the kernel, or its life is set
  in flips by code outside the race): stop after the diagnosis, BLOCKED.
- The fix changes anything at Original, or any race figure `tools/display_rate_check.sh --race` bounds.

## Result
Status: DONE

Changed: src/profile/shield_step.cpp and .hpp (new: the trace and the override), src/profile/enhancements.cpp (the
install call in E8's GE-sync hook), src/profile/pure_profile.cpp (the trace's flip call), CMakeLists.txt (the source),
tools/shield_check.sh (new), docs/timing.md ("The shield effect (task 107)" under E8), docs/developing.md
(`PURE_SHIELD_STEP`, `PURE_TRACE_SHIELD`), docs/verification.md (two rows), docs/status.md (the E8 row, the issue 2
bullet), this file.

Acceptance:
- [x] The stepping code and the cause, with the decompiled lines: "Diagnosis" below.
- [x] At 120 headless the trace shows every effect building up after its pickup and ending (rise 0.250 s, deleted
  after 5.226 s), as at Original.
- [x] At Original nothing is registered (no `[pure] shield step` line in shield_check's lane 0 nor in
  display_rate_check's PSP lane), `tools/frame_regress.sh` headless PASS 18/18, `tools/display_rate_check.sh --race`
  PASS with the PSP lane's figures task 091's to the digit (59.95 flips a second, game clock 1.0001, the start
  39.3/77.5/121.1/168.2 km/h, the first pad from 2.152 s at 1266.83 m); its 120 lane, with the override in, PASS
  (119.42, 1.0010, 38.9/77.2/120.6, 14.3 contacts a lap, the pad -0.050 s and -2.53 m as in task 091).
- [x] `PURE_SHIELD_STEP=0` at 120 brings the stuck effect back (out/107/off120, below).
- [x] The census, with what was and was not looked at: below and in docs/timing.md.

Verify output (last 20 lines of `tools/verify_task.sh 107`):
```
  ship 4 from flip 15681 (t=358.469): deleted, life 5.323, rise 0.451, fade 0.334, steps 234
  ship 5 from flip 16768 (t=376.854): deleted, life 5.405, rise 0.368, fade 0.416, steps 212
lane 1 (120 Hz): the sweep PASS (no damage), 197 s; 13 effects (13 deleted); life of the deleted: median 5.226 s (5.224 to 5.227); rise median 0.251 (0.009 to 0.252); fade median 0.226 (0.225 to 0.234)
  ship 6 from flip 8416 (t=214.690): deleted, life 5.227, rise 0.251, fade 0.227, steps 313
  ship 1 from flip 8491 (t=215.317): deleted, life 5.225, rise 0.251, fade 0.226, steps 313
  ship 0 from flip 10062 (t=228.474): deleted, life 5.226, rise 0.250, fade 0.234, steps 313
  ship 2 from flip 11276 (t=238.642): deleted, life 5.226, rise 0.251, fade 0.226, steps 313
  ship 7 from flip 11672 (t=241.959): deleted, life 5.226, rise 0.009, fade 0.227, steps 313
  ship 3 from flip 13920 (t=261.137): deleted, life 5.226, rise 0.251, fade 0.226, steps 313
  ship 3 from flip 15631 (t=275.717): deleted, life 5.226, rise 0.250, fade 0.226, steps 313
  ship 5 from flip 15771 (t=276.890): deleted, life 5.226, rise 0.250, fade 0.234, steps 313
  ship 3 from flip 16849 (t=285.918): deleted, life 5.227, rise 0.252, fade 0.227, steps 313
  ship 1 from flip 17069 (t=287.762): deleted, life 5.225, rise 0.251, fade 0.225, steps 313
  ship 4 from flip 17517 (t=291.512): deleted, life 5.226, rise 0.251, fade 0.226, steps 313
  ship 7 from flip 18292 (t=298.004): deleted, life 5.224, rise 0.183, fade 0.225, steps 313
  ship 3 from flip 25991 (t=363.982): deleted, life 5.227, rise 0.252, fade 0.227, steps 313
  [pure] shield step: FUN_08946918 overridden, the shield effect eases in 60 Hz steps of the time while the race runs faster than the PSP's 59.94 Hz (now 119.40 Hz; PURE_SHIELD_STEP=0 keeps the generated code)
shield_check: PASS (lanes 0 and 1: 5 and 13 effects, median life 5.373 and 5.226 s, rise 0.434 and 0.251 s, fade 0.385 and 0.226 s)
docs_check: 40 files, 0 findings: PASS
verify 107: PASS
```
(Ship 7's rises of 0.009 and 0.183 s are contacts during the build-up: the flash sets the alpha to 1 outright.)

Window checks this change wants (not run: Erik's screen was not booked): a Single Race at Display on the 120 Hz
display, Metal, with Smooth flashes on (Erik's repro settings), watching an opponent's shield and the player's after a
pickup and a wall contact: the shell builds up, flashes at the contact and fades about 5 s after the pickup; the same
on Vulkan; and the row switched to Original in the Esc menu mid-race with a shield showing (the override then passes
the real dt; untested even headless). The rig's 100 Hz display takes the same look.

Open questions:
- Original's own easing on the port is slower than the PSP's: the port's 15.683 ms frames (a third of them at
  59.94 Hz, the 1 ms clock) take no step, so Original's rise and fade are 0.37 to 0.47 s against the PSP's 0.25 s
  (15 steps of 16.68 ms). Display now eases at the PSP's 60 steps a second, so the two rows differ by that much. A
  fix at Original would be the 1 ms clock's (Open calls, "a finer virtual-time answer"), not this task's.
- The ten other functions of the census stall the same way at Display (DisruptorFx's effects, the engine flares, the
  `~UNDERWATER` and `~WIND` emitters, `FUN_089379f8`); what each looks like on screen at 120 is not checked. The
  override here is specific to the Shield (its clock at +0x15c); a shared helper for the others would need each
  one's own dt uses read first.
- The `stepping` map is keyed by object address and pruned only when over 256 entries (a deleted effect's entry is
  stale until its address is reused, then reset by the clock test); harmless in a race, noted.

### Diagnosis (confirmed in the decompile, 2026-10-23; out/107/ on the Mac)
- **The stepping code** is `FUN_08946918`, the Shield's update, as the planning session read it. It is slot +0x24 of
  the vtable `DAT_08ac2acc` (the word at 0x08ac2af0 is 0x08946918), which the object walker `FUN_08893284(dt, obj)`
  calls once a frame (`(**(vtable + 0x24))(dt, obj + *(short *)(vtable + 0x20))`; a 0 return skips the object's
  children and its +0x2c method, and the object is marked dead, flags `| 10`). The decompiled lines:
  ```
  if (0 < (int)(param_1 / 0.016666668)) { do { colour(+0x118..+0x124) += *(+0x128) * (target(+0x108..) - colour);
      iVar4++; } while (iVar4 < (int)(param_1 / 0.016666668)); }
  if ((int)(param_1 / 0.016666668) >= 1) { do { scale(+0x130) += (*(+0x12c) - scale) * *(+0x134); ... } }
  fVar8 = sin(*(float *)(this + 0x15c) * 15.0);  alpha = colour.a * (fVar8 * 0.25 + 0.75);  ... shells ...
  *(float *)(this + 0x15c) = clock + param_1;
  if (*(char *)(this + 0xc4) != 0 && colour.a <= 0.1) { flags = flags & ~4 | 10; FUN_08893940(this); return 0; }
  return 1;
  ```
  `dt` (f12) feeds only the step count and the clock.
- **Who sets the state** (the planning session's "the contact, most likely" confirmed):
  - `LinkObj_h__0892425c(ship)` raises the shield: it kills the ship's earlier Shield at `ship + 0x9fc` (flags
    `| 10`), constructs a new one with `FUN_08946054(obj, ship)` (owner at +0xc0), stores it at `ship + 0x9fc` and plays
    `~SHIELD`. It is the constructor's only caller (0x08924344).
  - `FUN_08947030(shield)`, the contact: sets the colour outright to the flash colour from `.bss` `DAT_08b73fb8..fc4`
    and the scale to 1.1 (0x3f8ccccd). Called from the ship's update `FUN_08926ae4` (0x08927500) and `FUN_0892935c`
    (0x08929750), each with `ship + 0x9fc`.
  - `FUN_08947080(shield)`, the end: target colour 0 (all four), target scale (+0x12c) 1.2, dying flag +0xc4 = 1.
    Called from `FUN_089243ec(ship)` (the shield's end; it also stops the `~SHIELD` sound).
  - The constructor's colour is `DAT_08b73fc8..fd4` and its target `DAT_08b73fa8..fb4` (read live by the trace).
  - The destructor `FUN_08946834` puts the base vtable 0x08ac4838 back; nothing but the update reads +0x15c.
- **The cause**: at 119.40 Hz a frame's dt is 7.4 to 9.4 ms, so `n = (int)(dt / 0.016666668)` is 0 on every frame:
  the colour never eases from the constructor's towards the target (no build-up), a contact's flash colour stays as
  set, and after the end the colour never eases to the target 0, so `colour.a <= 0.1` never holds and the dying effect
  is never deleted: it shows for the rest of the race (until the ship raises another shield, which kills it). It is a
  frame-sized step in one function the override can wrap (no escalation condition).

### The sighting test (Original, 2026-10-23)
One headless Vineta K drive-route race, `PURE_TRACE_SHIELD=1 tools/campaign_sweep.py single_race vineta_k --out
out/107/sight0` (PASS, 3 laps, 194.0 s, 41 contacts; 3:22 wall). **8 Shield effects**, all AI ships (ship 6 four
times, ship 1 twice, ships 4 and 7 once), at race time 13.6, 57.7, 86.4, 98.4, 99.2, 100.3, 128.4 and 131.2 s (the
virtual time of each `new` line less the race start's, t=201.16 s at flip 6253). Every one built up and ended by its
own delete test: life (its clock) 5.22 to 5.42 s, the end called at about 4.99 s of it; the rise to 90% of the target's
alpha 0.37 to 0.47 s and the fade from the dying flag to the delete 0.23 to 0.43 s. The constructor's colour alpha is
0.000 and its target's 1.000; a contact puts the alpha at 1.000 and the scale at 1.100 (ship 7 at flip 12304). Enough
for the check's median rule: the check (below) runs this route in both lanes.
Found on the way: at Original the port's frames step on 1625 of 2571 traced frames (n=1) and not on 946 (n=0: the
15.683 ms frames of the port's 1 ms clock, docs/timing.md "The game's clock in a race"), so the port's Original eases
at about 38 steps a second where the PSP's 16.68 ms frames give about 60: its rise and fade take 15 steps (0.25 s at
60 a second) but 0.37 to 0.47 s here. Not this task's (Original must stay the generated code).

### The trace at both rates, and the switch (2026-10-23)
- The trace: `PURE_TRACE_SHIELD=1` (src/profile/shield_step.cpp, called from the profile's flip counter) scans user
  RAM for the be::Ship objects (vtable 0x08AC259C) and, once a flip, prints every ship's live Shield (the ship's
  +0x9fc, vtable 0x08AC2ACC, owner +0xc0 the ship, not dead): `[pure] shield frame N ship K obj 0x... t= clock= n=
  steps= a= target= scale= dying=`, a `new` line and an `end deleted|replaced|killed|gone life= rise= fade= steps=`
  line. It reads guest memory only (no registration), so a traced Original run has an untraced one's dispatches.
- Original (out/107/sight0): frame by frame the alpha climbs 0, 0.150, 0.278, 0.386 ... on the n=1 frames and holds on
  the n=0 ones (0.913 at clock 0.367 s); the scale 0.700, 0.760, 0.808 ...; at the end call (clock 4.987) the target
  goes to 0.000 and dying to 1, and the alpha falls 0.850, 0.722 ... 0.103, then the effect is deleted (clock 5.389).
- 120 with the fix (out/107/fix120, the player destroyed at 181 s without `--no-damage`): 16 effects, every one built
  up (rise 0.250 to 0.268 s) and was deleted (fade 0.226 to 0.243 s, life 5.225 to 5.244 s), 313 or 314 steps each
  (60 a second).
- 120 with `PURE_SHIELD_STEP=0` (out/107/off120; `[pure] shield step: off (PURE_SHIELD_STEP=0), ...`): 9 effects. The
  5 with no contact took 0 steps, never built up (`rise=-`) and were deleted on time (alpha 0 at the end: invisible,
  the issue's "does not show"). The 4 with a contact were stuck at alpha 1.000 and scale 1.100 (the flash, set
  outright) and lived 11.3, 11.4, 37.7 and 55.2 s, the issue's "never stops". They ended only through a full-screen
  flash's two-vblank frames (16.75 ms, n = 1; the tools run Flashes at Original): three of them at one flip (12727)
  after 14 such steps. With Smooth flashes, the default, nothing ends them.

### The fix and the check
- `src/profile/shield_step.cpp`: `FUN_08946918` overridden by the aspect pattern (the generated body found through
  `Registrations`, registered once from E8's hook in the GE sync at the first frame whose vblank period is under the
  PSP's 16683 us, never at Original). Each call carries its real dt per effect, takes the whole 60 Hz frames as the
  call's steps n, and hands the body a dt that gives n; the body's clock at +0x15c is put back to the generated code's
  value (the last call's clock plus its real dt, bit for bit) at the effect's next call, before its body runs. Not after
  `original()` returns: the generated body returns to the caller (the override) when a call inside it cannot chain,
  with the rest of the body still to run from the outer loop, and after a 0 return the object is dead and is not
  touched. At the PSP's period (the row back to Original in a race) the override hands the real dt.
- `tools/shield_check.sh` (docs/verification.md): both lanes of the drive route with `--no-damage`. PASS: 5 effects at
  Original (life median 5.371 s), 10 at 120 (life 5.225 to 5.227 s, rise 0.250 to 0.252 s, fade 0.226 to 0.235 s).
  The judge FAILs the `PURE_SHIELD_STEP=0` lane above (5 never built up; the medians of rise 2.290 and fade 0.000 s
  out of bounds; with a 0 lane of `deleted` effects its 4 long lives too).

### The census
In docs/timing.md, "The shield effect (task 107)". The planning session's ten are confirmed with the shield's shape
(`for (i = 0; i < (int)(dt / 0.016666668); i++)`): `FUN_08858ad0` (two models, a delete test), `FUN_0885a010`,
`FUN_0885a5bc`, `FUN_0885aad4` (DisruptorFx effects: a model's colour, a delete test), `FUN_0885ae9c` (a list of
parts), `FUN_0886b274` and `FUN_0886bc6c` (the engine flares), `FUN_089379f8` (four values), `FUN_08945850` and
`FUN_08945a80` (the `~UNDERWATER` and `~WIND` sound emitters' level). Widened (out/107/census.py over the whole corpus
and config/function_map.csv: 1/60, 1/30, 60.0 and 30.0 built in a register and a float-to-integer conversion within 60
lines): three more hits, none a step (`FUN_0881dd18` and `FUN_0887d9e8` minutes of a time's text, `FUN_0886e4f8` a
16-frame cycle from the backend's clock times 30). `sceDisplayGetVcount`: the end-of-frame routine, `FUN_08865f7c`
and the loading screen only. Not looked at: a constant from memory or built more than 24 lines before its use, a frame
counter compared for equality, what the 60-line window misses, and what each of the ten looks like at 120 on screen.

## Review
Verify rerun on batch/m2 after the merge (2026-10-23, `tools/verify_task.sh 107`): PASS. Lane 0 (59.94 Hz) 6 effects,
all deleted, life median 5.356 s, rise 0.425, fade 0.367; lane 1 (120 Hz) 9 effects, all deleted, life 5.226 s (5.225
to 5.244), rise 0.251, fade 0.226; docs_check PASS.
Spot-read: src/profile/shield_step.cpp's override (the carry per effect, the dt handed so that the body's own
`(int)(dt / 0.016666668)` is the carry's whole frames, the clock at +0x15c put back to the generated code's value at
the effect's next entry rather than after `original()`, since the body can leave through the outer loop mid-way, and
nothing touched after a deleting return), its install from E8's GE-sync hook only once the vblank period is under the
PSP's, and the trace's read-only scan; the hook sits after `display_rate()` sets the period, so the first fast frame
installs it. The pass-through at the PSP's period (the row put back to Original mid-race) is in the code and untested.
Merged: 427cc4b (2026-10-23).
Notes: the window checks in Result are owed to Erik's eye (a Single Race at Display on Metal and on Vulkan, an
opponent's shield and the player's after a pickup and a contact, and the row switched mid-race). Two findings for later
briefs: the port's Original eases slower than the PSP (the 1 ms clock's 15.683 ms frames take no step; Open calls), and
the census's ten other functions stall the same way at Display (DisruptorFx, the engine flares, the underwater and wind
emitters, FUN_089379f8), each needing its own dt uses read before a shared fix.

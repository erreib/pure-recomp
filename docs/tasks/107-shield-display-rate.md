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
Status: PARTIAL (in progress: the diagnosis below; the trace built, the sighting test, the fix and the check to come)

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

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
